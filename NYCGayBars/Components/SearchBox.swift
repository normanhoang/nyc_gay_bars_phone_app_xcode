import SwiftUI

/// Glass search field with leading icon, a clear button, and an optional
/// trailing accessory (Explore's sort chip). Port of RN components/SearchBox.tsx.
/// Text edits route through `onChangeText` so the caller can intercept ZIP codes.
struct SearchBox<Trailing: View>: View {
    let text: String
    var placeholder: String = "Search bars, neighborhoods, ZIP…"
    var onChangeText: (String) -> Void
    var onFocus: () -> Void = {}
    @ViewBuilder var trailing: () -> Trailing

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.scaled(16))
                .foregroundStyle(Palette.gray400)
            TextField("", text: Binding(get: { text }, set: onChangeText),
                      prompt: Text(placeholder).foregroundStyle(Palette.gray400))
                .foregroundStyle(.white)
                .font(.scaled(16))
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            if !text.isEmpty {
                Button { onChangeText("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaled(18))
                        .foregroundStyle(Palette.gray400)
                }
                .buttonStyle(.plain)
            }
            trailing()
        }
        .padding(.horizontal, 12)
        .glassSurface(radius: 16, bordered: true)
        .onChange(of: focused) { _, f in if f { onFocus() } }
    }
}

extension SearchBox where Trailing == EmptyView {
    init(text: String, placeholder: String = "Search bars, neighborhoods, ZIP…",
         onChangeText: @escaping (String) -> Void, onFocus: @escaping () -> Void = {}) {
        self.init(text: text, placeholder: placeholder, onChangeText: onChangeText,
                  onFocus: onFocus, trailing: { EmptyView() })
    }
}
