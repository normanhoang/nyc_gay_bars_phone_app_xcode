import SwiftUI

/// Glass pill toggle with a sliding primary chip. Port of RN
/// components/SegmentedToggle.tsx. Segments are equal width.
struct SegmentedToggle: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        GeometryReader { geo in
            let seg = geo.size.width / CGFloat(max(options.count, 1))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Palette.primary)
                    .frame(width: seg)
                    .offset(x: seg * CGFloat(selection))
                    .animation(Anim.chip, value: selection)

                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, label in
                        Text(label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selection == i ? .white : Palette.gray200)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = i }
                    }
                }
            }
        }
        .frame(height: 34)
        .padding(4)
        .glassSurface(radius: 999, bordered: true)
    }
}
