import SwiftUI

/// Transient "10001 → Chelsea" confirmation shown under a search box after a
/// ZIP code is recognized. Port of RN components/ZipNote.tsx.
struct ZipNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.primary)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.primary)
        }
        .padding(.horizontal, 4)
    }
}
