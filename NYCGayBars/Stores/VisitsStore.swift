import Foundation
import Combine

/// Visit + drink state with on-device persistence. Port of RN
/// lib/VisitsContext.tsx. Persists to UserDefaults under the same keys.
final class VisitsStore: ObservableObject {
    private static let visitsKey = "@gaybars/visits"
    private static let visitedKey = "@gaybars/visited"

    /// All visits, most recent first.
    @Published private(set) var visits: [Visit] = []
    /// Bars manually marked "I've been here" (drink-logged bars not included).
    @Published private(set) var visitedBars: [String] = []
    /// True once persisted state has loaded (always true after init here).
    @Published private(set) var hydrated = false

    private let defaults = UserDefaults.standard

    init() {
        visits = decode([Visit].self, Self.visitsKey) ?? []
        visitedBars = decode([String].self, Self.visitedKey) ?? []
        hydrated = true
    }

    // MARK: - Persistence

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func saveVisits() {
        if let data = try? JSONEncoder().encode(visits) {
            defaults.set(data, forKey: Self.visitsKey)
        }
    }

    private func saveVisited() {
        if let data = try? JSONEncoder().encode(visitedBars) {
            defaults.set(data, forKey: Self.visitedKey)
        }
    }

    // MARK: - Queries

    /// A bar's visit on a given day (default today), or nil if none.
    func getVisitFor(_ barId: String, day: String? = nil) -> Visit? {
        let target = day ?? DayKey.key()
        return visits.first { $0.barId == barId && DayKey.key(iso: $0.date) == target }
    }

    func getVisitsForBar(_ barId: String) -> [Visit] {
        visits.filter { $0.barId == barId }
    }

    /// All visits on a given local day, most recent first.
    func getVisitsForDay(_ day: String) -> [Visit] {
        visits.filter { DayKey.key(iso: $0.date) == day }
    }

    /// All-time "been here" flag (marked or any drink logged).
    func isVisited(_ barId: String) -> Bool {
        visitedBars.contains(barId) || visits.contains { $0.barId == barId }
    }

    /// Set of all bar ids the user has ever visited.
    var visitedIds: Set<String> {
        Stats.computeVisitedIds(isVisited)
    }

    // MARK: - Mutations

    private func stampDate(for targetDay: String) -> String {
        targetDay == DayKey.key()
            ? DayKey.iso(Date())
            : DayKey.iso(DayKey.toDate(targetDay))
    }

    func logDrink(_ barId: String, _ rawType: String, day: String? = nil) {
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty else { return }
        let targetDay = day ?? DayKey.key()
        guard !DayKey.isFuture(targetDay) else { return }

        if let idx = visits.firstIndex(where: { $0.barId == barId && DayKey.key(iso: $0.date) == targetDay }) {
            var drinks = visits[idx].drinks
            if let di = drinks.firstIndex(where: { $0.type.lowercased() == type.lowercased() }) {
                drinks[di].count += 1
            } else {
                drinks.append(DrinkEntry(type: type, count: 1))
            }
            visits[idx].drinks = drinks
        } else {
            let v = Visit(id: DayKey.makeId(), barId: barId, date: stampDate(for: targetDay),
                          drinks: [DrinkEntry(type: type, count: 1)], note: nil)
            visits.insert(v, at: 0)
        }
        saveVisits()
    }

    func removeDrink(_ barId: String, _ rawType: String, day: String? = nil) {
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty else { return }
        let targetDay = day ?? DayKey.key()

        guard let idx = visits.firstIndex(where: { $0.barId == barId && DayKey.key(iso: $0.date) == targetDay })
        else { return }
        var drinks = visits[idx].drinks
        guard let di = drinks.firstIndex(where: { $0.type.lowercased() == type.lowercased() }) else { return }

        let nextCount = drinks[di].count - 1
        if nextCount <= 0 { drinks.remove(at: di) } else { drinks[di].count = nextCount }

        if drinks.isEmpty {
            visits.remove(at: idx)
        } else {
            visits[idx].drinks = drinks
        }
        saveVisits()
    }

    /// Set/clear the note on a bar's visit for a day; no-op without a visit.
    func setVisitNote(_ barId: String, day: String, note rawNote: String) {
        let note = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = visits.firstIndex(where: { $0.barId == barId && DayKey.key(iso: $0.date) == day })
        else { return }
        if (visits[idx].note ?? "") == note { return }
        visits[idx].note = note.isEmpty ? nil : note
        saveVisits()
    }

    func clearVisit(_ visitId: String) {
        visits.removeAll { $0.id == visitId }
        saveVisits()
    }

    /// Clear logged drink history. If includeVisited, also wipe visited marks.
    func clearHistory(includeVisited: Bool) {
        visits = []
        saveVisits()
        if includeVisited {
            visitedBars = []
            saveVisited()
        }
    }

    /// Toggle the visited flag. Setting true records a zero-drink check-in for
    /// `day` (default today). Setting false clears the bar's drink-days.
    func setVisited(_ barId: String, _ visited: Bool, day: String? = nil) {
        if visited {
            if !visitedBars.contains(barId) { visitedBars.append(barId) }
            saveVisited()

            let targetDay = day ?? DayKey.key()
            let existing = visits.contains { $0.barId == barId && DayKey.key(iso: $0.date) == targetDay }
            if !existing && !DayKey.isFuture(targetDay) {
                let checkIn = Visit(id: DayKey.makeId(), barId: barId,
                                    date: stampDate(for: targetDay), drinks: [], note: nil)
                visits.insert(checkIn, at: 0)
                saveVisits()
            }
        } else {
            visitedBars.removeAll { $0 == barId }
            saveVisited()
            visits.removeAll { $0.barId == barId }
            saveVisits()
        }
    }
}
