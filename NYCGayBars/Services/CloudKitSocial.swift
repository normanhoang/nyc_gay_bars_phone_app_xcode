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
    static let requestSubID = "sub-friendrequest-incoming"
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
        let rec = CKRecord(recordType: RT.profile, recordID: profileRecordID(userID))
        rec["userID"] = userID
        rec["displayName"] = displayName
        rec["code"] = Social.generateFriendCode()
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

    // MARK: - Friendships (one record per direction)

    private func friendshipRecordID(ownerID: String, friendID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "friendship-\(ownerID)-\(friendID)")
    }

    func createFriendship(ownerID: String, friendID: String) async throws {
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

    /// IDs of users I've added (my own Friendship records).
    func friendIDs(ownerID: String) async throws -> [String] {
        let q = CKQuery(recordType: RT.friendship, predicate: NSPredicate(format: "ownerID == %@", ownerID))
        return try await records(q).compactMap { $0["friendID"] as? String }
    }

    /// IDs of users who have added me (their Friendship records pointing at me).
    func friendedByIDs(userID: String) async throws -> [String] {
        let q = CKQuery(recordType: RT.friendship, predicate: NSPredicate(format: "friendID == %@", userID))
        return try await records(q).compactMap { $0["ownerID"] as? String }
    }

    // MARK: - Check-ins

    /// Broadcast presence: one small record per recipient, batch-saved.
    func createCheckIn(author: FriendProfile, bar: Bar, recipients: [String], now: Date = Date()) async throws {
        guard !recipients.isEmpty else { return }
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
        _ = try await db.modifyRecords(saving: records, deleting: [])
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

    /// Delete own check-in records past the 24h TTL.
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
        let toDelete = existing.map(\.subscriptionID).filter {
            $0.hasPrefix(Self.checkInSubPrefix) && wanted[$0] == nil
        }
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
        let (results, _) = try await db.records(matching: query, resultsLimit: limit)
        return results.compactMap { try? $0.1.get() }
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
        return FriendRequestItem(id: rec.recordID.recordName, fromID: fromID, fromName: fromName, toID: toID)
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
