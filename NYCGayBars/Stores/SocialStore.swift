import Foundation
import CloudKit
import Combine

/// Friends-feature state: own profile, friends, requests, and the Tonight
/// feed, all backed by the CloudKit public database via `CloudKitSocial`.
/// Own profile + friends are cached in UserDefaults so relaunches don't
/// block on the network; everything else is fetched on demand.
@MainActor
final class SocialStore: ObservableObject {
    /// Single instance shared between the SwiftUI environment and AppDelegate
    /// push callbacks.
    static let shared = SocialStore()

    enum AccountState: Equatable {
        case unknown
        /// Device has no iCloud account (or iCloud is restricted) — feature disabled.
        case unavailable
        case ready
    }

    private static let profileKey = "@gaybars/socialProfile"
    private static let friendsKey = "@gaybars/socialFriends"

    @Published private(set) var accountState: AccountState = .unknown
    /// Nil until the user completes friends onboarding (picks a display name).
    @Published private(set) var profile: FriendProfile?
    @Published private(set) var friends: [FriendProfile] = []
    @Published private(set) var incomingRequests: [FriendRequestItem] = []
    @Published private(set) var outgoingRequests: [FriendRequestItem] = []
    @Published private(set) var tonight: [FriendCheckIn] = []
    @Published private(set) var busy = false
    /// Last operation error, for inline display in FriendsView.
    @Published var errorMessage: String?
    /// Bar to open from a tapped check-in notification (consumed by RootTabView).
    @Published var deepLinkBarId: String?

    private let ck = CloudKitSocial()
    private let defaults = UserDefaults.standard
    private var userID: String?

    init() {
        if let data = defaults.data(forKey: Self.profileKey),
           let cached = try? JSONDecoder().decode(FriendProfile.self, from: data) {
            profile = cached
            userID = cached.id
        }
        if let data = defaults.data(forKey: Self.friendsKey),
           let cached = try? JSONDecoder().decode([FriendProfile].self, from: data) {
            friends = cached
        }
    }

    var onboarded: Bool { profile != nil }

    // MARK: - Lifecycle

    /// Check iCloud, then pull everything fresh. Call on appear of FriendsView
    /// and from push handlers.
    func start() async {
        do {
            let status = try await ck.accountStatus()
            guard status == .available else {
                accountState = .unavailable
                return
            }
            accountState = .ready
            userID = try await ck.myUserID()
            if profile == nil {
                profile = try await ck.fetchProfile(userID: userID!)
                persistProfile()
            }
            guard onboarded else { return }
            await refresh()
            try? await ck.deleteExpiredCheckIns(authorID: userID!)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Re-fetch requests, friendships (completing any accepted handshakes),
    /// subscriptions, and the Tonight feed.
    func refresh() async {
        guard let me = userID, onboarded else { return }
        do {
            try await reconcileAcceptances(me: me)
            incomingRequests = try await ck.incomingRequests(userID: me)
            outgoingRequests = try await ck.outgoingRequests(userID: me)
            let ids = try await ck.friendIDs(ownerID: me)
            friends = try await ck.profiles(userIDs: ids).sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            persistFriends()
            try await ck.syncSubscriptions(userID: me, friendIDs: ids)
            tonight = try await ck.tonightCheckIns(friendIDs: ids)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Someone I sent a request to created their Friendship{them→me}:
    /// finish the handshake by creating the mirror and dropping the request.
    /// Only mirrors users I actually requested — a stranger creating a
    /// Friendship pointing at me is ignored.
    private func reconcileAcceptances(me: String) async throws {
        let outgoing = try await ck.outgoingRequests(userID: me)
        guard !outgoing.isEmpty else { return }
        let accepted = Set(try await ck.friendedByIDs(userID: me))
        for request in outgoing where accepted.contains(request.toID) {
            try await ck.createFriendship(ownerID: me, friendID: request.toID)
            try await ck.deleteRequest(recordName: request.id)
        }
    }

    // MARK: - Onboarding

    func createProfile(displayName rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let me = userID else { return }
        busy = true
        defer { busy = false }
        do {
            profile = try await ck.createProfile(userID: me, displayName: name)
            persistProfile()
            await refresh()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Friends

    /// Send a request by invite code. If that user already requested me,
    /// this accepts instead of sending a duplicate crossing request.
    func addFriend(code rawCode: String) async {
        errorMessage = nil
        guard let me = profile else { return }
        guard let code = Social.normalizeCode(rawCode) else {
            errorMessage = "That doesn't look like a friend code."
            return
        }
        busy = true
        defer { busy = false }
        do {
            guard let other = try await ck.lookupProfile(code: code) else {
                errorMessage = "No one has that code."
                return
            }
            guard other.id != me.id else {
                errorMessage = "That's your own code."
                return
            }
            guard !friends.contains(where: { $0.id == other.id }) else {
                errorMessage = "\(other.displayName) is already your friend."
                return
            }
            if let crossing = incomingRequests.first(where: { $0.fromID == other.id }) {
                await accept(crossing)
                return
            }
            try await ck.sendRequest(from: me, to: other)
            outgoingRequests = try await ck.outgoingRequests(userID: me.id)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    func accept(_ request: FriendRequestItem) async {
        guard let me = userID else { return }
        busy = true
        defer { busy = false }
        do {
            try await ck.createFriendship(ownerID: me, friendID: request.fromID)
            incomingRequests.removeAll { $0.id == request.id }
            await refresh()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Hide an incoming request locally (we can't delete the sender's record).
    func ignore(_ request: FriendRequestItem) {
        incomingRequests.removeAll { $0.id == request.id }
    }

    func removeFriend(_ friend: FriendProfile) async {
        guard let me = userID else { return }
        do {
            try await ck.removeFriendship(ownerID: me, friendID: friend.id)
            friends.removeAll { $0.id == friend.id }
            persistFriends()
            try await ck.syncSubscriptions(userID: me, friendIDs: friends.map(\.id))
            tonight.removeAll { $0.authorID == friend.id }
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Check-ins

    /// Broadcast presence at a bar. Returns true on success.
    @discardableResult
    func shareCheckIn(bar: Bar) async -> Bool {
        guard let me = profile else { return false }
        busy = true
        defer { busy = false }
        do {
            try await ck.createCheckIn(author: me, bar: bar)
            return true
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    func refreshTonight() async {
        guard onboarded else { return }
        do {
            tonight = try await ck.tonightCheckIns(friendIDs: friends.map(\.id))
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Push

    /// Route a CloudKit remote notification: friendship (silent) pushes finish
    /// handshakes; request/check-in alerts refresh the relevant state.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return }
        switch note.subscriptionID {
        case CloudKitSocial.friendshipSubID, CloudKitSocial.requestSubID:
            await start()
        case .some(let id) where id.hasPrefix("sub-checkin-"):
            await refreshTonight()
        default:
            break
        }
    }

    // MARK: - Helpers

    private func persistProfile() {
        if let profile, let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        }
    }

    private func persistFriends() {
        if let data = try? JSONEncoder().encode(friends) {
            defaults.set(data, forKey: Self.friendsKey)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure: return "No connection — try again."
            case .notAuthenticated: return "Sign in to iCloud in Settings to use Friends."
            case .requestRateLimited, .zoneBusy, .serviceUnavailable: return "iCloud is busy — try again in a moment."
            default: break
            }
        }
        return "Something went wrong — try again."
    }
}
