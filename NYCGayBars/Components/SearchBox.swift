import SwiftUI

/// Glass search field with leading icon and a clear button. Port of RN
/// components/SearchBox.tsx. Text edits route through `onChangeText` so the
/// caller can intercept ZIP codes.
struct SearchBox: View {
    let text: String
    var placeholder: String = "Search bars, neighborhoods, ZIP…"
    var onChangeText: (String) -> Void
    var onFocus: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Palette.gray400)
            TextField("", text: Binding(get: { text }, set: onChangeText),
                      prompt: Text(placeholder).foregroundStyle(Palette.gray600))
                .foregroundStyle(.white)
                .font(.system(size: 16))
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            if !text.isEmpty {
                Button { onChangeText("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.gray400)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .glassSurface(radius: 16, bordered: true)
        .onChange(of: focused) { _, f in if f { onFocus() } }
    }
}
