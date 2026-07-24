import SwiftUI

/// History tab: month calendar + the selected day's visit cards, with backdated
/// logging and a clear-history action. Port of RN app/(tabs)/history.tsx.
struct HistoryView: View {
    @EnvironmentObject private var visits: VisitsStore
    @EnvironmentObject private var tabSwipe: TabSwipe

    @State private var scrollPos = ScrollPosition()
    @State private var selectedDay = DayKey.key()
    @State private var showPicker = false
    @State private var showClear = false
    @State private var visitToDelete: Visit?
    @State private var openBar: Bar?

    private var dayTotals: [String: Int] {
        visits.visits.reduce(into: [:]) { $0[$1.dayKey, default: 0] += $1.drinkTotal }
    }
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
                        HStack {
                            Text("History").font(.scaled(22, weight: .heavy)).foregroundStyle(.white)
                            Spacer()
                            if !visits.visits.isEmpty {
                                Menu {
                                    Button(role: .destructive) { showClear = true } label: {
                                        Label("Clear History", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.scaled(15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .glassSurface(radius: 12, bordered: true)
                                        .contentShape(Rectangle())
                                }
                            }
                        }
                        .padding(.bottom, 16)

                        MonthCalendar(selected: $selectedDay, dayTotals: dayTotals)

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DayKey.format(selectedDay))
                                    .font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                                if !dayVisits.isEmpty {
                                    Text("\(dayVisits.count) \(dayVisits.count == 1 ? "bar" : "bars") • \(dayTotal) \(dayTotal == 1 ? "drink" : "drinks")")
                                        .font(.scaled(14)).foregroundStyle(Palette.gray400)
                                }
                            }
                            Spacer()
                            if !isFutureDay {
                                Button { showPicker = true } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus").font(.scaled(13, weight: .semibold))
                                        Text("Add").font(.scaled(14, weight: .semibold))
                                    }
                                    .foregroundStyle(Palette.primary)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Capsule().fill(Palette.primary.opacity(0.15)))
                                    .overlay(Capsule().strokeBorder(Palette.primary.opacity(0.4), lineWidth: 1))
                                }
                                .buttonStyle(PressableScale())
                                .accessibilityLabel("Add drinks for this day")
                            }
                        }
                        .padding(.top, 16)

                        if dayVisits.isEmpty {
                            VStack(spacing: 8) {
                                Text("🍸").font(.scaled(36))
                                Text("No drinks logged this day.")
                                    .font(.scaled(14)).foregroundStyle(Palette.gray400)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(dayVisits) { v in
                                    VisitCard(visit: v,
                                              onDelete: { visitToDelete = v },
                                              onTap: { openBar = AppData.bar(id: v.barId) })
                                }
                            }
                            .padding(.top, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 104)
                }
                .scrollPosition($scrollPos)
                // Reset scroll once this page goes offscreen so the next visit
                // always starts at the top.
                .onChange(of: tabSwipe.page) { _, p in
                    if p != .history { scrollPos.scrollTo(edge: .top) }
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showPicker) {
            LogDayPicker(day: selectedDay).environmentObject(visits)
        }
        .sheet(item: $openBar) { bar in
            BarDetailSheet(bar: bar, day: selectedDay)
                .environmentObject(visits)
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
