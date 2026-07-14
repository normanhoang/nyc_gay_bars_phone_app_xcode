import Foundation

/// A user's public friends-feature profile (CloudKit `Profile` record).
/// `id` is the owner's CloudKit user record name. Codable so the own profile
/// and friends list can be cached in UserDefaults for instant/offline launch.
struct FriendProfile: Identifiable, Equatable, Codable {
    let id: String
    let displayName: String
    /// Short invite code others enter to send this user a friend request.
    let code: String
}

/// An incoming/outgoing friend request (CloudKit `FriendRequest` record).
struct FriendRequestItem: Identifiable, Equatable {
    /// CloudKit record name (needed so the sender can delete it).
    let id: String
    let fromID: String
    let fromName: String
    let toID: String
    /// Server-stamped creation date; a Friendship record only counts as this
    /// request's acceptance if it was created after this.
    let created: Date
}

/// A friend's shared check-in, decoded from a CloudKit `CheckIn` record.
struct FriendCheckIn: Identifiable, Equatable {
    let id: String
    let authorID: String
    let authorName: String
    let barId: String
    let barName: String
    let date: Date
}
