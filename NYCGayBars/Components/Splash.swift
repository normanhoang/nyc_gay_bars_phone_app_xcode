import SwiftUI

/// Branded launch overlay: the transparent logo centered on the app gradient,
/// shown briefly on startup. Mirrors RN components/Splash.tsx.
struct Splash: View {
    var body: some View {
        ZStack {
            AppBackground()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 300)
                .accessibilityLabel("NYC Gay Bars logo")
        }
        .ignoresSafeArea()
    }
}
