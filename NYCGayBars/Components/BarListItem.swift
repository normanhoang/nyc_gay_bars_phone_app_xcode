import SwiftUI

/// A bar row in the Explore / picker lists. Unvisited rows are full glass and
/// stay the visual target; visited rows recede (flat 4% fill, dimmed content,
/// green check). Shows a drink-count badge.
struct BarListItem: View {
    let bar: Bar
    var distance: Double?
    var visited: Bool
    var drinkCount: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bar.name)
                        .font(.scaled(16, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Text(bar.neighborhood)
                            .font(.scaled(12, weight: .medium))
                            .foregroundStyle(Palette.primary)
                        if let distance {
                            Text("· \(String(format: "%.1f", distance)) mi")
                                .font(.scaled(12, weight: .medium))
                                .foregroundStyle(Palette.gray400)
                        }
                    }
                    Text(bar.address)
                        .font(.scaled(12))
                        .foregroundStyle(Palette.gray400)
                        .lineLimit(1)
                    if let tags = bar.tags, !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.scaled(10, weight: .medium))
                                    .foregroundStyle(Palette.gray400)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
                .opacity(visited ? 0.55 : 1)

                if drinkCount > 0 {
                    HStack(spacing: 2) {
                        Text("🍹").font(.scaled(13))
                        Text("\(drinkCount)")
                            .font(.scaled(14, weight: .bold))
                            .foregroundStyle(visited ? Palette.gray200 : Palette.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(visited ? Color.white.opacity(0.08) : Palette.primary.opacity(0.25)))
                    .padding(.trailing, 8)
                }

                if visited {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.scaled(20))
                        .foregroundStyle(Palette.green)
                        .padding(.trailing, 8)
                }

                Image(systemName: "chevron.right")
                    .font(.scaled(16, weight: .semibold))
                    .foregroundStyle(Palette.gray400)
            }
            .padding(16)
            .modifier(RowSurface(visited: visited))
        }
        .buttonStyle(PressableScale())
    }
}

/// Full glass for unvisited rows; a flat, quieter panel for visited ones.
private struct RowSurface: ViewModifier {
    let visited: Bool
    func body(content: Content) -> some View {
        if visited {
            content.contentPanel(radius: 24, fill: Color.white.opacity(0.04))
        } else {
            content.glassSurface(radius: 24, bordered: true)
        }
    }
}
