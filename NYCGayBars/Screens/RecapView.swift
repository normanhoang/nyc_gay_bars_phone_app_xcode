import SwiftUI

/// Full-screen year recap (redesign 2a): hero drink count, 2×2 stat grid,
/// scene coverage, badges earned, and a story-format share card exported via
/// ImageRenderer + ShareLink. All numbers come from Logic/Stats scoped to one
/// calendar year.
struct RecapView: View {
    let year: Int
    var onClose: () -> Void

    @EnvironmentObject private var visits: VisitsStore
    @EnvironmentObject private var badges: BadgesStore

    @State private var shareImage: UIImage?

    private struct Model {
        let drinks: Int
        let nights: Int
        let bars: Int
        let totalBars: Int
        let boroughs: Int
        let topBar: Bar?
        let topBarNights: Int
        let topDrink: (type: String, count: Int)?
        let busiestMonth: (month: Int, nights: Int)?
        let homeTurf: (neighborhood: String, nights: Int)?
        let badgesEarned: [Badge]
    }

    private func makeModel() -> Model {
        let vs = Stats.visitsIn(year: year, visits.visits)
        let topBar = Stats.favoriteBar(vs)
        let earned = badges.badges
            .filter { $0.earnedAt?.hasPrefix("\(year)-") == true }
            .sorted { ($0.earnedAt ?? "") < ($1.earnedAt ?? "") }
        return Model(
            drinks: Stats.totalDrinks(vs),
            nights: Stats.totalDrinkDays(vs),
            bars: Stats.distinctBarsVisited(vs),
            totalBars: AppData.bars.count,
            boroughs: Stats.boroughCount(vs),
            topBar: topBar,
            topBarNights: topBar.map { Stats.nightsAt($0.id, vs) } ?? 0,
            topDrink: Stats.topDrinkType(vs),
            busiestMonth: Stats.busiestMonth(vs),
            homeTurf: Stats.homeTurf(vs),
            badgesEarned: earned)
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let m = makeModel()
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("YOUR \(String(year)) RECAP")
                                .font(.scaled(12, weight: .bold)).tracking(1.7)
                                .foregroundStyle(Palette.primary)
                            Text("What a year, honey.")
                                .font(.scaled(26, weight: .heavy)).foregroundStyle(.white)
                        }
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.scaled(20)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).glassSurface(radius: 18)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    .padding(.bottom, 16)

                    hero(m).padding(.bottom, 12)

                    LazyVGrid(columns: columns, spacing: 12) {
                        if let bar = m.topBar {
                            recapCard("TOP BAR", bar.name, "\(m.topBarNights) nights · your regular")
                        }
                        if let top = m.topDrink {
                            recapCard("TOP DRINK", "\(drinkEmoji(top.type)) \(top.type)", "\(top.count) logged")
                        }
                        if let busy = m.busiestMonth {
                            recapCard("BUSIEST MONTH", DateFormatter().monthSymbols[busy.month],
                                      "\(busy.nights) nights out")
                        }
                        if let home = m.homeTurf {
                            recapCard("HOME TURF", home.neighborhood, "\(home.nights) of \(m.nights) nights")
                        }
                    }
                    .padding(.bottom, 12)

                    coverage(m).padding(.bottom, 12)

                    if !m.badgesEarned.isEmpty {
                        badgesStrip(m).padding(.bottom, 20)
                    }

                    sharePill(m)
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .onAppear { shareImage = renderShareCard(m) }
    }

    private func hero(_ m: Model) -> some View {
        VStack(spacing: 6) {
            CountUp(value: m.drinks, font: .scaled(56, weight: .heavy), color: .white)
            (Text("drinks across ").foregroundStyle(Palette.gray300)
                + Text("\(m.nights) nights out").fontWeight(.semibold).foregroundStyle(Palette.primary))
                .font(.scaled(14))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Palette.primary.opacity(0.3), Palette.violetGlow.opacity(0.2)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Palette.primary.opacity(0.35), lineWidth: 1))
    }

    private func recapCard(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.scaled(11)).tracking(0.5).foregroundStyle(Palette.gray400)
            Text(value).font(.scaled(17, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8).padding(.top, 4)
            Text(detail).font(.scaled(11)).foregroundStyle(Palette.gray600)
                .lineLimit(1).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .contentPanel(radius: 16)
    }

    private func coverageCaption(_ m: Model) -> String {
        let remaining = m.totalBars - m.bars
        guard remaining > 0 else { return "You conquered the scene! 👑" }
        let pct = Double(m.bars) / Double(max(m.totalBars, 1))
        let phase = pct <= 0.25 ? "Just getting started"
            : pct <= 0.5 ? "Making the rounds"
            : pct <= 0.75 ? "A regular on the scene"
            : "Almost a legend"
        return "\(phase) — \(remaining) to go 🔥"
    }

    private func coverage(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SCENE COVERAGE").font(.scaled(11)).tracking(0.5).foregroundStyle(Palette.gray400)
                Spacer()
                Text("\(m.bars) / \(m.totalBars) bars")
                    .font(.scaled(12, weight: .semibold)).foregroundStyle(Palette.gray300)
            }
            ProgressBar(progress: Double(m.bars) / Double(max(m.totalBars, 1)), height: 6)
            Text(coverageCaption(m)).font(.scaled(11)).foregroundStyle(Palette.gray400)
        }
        .padding(14)
        .contentPanel(radius: 16)
    }

    private func badgesStrip(_ m: Model) -> some View {
        HStack(spacing: 8) {
            Text(m.badgesEarned.first?.emoji ?? "🏅").font(.scaled(18))
            Text("\(m.badgesEarned.count) badge\(m.badgesEarned.count == 1 ? "" : "s") earned")
                .font(.scaled(14, weight: .bold)).foregroundStyle(.white)
            if let first = m.badgesEarned.first {
                Text("· \(first.title) was your first")
                    .font(.scaled(12)).foregroundStyle(Palette.gray400)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .contentPanel(radius: 16)
    }

    /// The one solid-primary button in the app.
    @ViewBuilder
    private func sharePill(_ m: Model) -> some View {
        if let ui = shareImage {
            ShareLink(
                item: Image(uiImage: ui),
                preview: SharePreview("Your \(String(year)) recap", image: Image(uiImage: ui))) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up").font(.scaled(16, weight: .semibold))
                    Text("Share your recap").font(.scaled(16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Palette.primary))
                .shadow(color: Palette.primary.opacity(0.45), radius: 10, y: 2)
            }
            .buttonStyle(PressableScale())
        }
    }

    @MainActor
    private func renderShareCard(_ m: Model) -> UIImage? {
        let renderer = ImageRenderer(content: RecapShareCard(year: year, model: (
            drinks: m.drinks, nights: m.nights, bars: m.bars, totalBars: m.totalBars,
            boroughs: m.boroughs, topBar: m.topBar?.name, topDrink: m.topDrink,
            homeTurf: m.homeTurf?.neighborhood, badges: m.badgesEarned.count)))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Story-format export card — rendered offscreen, never shown in the UI.
private struct RecapShareCard: View {
    let year: Int
    let model: (drinks: Int, nights: Int, bars: Int, totalBars: Int, boroughs: Int,
                topBar: String?, topDrink: (type: String, count: Int)?,
                homeTurf: String?, badges: Int)

    var body: some View {
        VStack(spacing: 0) {
            Image("AppLogo")
                .resizable().scaledToFit().frame(width: 72, height: 72)
            Text("NYC GAY BARS · \(String(year))")
                .font(.system(size: 13, weight: .bold)).tracking(2)
                .foregroundStyle(Palette.primary)
                .padding(.top, 10)
            Text("\(model.drinks) drinks")
                .font(.system(size: 44, weight: .heavy)).foregroundStyle(.white)
                .padding(.top, 8)
            Text("\(model.nights) nights · \(model.bars) bars · \(model.boroughs) borough\(model.boroughs == 1 ? "" : "s")")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.gray300)
                .padding(.top, 4)

            VStack(spacing: 12) {
                if let bar = model.topBar { statRow("Top bar", bar) }
                if let top = model.topDrink { statRow("Top drink", "\(drinkEmoji(top.type)) \(top.type) ×\(top.count)") }
                if let home = model.homeTurf { statRow("Home turf", home) }
                statRow("Badges", "\(model.badges) earned")
            }
            .padding(.top, 24)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 6)
                Capsule().fill(LinearGradient(colors: [Palette.primary, Palette.violet],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: 260 * CGFloat(model.bars) / CGFloat(max(model.totalBars, 1)), height: 6)
            }
            .frame(width: 260)
            .padding(.top, 24)

            HStack {
                Text("\(model.bars) of \(model.totalBars) bars conquered")
                Spacer()
                Text("@thenycgaybars")
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.gray500)
            .frame(width: 260)
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 30)
        .frame(width: 340)
        .background(Palette.inkDeep)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Palette.primary, Palette.violet],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
        .padding(12)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Palette.gray400)
            Spacer()
            Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(width: 270)
    }
}
