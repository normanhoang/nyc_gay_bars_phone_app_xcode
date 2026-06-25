import SwiftUI

@main
struct NYCGayBarsApp: App {
    @StateObject private var visits = VisitsStore()
    @StateObject private var badges = BadgesStore()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppBackground()
                RootTabView()
                    .environmentObject(visits)
                    .environmentObject(badges)
                if showSplash {
                    Splash().transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
            }
        }
    }
}
