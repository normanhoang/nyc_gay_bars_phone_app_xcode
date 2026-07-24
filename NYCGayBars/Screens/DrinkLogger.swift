import SwiftUI

/// Per-drink +/- rows plus a custom-drink input. The first three presets are
/// always shown; the rest (and the custom input) collapse behind "More drinks"
/// — any row with a count stays visible (redesign 6a).
struct DrinkLogger: View {
    let visit: Visit?
    var onLog: (String) -> Void
    var onRemove: (String) -> Void

    @State private var custom = ""
    @State private var expanded = false

    private var customTypes: [String] {
        (visit?.drinks ?? []).map(\.type).filter { t in
            !PRESET_DRINKS.contains { $0.lowercased() == t.lowercased() }
        }
    }

    private func count(_ type: String) -> Int {
        visit?.drinks.first { $0.type.lowercased() == type.lowercased() }?.count ?? 0
    }

    var body: some View {
        let top = Array(PRESET_DRINKS.prefix(3))
        let rest = Array(PRESET_DRINKS.dropFirst(3))
        VStack(spacing: 0) {
            ForEach(top, id: \.self) { row($0) }
            if expanded {
                ForEach(rest, id: \.self) { row($0) }
                ForEach(customTypes, id: \.self) { row($0) }
            } else {
                // Collapsed, but never hide a row the user has drinks on.
                ForEach(rest.filter { count($0) > 0 }, id: \.self) { row($0) }
                ForEach(customTypes, id: \.self) { row($0) }
            }

            Button {
                withAnimation(Anim.chip) { expanded.toggle() }
                Haptics.light()
            } label: {
                HStack(spacing: 4) {
                    Text(expanded ? "Fewer drinks" : "More drinks")
                        .font(.scaled(13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.scaled(11, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(Palette.gray300)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            if expanded {
                HStack(spacing: 8) {
                    TextField("", text: $custom,
                              prompt: Text("Add a custom drink…").foregroundStyle(Palette.gray400))
                        .foregroundStyle(.white)
                        .font(.scaled(16))
                        .submitLabel(.done)
                        .onSubmit(addCustom)
                        .padding(.vertical, 8)
                    Button(action: addCustom) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.scaled(16))
                            Text("Add").font(.scaled(14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Palette.primary))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassSurface(radius: 16)
            }
        }
    }

    @ViewBuilder
    private func row(_ type: String) -> some View {
        let c = count(type)
        HStack(spacing: 0) {
            Text(drinkEmoji(type)).font(.scaled(24)).padding(.trailing, 12)
            Text(type).font(.scaled(16, weight: .medium)).foregroundStyle(.white)
            Spacer()
            HStack(spacing: 0) {
                Button { Haptics.light(); onRemove(type) } label: {
                    Image(systemName: "minus").font(.scaled(20)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(c == 0 ? 0.06 : 0.12)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                        .opacity(c == 0 ? 0.4 : 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(c == 0)
                .accessibilityLabel("Remove \(type)")

                Text("\(c)")
                    .font(.scaled(16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32)

                Button { Haptics.light(); onLog(type) } label: {
                    Image(systemName: "plus").font(.scaled(20)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Palette.primary))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(type)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassSurface(radius: 16, bordered: c > 0,
                      borderColor: c > 0 ? Palette.primary.opacity(0.4) : Color.white.opacity(0.16))
        .padding(.bottom, 12)
    }

    private func addCustom() {
        let name = custom.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Haptics.light()
        onLog(name)
        custom = ""
    }
}
