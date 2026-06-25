import SwiftUI

/// Month grid for the History screen. Selected day is a primary circle, today
/// gets a ring, days with visits get a dot, future days are dimmed. Port of RN
/// components/MonthCalendar.tsx.
struct MonthCalendar: View {
    @Binding var selected: String          // dayKey "y-m-d" (month 0-indexed)
    let markedDays: Set<String>            // dayKeys with visits

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
                }
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { step(1) } label: {
                    Image(systemName: "chevron.right").foregroundStyle(.white)
                }
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.system(size: 12, weight: .semibold))
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
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.white.opacity(0.05)))
        .onAppear(perform: syncToSelected)
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let k = key(year, month, day)
        let isSelected = k == selected
        let isToday = k == DayKey.key()
        let isFuture = DayKey.isFuture(k)
        let isMarked = markedDays.contains(k)

        ZStack {
            if isSelected {
                Circle().fill(Palette.primary).frame(width: 36, height: 36)
            } else if isToday {
                Circle().strokeBorder(Palette.gray600, lineWidth: 1).frame(width: 36, height: 36)
            }
            Text("\(day)")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .white : (isFuture ? Palette.gray700 : Palette.gray200))
            if isMarked && !isSelected {
                Circle().fill(Palette.primary).frame(width: 4, height: 4)
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
