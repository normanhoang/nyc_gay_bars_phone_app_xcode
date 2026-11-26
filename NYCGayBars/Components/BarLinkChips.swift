import SwiftUI
import UIKit

/// Equal-width Instagram / Website (Facebook / TikTok fallback) chips under
/// `BarActionPills`, so the user can check what's on tonight. Renders nothing
/// when the bar has no links.
struct BarLinkChips: View {
    let bar: Bar

    var body: some View {
        let links = BarLinks.links(for: bar)
        if !links.isEmpty {
            HStack(spacing: 8) {
                ForEach(links) { link in
                    Button { open(link) } label: { chip(link.kind) }
                        .buttonStyle(PressableScale())
                        .accessibilityLabel(link.kind == .website
                            ? "Open \(bar.name) website"
                            : "Open \(bar.name) on \(label(link.kind))")
                }
            }
        }
    }

    /// Same look as `BarActionPills`' untinted chip.
    private func chip(_ kind: BarLinkKind) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(kind)).font(.scaled(13, weight: .semibold))
            Text(label(kind)).font(.scaled(14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .glassSurface(radius: 999, bordered: true)
    }

    private func label(_ kind: BarLinkKind) -> String {
        switch kind {
        case .instagram: "Instagram"
        case .website: "Website"
        case .facebook: "Facebook"
        case .tiktok: "TikTok"
        }
    }

    private func icon(_ kind: BarLinkKind) -> String {
        switch kind {
        case .instagram: "camera"
        case .website: "globe"
        case .facebook: "person.2.wave.2"
        case .tiktok: "music.note"
        }
    }

    private func open(_ link: BarLink) {
        Haptics.light()
        guard let app = link.appURL else { UIApplication.shared.open(link.url); return }
        UIApplication.shared.open(app, options: [:]) { ok in
            if !ok { UIApplication.shared.open(link.url) }
        }
    }
}
