import SwiftUI

/// Per-drink +/- rows plus a custom-drink input. Port of RN
/// components/DrinkLogger.tsx.
struct DrinkLogger: View {
    let visit: Visit?
    var onLog: (String) -> Void
    var onRemove: (String) -> Void

    @State private var custom = ""

    private var customTypes: [String] {
        (visit?.drinks ?? []).map(\.type).filter { t in
            !PRESET_DRINKS.contains { $0.lowercased() == t.lowercased() }
        }
    }

    private func count(_ type: String) -> Int {
        visit?.drinks.first { $0.type.lowercased() == type.lowercased() }?.count ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(PRESET_DRINKS, id: \.self) { row($0) }
            ForEach(customTypes, id: \.self) { row($0) }

            HStack(spacing: 8) {
                TextField("", text: $custom,
                          prompt: Text("Add a custom drink…").foregroundStyle(Palette.gray600))
                    .foregroundStyle(.white)
                    .font(.system(size: 16))
                    .submitLabel(.done)
                    .onSubmit(addCustom)
                    .padding(.vertical, 8)
                Button(action: addCustom) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 16))
                        Text("Add").font(.system(size: 14, weight: .semibold))
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

    @ViewBuilder
    private func row(_ type: String) -> some View {
        let c = count(type)
        HStack(spacing: 0) {
            Text(drinkEmoji(type)).font(.system(size: 24)).padding(.trailing, 12)
            Text(type).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
            Spacer()
            HStack(spacing: 0) {
                Button { Haptics.light(); onRemove(type) } label: {
                    Image(systemName: "minus").font(.system(size: 20)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(c == 0 ? 0.06 : 0.12)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                        .opacity(c == 0 ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(c == 0)

                Text("\(c)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32)

                Button { Haptics.light(); onLog(type) } label: {
                    Image(systemName: "plus").font(.system(size: 20)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Palette.primary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassSurface(radius: 16)
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
