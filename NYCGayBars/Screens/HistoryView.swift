import SwiftUI

/// History tab: month calendar + the selected day's visit cards, with backdated
/// logging and a clear-history action. Port of RN app/(tabs)/history.tsx.
struct HistoryView: View {
    @EnvironmentObject private var visits: VisitsStore

    @State private var selectedDay = DayKey.key()
    @State private var showPicker = false
    @State private var showClear = false
    @State private var visitToDelete: Visit?

    private var markedDays: Set<String> { Set(visits.visits.map { DayKey.key(iso: $0.date) }) }
    private var dayVisits: [Visit] { visits.getVisitsForDay(selectedDay) }
    private var dayTotal: Int { dayVisits.reduce(0) { $0 + $1.drinkTotal } }
    private var isFutureDay: Bool { DayKey.isFuture(selectedDay) }

    var body: some View {
        Group {
            if !visits.hydrated {
                Color.clear
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("History").font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                            .padding(.bottom, 16)

                        MonthCalendar(selected: $selectedDay, markedDays: markedDays)

                        Text(DayKey.format(selectedDay))
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .padding(.top, 16)
                        if !dayVisits.isEmpty {
                            Text("\(dayVisits.count) \(dayVisits.count == 1 ? "bar" : "bars") • \(dayTotal) \(dayTotal == 1 ? "drink" : "drinks")")
                                .font(.system(size: 14)).foregroundStyle(Palette.gray400)
                                .padding(.top, 2)
                        }
                        if !isFutureDay {
                            Button { showPicker = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle").font(.system(size: 18))
                                    Text("Add drinks for this day").font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundStyle(Palette.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.primary.opacity(0.15)))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.primary.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(PressableScale())
                            .padding(.top, 12)
                        }

                        if dayVisits.isEmpty {
                            VStack(spacing: 8) {
                                Text("🍸").font(.system(size: 36))
                                Text("No drinks logged this day.")
                                    .font(.system(size: 14)).foregroundStyle(Palette.gray400)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(dayVisits) { v in
                                    VisitCard(visit: v, onDelete: { visitToDelete = v })
                                }
                            }
                            .padding(.top, 16)
                        }

                        if !visits.visits.isEmpty {
                            Button { showClear = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash").font(.system(size: 18))
                                    Text("Clear History").font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundStyle(Palette.red)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.red.opacity(0.15)))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.red.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(PressableScale())
                            .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 104)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showPicker) {
            LogDayPicker(day: selectedDay).environmentObject(visits)
        }
        .overlay {
            if showClear {
                ConfirmDialog(
                    title: "Clear all history?",
                    message: "This can't be undone. Choose what to clear:",
                    actions: [
                        .init(label: "Drink history only", style: .destructive) {
                            visits.clearHistory(includeVisited: false)
                        },
                        .init(label: "Full reset (incl. visited)", style: .destructive) {
                            visits.clearHistory(includeVisited: true)
                        },
                        .init(label: "Cancel", style: .cancel) {},
                    ],
                    onDismiss: { withAnimation(.easeOut(duration: 0.2)) { showClear = false } })
            }
        }
        .animation(.easeOut(duration: 0.2), value: showClear)
        .overlay {
            if let v = visitToDelete {
                let barName = AppData.bar(id: v.barId)?.name ?? "this visit"
                ConfirmDialog(
                    title: "Delete visit?",
                    message: "Remove \(barName) from this day? This can't be undone.",
                    actions: [
                        .init(label: "Delete", style: .destructive) {
                            visits.clearVisit(v.id)
                        },
                        .init(label: "Cancel", style: .cancel) {},
                    ],
                    onDismiss: { withAnimation(.easeOut(duration: 0.2)) { visitToDelete = nil } })
            }
        }
        .animation(.easeOut(duration: 0.2), value: visitToDelete?.id)
    }
}
