import CloudKit
import Foundation

/// Thin async wrapper around the CloudKit public database for the friends
/// feature. Record types: `Profile`, `FriendRequest`, `Friendship`, `CheckIn`.
///
/// Trust model (public DB, creator-only writes):
/// - A friendship is one record per direction; each side only ever creates
///   records it owns. B accepting A's request = B creates `Friendship{B→A}`;
///   A's device later observes it and creates the mirror `Friendship{A→B}`.
/// - Pushes are CloudKit query subscriptions — no server involved. Alert text
///   comes from `Localizable.strings` keys with args pulled off the record.
///
/// Check-ins are fanned out client-side: one record per recipient
/// (`recipientID`), so a friend who was unchecked or removed never has a
/// record addressed to them and their subscription can never fire.
///
/// Requires queryable indexes (CloudKit dashboard) on: Profile.code,
/// FriendRequest.fromID/toID, Friendship.ownerID/friendID,
/// CheckIn.authorID/recipientID/ts (ts also sortable).
struct CloudKitSocial {
    static let containerID = "iCloud.com.normanhoang.nycgaybars"

    private let container = CKContainer(identifier: CloudKitSocial.containerID)
    private var db: CKDatabase { container.publicCloudDatabase }

    private enum RT {
        static let profile = "Profile"
        static let request = "FriendRequest"
        static let friendship = "Friendship"
        static let checkIn = "CheckIn"
    }

    // Deterministic IDs make subscription + friendship setup idempotent.
    // -v2 carries desiredKeys (fromID/fromName/toID) so a tapped request push
    // can show the Accept row from the payload; the un-versioned legacy sub is
    // deleted on next sync.
    static let requestSubID = "sub-friendrequest-incoming-v2"
    static let legacyRequestSubID = "sub-friendrequest-incoming"
    static let friendshipSubID = "sub-friendship-incoming"
    private static let checkInSubPrefix = "sub-checkin-"
    static func checkInSubID(friendID: String) -> String { checkInSubPrefix + friendID }

    static let checkInCategory = "FRIEND_CHECKIN"
    static let requestCategory = "FRIEND_REQUEST"

    // MARK: - Account / profile

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    /// Stable CloudKit user record name for the signed-in iCloud account.
    func myUserID() async throws -> String {
        try await container.userRecordID().recordName
    }

    // Custom record names may not start with "_" (user record names do),
    // hence the prefix.
    private func profileRecordID(_ userID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "profile-\(userID)")
    }

    func fetchProfile(userID: String) async throws -> FriendProfile? {
        do {
            return Self.profile(from: try await db.record(for: profileRecordID(userID)))
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        }
    }

    func createProfile(userID: String, displayName: String) async throws -> FriendProfile {
        // Regenerate on the (astronomically rare) code collision so two users
        // never share an invite code — lookupProfile takes the first match.
        var code = Social.generateFriendCode()
        var retries = 0
        while retries < 3, try await lookupProfile(code: code) != nil {
            code = Social.generateFriendCode()
            retries += 1
        }
        let rec = CKRecord(recordType: RT.profile, recordID: profileRecordID(userID))
        rec["userID"] = userID
        rec["displayName"] = displayName
        rec["code"] = code
        return Self.profile(from: try await db.save(rec))!
    }

    /// Rename own profile in place, preserving the friend `code`. Fetch-then-save
    /// so the existing record (and its code) is kept — not a fresh createProfile.
    func updateProfileName(userID: String, displayName: String) async throws -> FriendProfile {
        let rec = try await db.record(for: profileRecordID(userID))
        rec["displayName"] = displayName
        return Self.profile(from: try await db.save(rec))!
    }

    /// Rewrite the denormalized author/sender name copies I own after a rename,
    /// so friends stop seeing my old name. Best-effort; records are creator-owned.
    func renameOutgoingRequests(fromID: String, newName: String) async throws {
        let q = CKQuery(recordType: RT.request, predicate: NSPredicate(format: "fromID == %@", fromID))
        let recs = try await records(q)
        guard !recs.isEmpty else { return }
        for rec in recs { rec["fromName"] = newName }
        _ = try await db.modifyRecords(saving: recs, deleting: [])
    }

    func renameCheckIns(authorID: String, newName: String) async throws {
        let q = CKQuery(recordType: RT.checkIn, predicate: NSPredicate(format: "authorID == %@", authorID))
        let recs = try await records(q)
        guard !recs.isEmpty else { return }
        for rec in recs { rec["authorName"] = newName }
        _ = try await db.modifyRecords(saving: recs, deleting: [])
    }

    func lookupProfile(code: String) async throws -> FriendProfile? {
        let q = CKQuery(recordType: RT.profile, predicate: NSPredicate(format: "code == %@", code))
        return try await records(q, limit: 1).compactMap(Self.profile(from:)).first
    }

    /// Batch-fetch profiles by user ID (missing ones are silently dropped).
    func profiles(userIDs: [String]) async throws -> [FriendProfile] {
        guard !userIDs.isEmpty else { return [] }
        let results = try await db.records(for: userIDs.map(profileRecordID))
        return results.values.compactMap { try? Self.profile(from: $0.get()) }
    }

    // MARK: - Friend requests

    func sendRequest(from me: FriendProfile, to other: FriendProfile) async throws {
        let rec = CKRecord(recordType: RT.request,
                           recordID: .init(recordName: "request-\(me.id)-\(other.id)"))
        rec["fromID"] = me.id
        rec["fromName"] = me.displayName
        rec["toID"] = other.id
        try await saveIgnoringExisting(rec)
    }

    func incomingRequests(userID: String) async throws -> [FriendRequestItem] {
        let q = CKQuery(recordType: RT.request, predicate: NSPredicate(format: "toID == %@", userID))
        return try await records(q).compactMap(Self.request(from:))
    }

    func outgoingRequests(userID: String) async throws -> [FriendRequestItem] {
        let q = CKQuery(recordType: RT.request, predicate: NSPredicate(format: "fromID == %@", userID))
        return try await records(q).compactMap(Self.request(from:))
    }

    /// Delete an own outgoing request (creator-only write; no-op if gone).
    func deleteRequest(recordName: String) async throws {
        do {
            try await db.deleteRecord(withID: .init(recordName: recordName))
        } catch let e as CKError where e.code == .unknownItem {}
    }

    /// Delete my own request record to a user (deterministic name); no-op if
    /// gone. Used to clear a lingering request on unfriend so re-adding is clean.
    func deleteRequest(from: String, to: String) async throws {
        try await deleteRequest(recordName: "request-\(from)-\(to)")
    }

    // MARK: - Friendships (one record per direction)

    private func friendshipRecordID(ownerID: String, friendID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "friendship-\(ownerID)-\(friendID)")
    }

    func createFriendship(ownerID: String, friendID: String) async throws {
        // Delete any pre-existing record first so the save stamps a fresh
        // creationDate: the other side's handshake gate (acceptedOutgoing) only
        // trusts records newer than its request, and keeping a stale record's
        // date would leave the handshake permanently incompletable.
        try await removeFriendship(ownerID: ownerID, friendID: friendID)
        let rec = CKRecord(recordType: RT.friendship,
                           recordID: friendshipRecordID(ownerID: ownerID, friendID: friendID))
        rec["ownerID"] = ownerID
        rec["friendID"] = friendID
        try await saveIgnoringExisting(rec)
    }

    func removeFriendship(ownerID: String, friendID: String) async throws {
        do {
            try await db.deleteRecord(withID: friendshipRecordID(ownerID: ownerID, friendID: friendID))
        } catch let e as CKError where e.code == .unknownItem {}
    }

    /// Users I've added (my own Friendship records), with each record's
    /// server-stamped creationDate. A missing stamp maps to .distantPast so an
    /// undatable record can only ever read as stale, never as an acceptance.
    func friendIDs(ownerID: String) async throws -> [String: Date] {
        let q = CKQuery(recordType: RT.friendship, predicate: NSPredicate(format: "ownerID == %@", ownerID))
        return Self.datedIDs(try await records(q), key: "friendID")
    }

    /// Users who have added me (their Friendship records pointing at me),
    /// with creation dates — the handshake gate compares these against the
    /// outgoing request's date to tell an acceptance from a stale relic.
    func friendedByIDs(userID: String) async throws -> [String: Date] {
        let q = CKQuery(recordType: RT.friendship, predicate: NSPredicate(format: "friendID == %@", userID))
        return Self.datedIDs(try await records(q), key: "ownerID")
    }

    private static func datedIDs(_ recs: [CKRecord], key: String) -> [String: Date] {
        Dictionary(recs.compactMap { rec in
            (rec[key] as? String).map { ($0, rec.creationDate ?? .distantPast) }
        }, uniquingKeysWith: max)
    }

    // MARK: - Check-ins

    /// Broadcast presence: one small record per recipient, batch-saved. Returns
    /// the copies that actually saved plus the first per-record failure, if any
    /// — the ids come back even on a partial fan-out so the caller can retain
    /// them and still retract what landed.
    func createCheckIn(author: FriendProfile, bar: Bar, recipients: [String],
                       now: Date = Date()) async throws -> (saved: [CKRecord.ID], failure: Error?) {
        guard !recipients.isEmpty else { return ([], nil) }
        let records = recipients.map { recipient in
            let rec = CKRecord(recordType: RT.checkIn)
            rec["authorID"] = author.id
            rec["authorName"] = author.displayName
            rec["recipientID"] = recipient
            rec["barId"] = bar.id
            rec["barName"] = bar.name
            rec["ts"] = now
            return rec
        }
        // The public DB saves batches non-atomically and reports per-record
        // failures in the results, not as a thrown error — return them so a
        // partial fan-out doesn't read as success.
        let (saveResults, _) = try await db.modifyRecords(saving: records, deleting: [])
        var saved: [CKRecord.ID] = []
        var failure: Error?
        for (id, result) in saveResults {
            switch result {
            case .success: saved.append(id)
            case .failure(let error): failure = failure ?? error
            }
        }
        return (saved, failure)
    }

    /// Check-ins addressed to me inside the Tonight window, newest first.
    func tonightCheckIns(userID: String, now: Date = Date()) async throws -> [FriendCheckIn] {
        let cutoff = now.addingTimeInterval(-Social.tonightWindow)
        let q = CKQuery(recordType: RT.checkIn,
                        predicate: NSPredicate(format: "recipientID == %@ AND ts > %@", userID, cutoff as NSDate))
        q.sortDescriptors = [NSSortDescriptor(key: "ts", ascending: false)]
        return try await records(q).compactMap(Self.checkIn(from:))
    }

    /// Retract own check-ins addressed to one recipient (unfriend revoke).
    func deleteCheckIns(authorID: String, recipientID: String) async throws {
        let q = CKQuery(recordType: RT.checkIn,
                        predicate: NSPredicate(format: "authorID == %@ AND recipientID == %@",
                                               authorID, recipientID))
        let sent = try await records(q).map(\.recordID)
        guard !sent.isEmpty else { return }
        _ = try await db.modifyRecords(saving: [], deleting: sent)
    }

    /// A timestamp-matched removal that never found its records: CloudKit's
    /// query index hadn't caught up. Thrown rather than swallowed so the caller
    /// rolls the row back instead of hiding it over a delete that never
    /// happened (the copies would stay live in friends' feeds).
    struct CheckInRemovalFailed: Error {}

    /// Retract one fan-out of my own check-ins — every recipient copy plus the
    /// self-addressed one — so the check-in leaves friends' Tonight feeds.
    /// Fallback for fan-outs shared in an earlier launch, whose record names
    /// are no longer held: `createCheckIn` stamps every copy with a single
    /// `now`, so the fan-out is identified by a narrow window around that stamp
    /// (equality on a Double round-trip is fragile). Uses only the existing
    /// authorID/ts indexes. Retries across the query-index lag and throws if it
    /// never matches — prefer `deleteCheckIns(recordNames:)` when the ids are
    /// known, which needs no index at all.
    func deleteCheckIns(authorID: String, at ts: Date, attempts: Int = 4) async throws {
        let window = Social.checkInMatchWindow
        let q = CKQuery(recordType: RT.checkIn,
                        predicate: NSPredicate(format: "authorID == %@ AND ts >= %@ AND ts <= %@",
                                               authorID,
                                               ts.addingTimeInterval(-window) as NSDate,
                                               ts.addingTimeInterval(window) as NSDate))
        for attempt in 0..<max(attempts, 1) {
            let mine = try await records(q).map(\.recordID)
            if !mine.isEmpty {
                _ = try await db.modifyRecords(saving: [], deleting: mine)
                return
            }
            if attempt < attempts - 1 { try await Task.sleep(nanoseconds: 1_500_000_000) }
        }
        throw CheckInRemovalFailed()
    }

    /// Retract a fan-out by the record names retained from its create. No
    /// query, so it deletes correctly inside CloudKit's index lag — a
    /// just-shared check-in isn't queryable for seconds, and the query-based
    /// path above would match nothing.
    func deleteCheckIns(recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        let ids = recordNames.map { CKRecord.ID(recordName: $0) }
        let (_, deleteResults) = try await db.modifyRecords(saving: [], deleting: ids)
        for case .failure(let error) in deleteResults.values {
            // Already gone (TTL sweep, another device) is the outcome we wanted.
            if (error as? CKError)?.code == .unknownItem { continue }
            throw error
        }
    }

    /// Delete own check-in records past `Social.checkInTTL`.
    func deleteExpiredCheckIns(authorID: String, now: Date = Date()) async throws {
        let cutoff = now.addingTimeInterval(-Social.checkInTTL)
        let q = CKQuery(recordType: RT.checkIn,
                        predicate: NSPredicate(format: "authorID == %@ AND ts < %@", authorID, cutoff as NSDate))
        let stale = try await records(q).map(\.recordID)
        guard !stale.isEmpty else { return }
        _ = try await db.modifyRecords(saving: [], deleting: stale)
    }

    // MARK: - Subscriptions

    /// Reconcile server subscriptions with the current friend list:
    /// core request/friendship subs plus one check-in alert sub per un-muted
    /// friend. Idempotent; also removes check-in subs for unfriended or
    /// newly muted users.
    func syncSubscriptions(userID: String, subscribedFriendIDs: [String]) async throws {
        var wanted: [String: CKSubscription] = [
            Self.requestSubID: requestSubscription(userID: userID),
            Self.friendshipSubID: friendshipSubscription(userID: userID),
        ]
        for friendID in subscribedFriendIDs {
            let id = Self.checkInSubID(friendID: friendID)
            wanted[id] = checkInSubscription(friendID: friendID, userID: userID)
        }

        let existing = try await db.allSubscriptions()
        let existingIDs = Set(existing.map(\.subscriptionID))
        let toSave = wanted.filter { !existingIDs.contains($0.key) }.map(\.value)
        var toDelete = existing.map(\.subscriptionID).filter {
            $0.hasPrefix(Self.checkInSubPrefix) && wanted[$0] == nil
        }
        // One-time migration: drop the pre-desiredKeys request sub.
        if existingIDs.contains(Self.legacyRequestSubID) { toDelete.append(Self.legacyRequestSubID) }
        guard !toSave.isEmpty || !toDelete.isEmpty else { return }
        _ = try await db.modifySubscriptions(saving: toSave, deleting: toDelete)
    }

    /// Alert push when a friend shares a check-in addressed to me:
    /// "<name> is at <bar>". Scoped to recipientID so records addressed to
    /// other friends can never fire it.
    private func checkInSubscription(friendID: String, userID: String) -> CKQuerySubscription {
        let sub = CKQuerySubscription(recordType: RT.checkIn,
                                      predicate: NSPredicate(format: "authorID == %@ AND recipientID == %@",
                                                             friendID, userID),
                                      subscriptionID: Self.checkInSubID(friendID: friendID),
                                      options: .firesOnRecordCreation)
        let info = CKSubscription.NotificationInfo()
        info.alertLocalizationKey = "FRIEND_CHECKIN_ALERT"
        info.alertLocalizationArgs = ["authorName", "barName"]
        info.soundName = "default"
        info.desiredKeys = ["barId", "authorName", "barName"]
        info.category = Self.checkInCategory
        sub.notificationInfo = info
        return sub
    }

    /// Alert push for an incoming friend request.
    private func requestSubscription(userID: String) -> CKQuerySubscription {
        let sub = CKQuerySubscription(recordType: RT.request,
                                      predicate: NSPredicate(format: "toID == %@", userID),
                                      subscriptionID: Self.requestSubID,
                                      options: .firesOnRecordCreation)
        let info = CKSubscription.NotificationInfo()
        info.alertLocalizationKey = "FRIEND_REQUEST_ALERT"
        info.alertLocalizationArgs = ["fromName"]
        info.soundName = "default"
        // Carry the sender fields so a tapped request shows the Accept row
        // straight from the payload, before the record is queryable.
        info.desiredKeys = ["fromID", "fromName", "toID"]
        info.category = Self.requestCategory
        sub.notificationInfo = info
        return sub
    }

    /// Silent push when someone creates a Friendship pointing at me
    /// (acceptance signal) so the mirror record + subs can be reconciled.
    private func friendshipSubscription(userID: String) -> CKQuerySubscription {
        let sub = CKQuerySubscription(recordType: RT.friendship,
                                      predicate: NSPredicate(format: "friendID == %@", userID),
                                      subscriptionID: Self.friendshipSubID,
                                      options: .firesOnRecordCreation)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        sub.notificationInfo = info
        return sub
    }

    // MARK: - Helpers

    private func records(_ query: CKQuery, limit: Int = CKQueryOperation.maximumResults) async throws -> [CKRecord] {
        // Follow the continuation cursor: one call returns a single server page
        // (~a few hundred records), and silently truncating e.g. friendedByIDs
        // would make real friends look like removals.
        let unbounded = limit == CKQueryOperation.maximumResults
        let (firstPage, firstCursor) = try await db.records(matching: query, resultsLimit: limit)
        var all = firstPage.compactMap { try? $0.1.get() }
        var cursor = firstCursor
        while let c = cursor, unbounded || all.count < limit {
            let remaining = unbounded ? CKQueryOperation.maximumResults : limit - all.count
            let (page, next) = try await db.records(continuingMatchFrom: c, resultsLimit: remaining)
            all += page.compactMap { try? $0.1.get() }
            cursor = next
        }
        return all
    }

    /// Save that treats "already exists" as success (deterministic record IDs).
    private func saveIgnoringExisting(_ record: CKRecord) async throws {
        do {
            _ = try await db.save(record)
        } catch let e as CKError where e.code == .serverRecordChanged {}
    }

    private static func profile(from rec: CKRecord) -> FriendProfile? {
        guard let userID = rec["userID"] as? String,
              let name = rec["displayName"] as? String,
              let code = rec["code"] as? String else { return nil }
        return FriendProfile(id: userID, displayName: name, code: code)
    }

    private static func request(from rec: CKRecord) -> FriendRequestItem? {
        guard let fromID = rec["fromID"] as? String,
              let fromName = rec["fromName"] as? String,
              let toID = rec["toID"] as? String,
              creatorMatches(rec, claimedID: fromID) else { return nil }
        // Missing creation stamp → .distantFuture: nothing can postdate it, so
        // the request can never be auto-completed by a stale friendship record.
        return FriendRequestItem(id: rec.recordID.recordName, fromID: fromID, fromName: fromName,
                                 toID: toID, created: rec.creationDate ?? .distantFuture)
    }

    private static func checkIn(from rec: CKRecord) -> FriendCheckIn? {
        guard let authorID = rec["authorID"] as? String,
              let authorName = rec["authorName"] as? String,
              let barId = rec["barId"] as? String,
              let barName = rec["barName"] as? String,
              let ts = rec["ts"] as? Date,
              creatorMatches(rec, claimedID: authorID) else { return nil }
        return FriendCheckIn(id: rec.recordID.recordName, authorID: authorID, authorName: authorName,
                             barId: barId, barName: barName, date: ts)
    }

    /// Audit finding #1: reject records whose self-declared author/sender ID
    /// doesn't match CloudKit's system-stamped creator — an attacker can set a
    /// record field to any ID, but not `creatorUserRecordID`. Gated by
    /// `Social.verifyRecordCreator` (see FINDINGS.md) until verified against a
    /// second iCloud account; when off, this is a no-op. Own records read back
    /// report the creator as `__defaultOwner__`, so those are always allowed.
    private static func creatorMatches(_ rec: CKRecord, claimedID: String) -> Bool {
        guard Social.verifyRecordCreator else { return true }
        guard let creator = rec.creatorUserRecordID?.recordName else { return true }
        return creator == claimedID || creator == "__defaultOwner__"
    }
}
