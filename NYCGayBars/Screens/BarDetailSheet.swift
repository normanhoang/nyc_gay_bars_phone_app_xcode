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
                        Text(bar.neighborhood)
                            .font(.scaled(14, weight: .semibold))
                            .foregroundStyle(Palette.primary)
                            .padding(.top, 4)

                        if let tags = bar.tags, !tags.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.scaled(12, weight: .medium))
                                        .foregroundStyle(Palette.gray300)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.white.opacity(0.08)))
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                                }
                            }
                            .padding(.top, 8)
                        }

                        Button { showDirections = true } label: {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "location").font(.scaled(14))
                                    .foregroundStyle(Palette.gray400)
                                Text(bar.address).font(.scaled(14)).foregroundStyle(Palette.gray400)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)

                        if let desc = bar.description, !desc.isEmpty {
                            Text(desc).font(.scaled(14)).foregroundStyle(Palette.gray300)
                                .padding(.top, 12)
                        }

                        visitedToggle.padding(.top, 20)
                        // Presence broadcast is a deliberate, separate action —
                        // logging drinks never notifies anyone.
                        if social.onboarded && isTargetToday {
                            shareWithFriends.padding(.top, 12)
                        }
                        drinkCountBox.padding(.vertical, 16)

                        Text("Log a drink")
                            .font(.scaled(16, weight: .bold))
                            .foregroundStyle(.white)
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
            BadgeToast()
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

    private var visitedToggle: some View {
        Button(action: toggleVisited) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Visited").font(.scaled(16, weight: .semibold)).foregroundStyle(.white)
                    Text(visited ? "You've been here" : "Tap if you've been here")
                        .font(.scaled(12)).foregroundStyle(Palette.gray400)
                }
                Spacer()
                Image(systemName: visited ? "checkmark.square.fill" : "square")
                    .font(.scaled(28))
                    .foregroundStyle(visited ? Palette.green : Palette.gray500)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassSurface(radius: 16, bordered: true)
        }
        .buttonStyle(.plain)
    }

    private var shareWithFriends: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                HStack(spacing: 8) {
                    Image(systemName: sharedWithFriends ? "checkmark" : "person.2.fill")
                        .font(.scaled(15, weight: .semibold))
                    Text(sharedWithFriends ? "Shared with friends" : "Share with friends")
                        .font(.scaled(16, weight: .semibold))
                }
                .foregroundStyle(sharedWithFriends ? Palette.green : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassSurface(radius: 16, bordered: true)
            }
            .buttonStyle(.plain)
            .disabled(sharedWithFriends)

            if let shareError {
                Text(shareError).font(.scaled(12)).foregroundStyle(Palette.gray400)
            }
        }
    }

    private var drinkCountBox: some View {
        HStack {
            Text(isTargetToday ? "Today's drinks" : "Drinks on \(DayKey.format(targetDay))")
                .font(.scaled(14, weight: .medium)).foregroundStyle(.white)
            Spacer()
            CountUp(value: total, font: .scaled(24, weight: .heavy), color: Palette.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.primary.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.primary.opacity(0.3), lineWidth: 1))
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
