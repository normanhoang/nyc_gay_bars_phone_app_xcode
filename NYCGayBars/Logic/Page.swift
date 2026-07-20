import Foundation

/// The four root tabs, in the order they appear in the pager and tab bar.
/// Single source of truth for tab order — the pager, the tab bar and every
/// `tabSwipe.page` comparison derive from this, so reordering is a one-line
/// edit here rather than a hunt for integer literals across the screens.
enum Page: Int, CaseIterable, Hashable {
    case explore, friends, stats, history

    /// SF Symbol name for the tab bar.
    var icon: String {
        switch self {
        case .explore: "wineglass.fill"
        case .friends: "person.2.fill"
        case .stats: "chart.bar.fill"
        case .history: "calendar"
        }
    }

    var label: String {
        switch self {
        case .explore: "Explore"
        case .friends: "Friends"
        case .stats: "Stats"
        case .history: "History"
        }
    }
}
