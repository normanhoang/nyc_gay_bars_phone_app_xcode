import Foundation

enum BarLinkKind { case instagram, website, facebook, tiktok }

/// One outbound link for a bar. `appURL`, when set, is tried first (native
/// app); `url` is the web fallback.
struct BarLink: Identifiable {
    let kind: BarLinkKind
    let url: URL
    let appURL: URL?
    var id: BarLinkKind { kind }
}

enum BarLinks {
    /// Links in display order — Instagram, Website, Facebook, TikTok — skipping
    /// missing or unparseable fields.
    static func links(for bar: Bar) -> [BarLink] {
        var out: [BarLink] = []
        if let h = nonEmpty(bar.instagram), let url = URL(string: "https://www.instagram.com/\(h)") {
            out.append(BarLink(kind: .instagram, url: url,
                               appURL: URL(string: "instagram://user?username=\(h)")))
        }
        if let s = nonEmpty(bar.website), let url = URL(string: s) {
            out.append(BarLink(kind: .website, url: url, appURL: nil))
        }
        if let s = nonEmpty(bar.facebook), let url = URL(string: s) {
            out.append(BarLink(kind: .facebook, url: url, appURL: nil))
        }
        if let h = nonEmpty(bar.tiktok), let url = URL(string: "https://www.tiktok.com/@\(h)") {
            out.append(BarLink(kind: .tiktok, url: url, appURL: nil))
        }
        return out
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
