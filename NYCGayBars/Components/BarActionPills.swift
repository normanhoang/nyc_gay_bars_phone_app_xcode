import SwiftUI
import UIKit

/// Equal-width Directions / Share / Visited chips for a bar (redesign 6a),
/// shared by `BarDetailSheet` and `QuickLogSheet`.
///
/// The destructive un-visit confirmation is *not* owned here: `ConfirmDialog`
/// dims the whole surface behind it, so it has to be rendered at the host
/// sheet's root — this view reports the intent via `onConfirmUnvisit` instead.
struct BarActionPills: View {
    let bar: Bar
    /// Day the Visited mark applies to; nil means today.
    var day: String?
    /// Un-visiting would discard logged drink-days — host confirms first.
    var onConfirmUnvisit: () -> Void

    @EnvironmentObject private var visits: VisitsStore
    @EnvironmentObject private var social: SocialStore

    @State private var showDirections = false
    @State private var sharedWithFriends = false
    @State private var shareError: String?

    private var targetDay: String { day ?? DayKey.key() }
    private var isTargetToday: Bool { targetDay == DayKey.key() }
    private var visited: Bool { visits.isVisited(bar.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { showDirections = true } label: {
                    chipLabel("location.fill", "Directions", tint: nil)
                }
                .buttonStyle(PressableScale())
                // Anchored to this button, not the row: iOS 26 draws the tail
                // at the centre of whatever view carries the modifier, which on
                // the row reads as pointing at Share.
                .confirmationDialog("Get directions", isPresented: $showDirections,
                                    titleVisibility: .visible) {
                    Button("Apple Maps") { openMaps(google: false) }
                    Button("Google Maps") { openMaps(google: true) }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Open directions to \(bar.name) in:") }

                // Presence broadcast is a deliberate, separate action — logging
                // drinks never notifies anyone. Hidden until at least one friend
                // is send-enabled (and hides again at 0).
                if social.canShareCheckIns && isTargetToday {
                    Button(action: share) {
                        chipLabel(sharedWithFriends ? "checkmark" : "person.2.fill",
                                  sharedWithFriends ? "Shared" : "Share",
                                  tint: sharedWithFriends ? Palette.green : nil)
                    }
                    .buttonStyle(PressableScale())
                    .disabled(sharedWithFriends)
                }

                Button(action: toggleVisited) {
                    chipLabel("checkmark", "Visited", tint: visited ? Palette.green : nil)
                }
                .buttonStyle(PressableScale())
            }
            if let shareError {
                Text(shareError).font(.scaled(12)).foregroundStyle(Palette.gray400)
            }
        }
        // Quick Log can swap the bar underneath us; a "Shared" chip belonging to
        // the previous bar would be a lie.
        .onChange(of: bar.id) { _, _ in
            sharedWithFriends = false
            shareError = nil
        }
    }

    /// Pill chip content: tinted fill/border when `tint` is set, glass otherwise.
    @ViewBuilder
    private func chipLabel(_ icon: String, _ label: String, tint: Color?) -> some View {
        let content = HStack(spacing: 6) {
            Image(systemName: icon).font(.scaled(13, weight: .semibold))
            Text(label).font(.scaled(14, weight: .semibold))
        }
        .foregroundStyle(tint ?? .white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)

        if let tint {
            content
                .background(Capsule().fill(tint.opacity(0.14)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
        } else {
            content.glassSurface(radius: 999, bordered: true)
        }
    }

    private func share() {
        guard !sharedWithFriends else { return }
        Haptics.light()
        shareError = nil
        Task {
            if await social.shareCheckIn(bar: bar) {
                Haptics.success()
                sharedWithFriends = true
            } else {
                shareError = social.errorMessage ?? "Couldn't share — try again."
            }
        }
    }

    private func toggleVisited() {
        if !visited {
            Haptics.light()
            visits.setVisited(bar.id, true, day: targetDay)
            return
        }
        if visits.getVisitsForBar(bar.id).count > 0 {
            onConfirmUnvisit()
        } else {
            Haptics.light()
            visits.setVisited(bar.id, false)
        }
    }

    private func openMaps(google: Bool) {
        let lat = bar.latitude, lng = bar.longitude
        let encoded = "\(bar.name), \(bar.address)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = google
            ? "https://www.google.com/maps/dir/?api=1&destination=\(encoded)"
            : "https://maps.apple.com/?daddr=\(lat),\(lng)&q=\(bar.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
    }
}
