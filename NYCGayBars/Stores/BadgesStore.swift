import Foundation
import Combine

/// Badge state: computes badges from visits, persists first-earned timestamps,
/// and drives the unlock toast queue. Port of RN lib/BadgesContext.tsx.
final class BadgesStore: ObservableObject {
    private static let badgeDatesKey = "@gaybars/badgeDates"
    private static let toastSeconds: TimeInterval = 3.5

    /// All badges in definition order, with earn dates where earned.
    @Published private(set) var badges: [Badge] = []
    /// Badges earned since app start, oldest first — drives the unlock toast.
    @Published private(set) var unlocked: [Badge] = [] {
        didSet { armToastTimer() }
    }

    private var earnedAt: [String: String] = [:]
    private var firstReconcile = true
    private var toastTimer: Timer?
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: Self.badgeDatesKey),
           let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            earnedAt = stored
        }
    }

    /// Recompute badges for the given visits/visited set, stamping newly earned
    /// badges and dropping reverted ones. Call on visits/visited changes.
    func reconcile(visits: [Visit], visitedIds: Set<String>) {
        let all = Stats.badges(visits, visitedIds)

        var next = earnedAt
        var changed = false
        var newly: [Badge] = []

        for b in all {
            if b.earned && next[b.id] == nil {
                next[b.id] = DayKey.iso(Date())
                newly.append(b)
                changed = true
            } else if !b.earned && next[b.id] != nil {
                next.removeValue(forKey: b.id)
                changed = true
            }
        }

        if changed {
            earnedAt = next
            if let data = try? JSONEncoder().encode(earnedAt) {
                defaults.set(data, forKey: Self.badgeDatesKey)
            }
        }

        badges = all.map { b in
            var copy = b
            copy.earnedAt = earnedAt[b.id]
            return copy
        }

        if !newly.isEmpty && !firstReconcile {
            let queued = Set(unlocked.map { $0.id })
            let add = newly.filter { !queued.contains($0.id) }.map { b -> Badge in
                var copy = b
                copy.earnedAt = next[b.id]
                return copy
            }
            if !add.isEmpty {
                Haptics.success()
                unlocked.append(contentsOf: add)
            }
        }

        firstReconcile = false
    }

    /// Drop the first badge from the unlock queue.
    func dismissUnlocked() {
        if !unlocked.isEmpty { unlocked.removeFirst() }
    }

    private func armToastTimer() {
        toastTimer?.invalidate()
        guard !unlocked.isEmpty else { return }
        toastTimer = Timer.scheduledTimer(withTimeInterval: Self.toastSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.unlocked.isEmpty { self.unlocked.removeFirst() }
        }
    }
}
