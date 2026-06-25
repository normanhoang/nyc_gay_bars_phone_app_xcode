import SwiftUI
import UIKit

extension View {
    /// Resign the first responder (hide the keyboard) when an empty area of the
    /// view — anything that isn't an interactive control — is tapped. Place a
    /// transparent tappable layer behind the content so it only catches taps
    /// that fall through, never stealing taps from buttons or the search field.
    func dismissKeyboardOnBackgroundTap() -> some View {
        background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        )
    }
}
