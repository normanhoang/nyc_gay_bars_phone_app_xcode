import Foundation
import Combine

/// Search-box state with NYC ZIP interception: typing a recognized ZIP fires
/// `onZip` with the nearest bar neighborhood, clears the field, and surfaces a
/// transient confirmation note. Port of RN lib/useZipQuery.ts.
@MainActor
final class ZipQuery: ObservableObject {
    @Published var query = ""
    @Published var zipNote: String?

    /// Runs the screen's normal neighborhood-selection path.
    var onZip: (String) -> Void = { _ in }

    private var dismissTask: Task<Void, Never>?

    func change(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let hood = Geo.neighborhoodForZip(trimmed) {
            onZip(hood)
            query = ""
            setNote("\(trimmed) → \(hood)")
            return
        }
        query = text
        zipNote = nil
    }

    private func setNote(_ note: String) {
        zipNote = note
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { self?.zipNote = nil }
        }
    }
}
