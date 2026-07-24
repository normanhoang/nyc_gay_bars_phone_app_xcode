import SwiftUI
import UIKit

/// Full bar-logging UI, presented as a sheet. Logs today by default, or against
/// `day` for backdated entry. Port of RN components/BarDetailSheet.tsx.
struct BarDetailSheet: View {
    let bar: Bar
    /// Log against this past day instead of today.
    var day: String?
    /// When shown in-place (the log/[day] flow) rather than as a sheet, the
    /// host supplies its own close handler.
    var onClose: (() -> Void)?

    @EnvironmentObject private var visits: VisitsStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var badges: BadgesStore
    @Environment(\.dismiss) private var dismiss

    @State private var noteDraft = ""
    @State private var showRemoveAlert = false
    @State private var showDirections = false
    @State private var sharedWithFriends = false
    @State private var shareError: String?

    private var targetDay: String { day ?? DayKey.key() }
    private var isTargetToday: Bool { targetDay == DayKey.key() }
    private var visit: Visit? { visits.getVisitFor(bar.id, day: targetDay) }
    private var total: Int { visit?.drinkTotal ?? 0 }
    private var visited: Bool { visits.isVisited(bar.id) }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
            VStack(spacing: 0) {
                grabber
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(bar.name)
                            .font(.scaled(24, weight: .heavy))
                            .foregroundStyle(.white)
                        metaLine.padding(.top, 4)

                        if let desc = bar.description, !desc.isEmpty {
                            Text(desc).font(.scaled(14)).foregroundStyle(Palette.gray300)
                                .padding(.top, 12)
                        }

                        actionRow.padding(.top, 16)
                        if let shareError {
                            Text(shareError).font(.scaled(12)).foregroundStyle(Palette.gray400)
                                .padding(.top, 6)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Log a drink")
                                .font(.scaled(16, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer()
                            HStack(spacing: 4) {
                                Text(isTargetToday ? "Tonight:" : "This day:")
                                    .font(.scaled(13)).foregroundStyle(Palette.gray400)
                                CountUp(value: total, font: .scaled(16, weight: .heavy), color: Palette.primary)
                                Text("🍹").font(.scaled(13))
                            }
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 12)
                        DrinkLogger(
                            visit: visit,
                            onLog: { visits.logDrink(bar.id, $0, day: targetDay) },
                            onRemove: { visits.removeDrink(bar.id, $0, day: targetDay) })

                        notesSection.padding(.top, 20)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            // Push below the grabber so the banner sits fully inside the sheet
            // instead of being clipped by its top edge.
            BadgeToast()
                .padding(.top, 52)
        }
        .presentationDragIndicator(.hidden)
        .confirmationDialog("Get directions", isPresented: $showDirections, titleVisibility: .visible) {
            Button("Apple Maps") { openMaps(google: false) }
            Button("Google Maps") { openMaps(google: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Open directions to \(bar.name) in:") }
        .overlay {
            if showRemoveAlert {
                let n = visits.getVisitsForBar(bar.id).count
                ConfirmDialog(
                    title: "Mark as never visited?",
                    message: "This will remove \(n) logged drink-day\(n == 1 ? "" : "s") for \(bar.name).",
                    actions: [
                        .init(label: "Remove", style: .destructive) { visits.setVisited(bar.id, false) },
                        .init(label: "Cancel", style: .cancel) {},
                    ],
                    onDismiss: { withAnimation(.easeOut(duration: 0.2)) { showRemoveAlert = false } })
            }
        }
        .animation(.easeOut(duration: 0.2), value: showRemoveAlert)
        .onAppear { noteDraft = visit?.note ?? "" }
        .onChange(of: visit?.id) { _, _ in noteDraft = visit?.note ?? "" }
        // Own a toast layer while visible so the root toast defers to this one.
        .onAppear { badges.pushToastModal() }
        .onDisappear { badges.popToastModal() }
    }

    private var grabber: some View {
        HStack {
            Spacer()
            Button { commitNote(); if let onClose { onClose() } else { dismiss() } } label: {
                Image(systemName: "xmark").font(.scaled(20)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassSurface(radius: 18)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 40, height: 6).padding(.top, 0)
        }
    }

    /// One-line header meta: neighborhood · street · tags (redesign 6a).
    private var metaLine: some View {
        let street = bar.address.components(separatedBy: ",").first ?? bar.address
        let tags = (bar.tags ?? []).map { " · \($0)" }.joined()
        return (Text(bar.neighborhood).fontWeight(.semibold).foregroundStyle(Palette.primary)
            + Text(" · \(street)\(tags)").foregroundStyle(Palette.gray400))
            .font(.scaled(13))
            .lineLimit(2)
    }

    /// Equal-width Directions / Share / Visited chips (redesign 6a).
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button { showDirections = true } label: {
                chipLabel("location.fill", "Directions", tint: nil)
            }
            .buttonStyle(PressableScale())

            // Presence broadcast is a deliberate, separate action — logging
            // drinks never notifies anyone. Hidden until at least one friend
            // is send-enabled (and hides again at 0).
            if social.canShareCheckIns && isTargetToday {
                Button {
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
                } label: {
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

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes").font(.scaled(16, weight: .bold)).foregroundStyle(.white)
            if visit != nil {
                TextField("", text: $noteDraft,
                          prompt: Text("How was the night?…").foregroundStyle(Palette.gray400),
                          axis: .vertical)
                    .lineLimit(3...)
                    .foregroundStyle(.white)
                    .font(.scaled(16))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: 80, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    .onChange(of: noteDraft) { _, _ in commitNote() }
            } else {
                Text("Log a drink to add a note about this visit.")
                    .font(.scaled(14)).foregroundStyle(Palette.gray500)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
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
            showRemoveAlert = true
        } else {
            Haptics.light()
            visits.setVisited(bar.id, false)
        }
    }

    private func commitNote() {
        if visit != nil { visits.setVisitNote(bar.id, day: targetDay, note: noteDraft) }
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
