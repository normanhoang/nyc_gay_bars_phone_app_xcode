import SwiftUI

/// Month grid for the History screen. Selected day is a primary circle, today
/// gets a ring, days with visits get a dot scaled to the night's size, future
/// days are dimmed. A bottom strip summarizes the shown month.
struct MonthCalendar: View {
    @Binding var selected: String          // dayKey "y-m-d" (month 0-indexed)
    let dayTotals: [String: Int]           // dayKey → drink total (0 = check-in only)

    @State private var month: Int = 0      // 0-indexed
    @State private var year: Int = 2026

    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    private func key(_ y: Int, _ m: Int, _ d: Int) -> String { "\(y)-\(m)-\(d)" }

    private var monthTitle: String {
        let f = DateFormatter()
        return "\(f.monthSymbols[month]) \(year)"
    }

    private var daysInMonth: Int {
        var c = DateComponents(); c.year = year; c.month = month + 1; c.day = 1
        let cal = Calendar.current
        let date = cal.date(from: c)!
        return cal.range(of: .day, in: .month, for: date)!.count
    }

    private var leadingBlanks: Int {
        var c = DateComponents(); c.year = year; c.month = month + 1; c.day = 1
        let date = Calendar.current.date(from: c)!
        return Calendar.current.component(.weekday, from: date) - 1  // 0=Sun
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { step(-1) } label: {
                    Image(systemName: "chevron.left").foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Previous month")
                Spacer()
                Text(monthTitle)
                    .font(.scaled(16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { step(1) } label: {
                    Image(systemName: "chevron.right").foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Next month")
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.scaled(12, weight: .semibold))
                        .foregroundStyle(Palette.gray500)
                        .frame(maxWidth: .infinity)
                }
            }

            let cells = Array(0..<(leadingBlanks + daysInMonth))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(cells, id: \.self) { i in
                    if i < leadingBlanks {
                        Color.clear.frame(height: 44)
                    } else {
                        dayCell(i - leadingBlanks + 1)
                    }
                }
            }

            monthSummary
        }
        .padding(16)
        .contentPanel()
        .onAppear(perform: syncToSelected)
    }

    /// Bottom strip: shown month's totals + dot-size legend (redesign 5a).
    private var monthSummary: some View {
        let monthKeys = dayTotals.keys.filter { $0.hasPrefix("\(year)-\(month)-") }
        let days = monthKeys.count
        let drinks = monthKeys.reduce(0) { $0 + (dayTotals[$1] ?? 0) }
        let name = DateFormatter().monthSymbols[month]
        return VStack(spacing: 10) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack {
                (Text("\(name): ").foregroundStyle(Palette.gray400)
                    + Text("\(days) drink-\(days == 1 ? "day" : "days") · \(drinks) \(drinks == 1 ? "drink" : "drinks")")
                        .fontWeight(.semibold).foregroundStyle(Palette.gray200))
                    .font(.scaled(12))
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Palette.primary.opacity(0.5)).frame(width: 4, height: 4)
                    Circle().fill(Palette.primary).frame(width: 7, height: 7)
                    Text("bigger night").font(.scaled(11)).foregroundStyle(Palette.gray500)
                        .padding(.leading, 2)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let k = key(year, month, day)
        let isSelected = k == selected
        let isToday = k == DayKey.key()
        let isFuture = DayKey.isFuture(k)
        let total = dayTotals[k]

        ZStack {
            if isSelected {
                Circle().fill(Palette.primary).frame(width: 36, height: 36)
            } else if isToday {
                Circle().strokeBorder(Palette.gray600, lineWidth: 1).frame(width: 36, height: 36)
            }
            Text("\(day)")
                .font(.scaled(14))
                .foregroundStyle(isSelected ? .white : (isFuture ? Palette.gray500 : Palette.gray200))
            if let total, !isSelected {
                // Dot scales with the night's size: 1 drink small/faint,
                // a few drinks medium, big nights full-size and solid.
                let (size, opacity): (CGFloat, Double) =
                    total >= 4 ? (7, 1) : total >= 2 ? (5, 0.75) : (4, 0.5)
                Circle().fill(Palette.primary.opacity(opacity))
                    .frame(width: size, height: size)
                    .offset(y: 14)
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if !isFuture { selected = k } }
    }

    private func step(_ delta: Int) {
        var m = month + delta
        var y = year
        if m < 0 { m = 11; y -= 1 }
        if m > 11 { m = 0; y += 1 }
        month = m; year = y
    }

    private func syncToSelected() {
        let parts = selected.split(separator: "-").compactMap { Int($0) }
        if parts.count == 3 {
            year = parts[0]; month = parts[1]
        }
    }
}
