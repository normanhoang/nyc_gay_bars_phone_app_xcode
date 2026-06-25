import SwiftUI

/// Horizontal neighborhood filter chips with a pinned first option ("All").
/// Cheap translucent pills (no per-item glass). Port of RN FilterChips.tsx.
struct FilterChips: View {
    /// Full ordered list; the first entry is pinned and stays at the far left.
    let options: [String]
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 8) {
            if let pinned = options.first {
                chip(pinned)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(options.dropFirst(), id: \.self) { opt in
                            chip(opt).id(opt)
                        }
                    }
                    .padding(.trailing, 16)
                }
                .onChange(of: selected) { _, newVal in
                    let target = newVal == options.first ? options.dropFirst().first : newVal
                    if let t = target {
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(t, anchor: .leading) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ label: String) -> some View {
        let active = selected == label
        Button { selected = label } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? .white : Palette.gray300)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(active ? Palette.primary : Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule().strokeBorder(
                        active ? Palette.primary.opacity(0.6) : Color.white.opacity(0.10),
                        lineWidth: 1)
                )
        }
        .buttonStyle(PressableScale())
    }
}
