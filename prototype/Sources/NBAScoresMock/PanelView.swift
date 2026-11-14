import SwiftUI

enum Tab: String, CaseIterable {
    case scores = "Scores"
    case standings = "Standings"
}

enum Table: String, CaseIterable {
    case season = "Season"
    case cup = "NBA Cup"
    case playoffs = "Playoffs"
}

enum Route: Hashable {
    case box(Game.ID)
    case player
}

@MainActor @Observable
final class Nav {
    var tab = Tab.scores
    var table = Table.season
    var stack: [Route] = []
    var day = Mock.today

    var width: CGFloat {
        if !stack.isEmpty { return Layout.detail }
        return tab == .scores ? Layout.compact : Layout.wide
    }

    /// Changes whenever another screen is shown.
    var screen: AnyHashable {
        if let route = stack.last { return AnyHashable(route) }
        return tab == .scores ? AnyHashable(day) : AnyHashable(table)
    }

    func open(_ route: Route) { stack.append(route) }
    func back() { if !stack.isEmpty { stack.removeLast() } }

    func step(_ delta: Int) {
        guard stack.isEmpty, tab == .scores else { return }
        day = min(max(day + delta, 0), Mock.days.count - 1)
    }
}

struct PanelView: View {
    @State var nav: Nav
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Header(nav: nav)
            Divider()
            Fitted(maxHeight: Layout.maxContentHeight, screen: nav.screen) {
                content
                    .padding(.horizontal, Layout.inset)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: nav.width)
        .background(WindowClamp())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) { nav.back(); return .handled }
        .onKeyPress(.leftArrow) { nav.step(-1); return .handled }
        .onKeyPress(.rightArrow) { nav.step(1); return .handled }
        .onKeyPress(characters: .letters) { press in
            switch press.characters {
            case "s": nav.stack = []; nav.tab = .standings
            case "b": nav.stack = []; nav.tab = .scores
            case "t": nav.stack = []; nav.tab = .scores; nav.day = Mock.today
            case "o": nav.stack = []; nav.tab = .standings; nav.table = .playoffs
            default: return .ignored
            }
            return .handled
        }
    }

    @ViewBuilder private var content: some View {
        switch nav.stack.last {
        case .box: BoxScoreView(nav: nav)
        case .player: PlayerView()
        case nil:
            switch (nav.tab, nav.table) {
            case (.scores, _): ScoresView(nav: nav)
            case (.standings, .season): StandingsView()
            case (.standings, .playoffs): PlayoffsView()
            case (.standings, .cup):
                Text("The NBA Cup view is not part of this mockup.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }
}

// MARK: Header

struct Header: View {
    @Bindable var nav: Nav

    var body: some View {
        Group {
            if let route = nav.stack.last { detail(route) } else { top }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var top: some View {
        HStack(spacing: 10) {
            Picker("View", selection: $nav.tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 0)
            if nav.tab == .scores {
                let day = Mock.days[nav.day]
                StepTitle(
                    title: day.title, subtitle: day.subtitle,
                    canPrev: nav.day > 0, canNext: nav.day < Mock.days.count - 1,
                    prev: { nav.step(-1) }, next: { nav.step(1) }
                )
            } else {
                StepTitle(
                    title: Mock.season, subtitle: nav.table == .playoffs ? "Playoffs · final" : "Regular season",
                    canPrev: true, canNext: false, prev: {}, next: {}
                )
            }
            Spacer(minLength: 0)

            if nav.tab == .standings {
                Picker("Table", selection: $nav.table) {
                    ForEach(Table.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            IconButton(symbol: "magnifyingglass") {}
        }
    }

    private func detail(_ route: Route) -> some View {
        ZStack {
            HStack {
                Button { nav.back() } label: {
                    Label(backTitle, systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                if case .box(let id) = route, Mock.game(id).isFinal { RecapButton() }
            }
            switch route {
            case .box(let id):
                let game = Mock.game(id)
                TitleBlock(title: boxTitle(game), subtitle: "\(statusText(game)) · \(Mock.venue)", live: game.isLive)
            case .player:
                TitleBlock(title: Mock.playerName, subtitle: Mock.playerSubtitle)
            }
        }
    }

    private var backTitle: String {
        switch nav.stack.dropLast().last {
        case .box: "Box score"
        case .player: "Player"
        case nil: nav.tab.rawValue
        }
    }

    private func boxTitle(_ game: Game) -> String {
        guard let away = game.away.score, let home = game.home.score else {
            return "\(game.away.team.abbr) at \(game.home.team.abbr)"
        }
        return "\(game.away.team.abbr)  \(away) – \(home)  \(game.home.team.abbr)"
    }

    private func statusText(_ game: Game) -> String {
        switch game.status {
        case .scheduled(let time): time
        case .live(let clock): clock
        case .final(let text): text
        }
    }
}

struct TitleBlock: View {
    let title: String
    let subtitle: String
    var live = false

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 14, weight: .semibold)).monospacedDigit()
            Text(subtitle).font(.system(size: 10.5)).foregroundStyle(live ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
    }
}

/// A title between two chevrons: the day in the scores, the season in the standings.
struct StepTitle: View {
    let title: String
    let subtitle: String
    let canPrev: Bool
    let canNext: Bool
    let prev: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "chevron.left", enabled: canPrev, action: prev)
            VStack(spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .frame(minWidth: 124)
            IconButton(symbol: "chevron.right", enabled: canNext, action: next)
        }
    }
}
