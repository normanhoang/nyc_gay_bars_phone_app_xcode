import SwiftUI

/// A bar row in the Explore / picker lists. Glass surface; gets a primary
/// border + wash when visited; shows a drink-count badge. Port of RN
/// components/BarListItem.tsx.
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Text(bar.neighborhood)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.primary)
                        if let distance {
                            Text("· \(String(format: "%.1f", distance)) mi")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.gray400)
                        }
                    }
                    Text(bar.address)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.gray400)
                        .lineLimit(1)
                    if let tags = bar.tags, !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10, weight: .medium))
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

                if drinkCount > 0 {
                    HStack(spacing: 2) {
                        Text("🍹").font(.system(size: 13))
                        Text("\(drinkCount)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.primary.opacity(0.25)))
                    .padding(.trailing, 4)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.gray400)
            }
            .padding(16)
            .background {
                if visited {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Palette.primary.opacity(0.20))
                }
            }
            .glassSurface(radius: 24, bordered: visited,
                          borderColor: visited ? Palette.primary.opacity(0.5) : Color.white.opacity(0.16))
        }
        .buttonStyle(PressableScale())
    }
}
