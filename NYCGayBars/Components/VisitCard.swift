import SwiftUI

/// A logged visit on the History screen: bar, drinks, optional note; delete
/// lives in a quiet ⋯ menu (redesign 5a).
struct VisitCard: View {
    let visit: Visit
    var onDelete: () -> Void
    /// Tapping the card opens the bar for this visit's day.
    var onTap: (() -> Void)? = nil

    private var bar: Bar? { AppData.bar(id: visit.barId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bar?.name ?? visit.barId)
                        .font(.scaled(16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(bar?.neighborhood ?? "")
                        .font(.scaled(12, weight: .medium))
                        .foregroundStyle(Palette.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(visit.drinkTotal)")
                        .font(.scaled(18, weight: .heavy))
                        .foregroundStyle(Palette.primary)
                    Text("DRINKS")
                        .font(.scaled(10, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(Palette.gray400)
                }

                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete visit", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.scaled(13, weight: .semibold))
                        .foregroundStyle(Palette.gray400)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .padding(.top, -6)
                .padding(.trailing, -8)
            }

            if visit.drinks.isEmpty {
                Text("Checked in · no drinks")
                    .font(.scaled(14))
                    .foregroundStyle(Palette.gray400)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .padding(.top, 12)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(visit.drinks, id: \.type) { d in
                        HStack(spacing: 2) {
                            Text(drinkEmoji(d.type)).font(.scaled(14))
                            Text(d.type).font(.scaled(14)).foregroundStyle(.white)
                            Text("×\(d.count)")
                                .font(.scaled(14, weight: .bold))
                                .foregroundStyle(Palette.primary)
                                .padding(.leading, 4)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    }
                }
                .padding(.top, 12)
            }

            if let note = visit.note, !note.isEmpty {
                Text("“\(note)”")
                    .font(.scaled(14))
                    .italic()
                    .foregroundStyle(Palette.gray400)
                    .padding(.top, 12)
            }
        }
        .padding(16)
        .contentPanel()
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { onTap?() }
    }
}
