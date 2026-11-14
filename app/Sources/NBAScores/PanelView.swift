import NBAKit
import SwiftUI

struct PanelView: View {
    let model: AppModel
    @FocusState private var focused: Bool

    private var width: CGFloat {
        switch model.stack.last {
        case .bracket: Layout.wide
        case .some: Layout.detail
        case nil: model.tab == .scores ? Layout.compact : Layout.wide
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model)
            Divider()
            Fitted(maxHeight: Layout.maxContentHeight, screen: model.screen) {
                content
                    .padding(.horizontal, Layout.inset)
                    .padding(.vertical, 8)
            }
            if let error = model.error, hasContent {
                Divider()
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .frame(width: width)
        .background(PanelWindow(opened: model.panelOpened, closed: model.panelClosed))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        // The search field takes the keyboard while it is open; give it back afterwards.
        .onChange(of: model.searchOpen) { _, open in if !open { focused = true } }
        .onKeyPress(phases: .down) { press in handle(press) ? .handled : .ignored }
    }

    @ViewBuilder private var content: some View {
        switch model.stack.last {
        case .box(let id): BoxScoreView(model: model, id: id)
        case .player(let id): PlayerView(model: model, id: id)
        case .team: TeamView(model: model)
        case .search: SearchView(model: model)
        case .series(let series): SeriesView(model: model, series: series)
        case .bracket(let key): StandingsView(model: model, key: key)
        case .award(let key): AwardView(model: model, key: key)
        case nil:
            switch model.tab {
            case .scores: ScoresView(model: model)
            case .standings: StandingsView(model: model, key: model.tableKey)
            }
        }
    }

    /// Whether the screen shows data: an error is then a footnote, not the whole view.
    private var hasContent: Bool {
        switch model.stack.last {
        case .box(let id): model.boxes[id] != nil
        case .player, .team, .search, .series, .bracket, .award: false
        case nil: model.tab == .scores ? model.viewLoaded : false
        }
    }

    private func handle(_ press: KeyPress) -> Bool {
        if press.modifiers.contains(.command), press.characters == "f" {
            model.openSearch()
            return true
        }
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return false }
        let top = model.stack.last
        switch press.key {
        case .escape:
            if model.stack.isEmpty { StatusItem.closePanel() } else { model.back() }
        case .leftArrow, .rightArrow:
            let delta = press.key == .leftArrow ? -1 : 1
            switch top {
            case .box: model.stepBox(delta)
            case .team: model.stepTeamSeason(delta)
            case .award: model.stepAwardSeason(delta)
            case .player, .search, .series, .bracket: return false
            case nil: model.tab == .scores ? model.stepDay(delta) : model.stepSeason(delta)
            }
        case .upArrow, .downArrow:
            let delta = press.key == .upArrow ? -1 : 1
            if top == .search { model.moveSearch(delta) }
            else if top == nil, model.tab == .scores { model.moveSelection(delta) }
            else { return false }
        case .return:
            if top == .search { model.openSelectedResult() }
            else if top == nil, model.tab == .scores { model.openSelected() }
            else { return false }
        default:
            // Letters belong to the search field while it is open.
            guard top != .search else { return false }
            switch press.characters {
            case "/": model.openSearch()
            case "r": model.refreshNow()
            case "t": model.show(Tab.scores); model.goCurrent()
            case "b": model.show(Tab.scores)
            case "s": model.show(model.tab == .standings && model.stack.isEmpty ? Tab.scores : Tab.standings)
            case "p": model.cycleTable()
            case "c": model.show(Table.cup)
            case "o": model.show(Table.playoffs)
            case "y":
                guard let url = model.recapTarget else { return false }
                model.openRecap(url)
            default: return false
            }
        }
        return true
    }
}

// MARK: Header

struct Header: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.stack.last {
            case .box(let id): box(id)
            case .player(let id): player(id)
            case .team: team
            case .search: search
            case .series(let series): self.series(series)
            case .bracket(let key): detail { TitleBlock(title: Season.label(key.season), subtitle: tableSubtitle(key)) }
            case .award(let key):
                detail {
                    StepTitle(
                        title: key.kind.title, subtitle: Season.label(key.season),
                        canPrev: key.season > key.kind.firstSeason, canNext: key.season < Awards.lastSeason(),
                        prev: { model.stepAwardSeason(-1) }, next: { model.stepAwardSeason(1) }
                    )
                }
            case nil: top
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var top: some View {
        HStack(spacing: 10) {
            Picker("View", selection: Binding(get: { model.tab }, set: { (tab: Tab) in model.show(tab) })) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 0)
            if model.tab == .scores {
                let index = model.dayIndex
                StepTitle(
                    title: model.viewDay.isEmpty ? "NBA" : GameDay.label(model.viewDay),
                    subtitle: daySubtitle,
                    canPrev: (index ?? 0) > 0, canNext: (index ?? model.days.count) < model.days.count - 1,
                    prev: { model.stepDay(-1) }, next: { model.stepDay(1) }
                )
            } else {
                StepTitle(
                    title: Season.label(model.standingsSeason), subtitle: tableSubtitle(model.tableKey),
                    canPrev: model.standingsSeason > model.table.firstSeason,
                    canNext: model.standingsSeason < max(model.seasonYear, model.latestSeason),
                    prev: { model.stepSeason(-1) }, next: { model.stepSeason(1) }
                )
            }
            Spacer(minLength: 0)
            if model.tab == .standings {
                Picker("Table", selection: Binding(get: { model.table }, set: { model.show($0) })) {
                    ForEach(Table.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 2) {
                IconButton(symbol: "magnifyingglass") { model.openSearch() }.help("Search teams and players (/)")
                RefreshButton(model: model)
            }
        }
    }

    private var daySubtitle: String {
        let games = model.viewGames
        if model.viewingCurrent, !games.isEmpty {
            return "Today · \(games.count == 1 ? "1 game" : "\(games.count) games")"
        }
        return games.isEmpty ? (model.viewingCurrent ? "Today" : " ") : games.subtitle
    }

    /// "Regular season", "NBA Cup", "Playoffs · final"
    private func tableSubtitle(_ key: TableKey) -> String {
        switch key.table {
        case .season: "Regular season"
        case .cup: model.cups[key.season].map { $0.done ? "NBA Cup · final" : "NBA Cup" } ?? "NBA Cup"
        case .playoffs: model.brackets[key.season].map { "Playoffs · \($0.phase.rawValue)" } ?? "Playoffs"
        }
    }

    private func series(_ series: SeriesCard) -> some View {
        detail {
            TitleBlock(title: "\(series.top.abbr)  \(series.top.wins) – \(series.bottom.wins)  \(series.bottom.abbr)",
                       subtitle: series.label, live: series.state == .live)
        }
    }

    /// The name of the screen under this one, on the back button.
    private var backTitle: String {
        model.stack.dropLast().last?.title ?? model.tab.rawValue
    }

    /// Back on the left, a title in the middle, actions on the right.
    private func detail(@ViewBuilder title: () -> some View, @ViewBuilder actions: () -> some View = { EmptyView() }) -> some View {
        ZStack {
            HStack(spacing: 6) {
                Button { model.back() } label: {
                    Label(backTitle, systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                actions()
                RefreshButton(model: model)
            }
            title()
        }
    }

    private func box(_ id: String) -> some View {
        let game = model.game(id)
        let box = model.boxes[id]
        let away = box?.teams.first?.side ?? game?.away
        let home = box?.teams.last?.side ?? game?.home
        let state = box?.state ?? game?.state ?? .pre
        let detail = box?.detail ?? game?.detail ?? ""
        let venue = box?.venue ?? game?.venue ?? ""
        let recap = box?.recapURL ?? game?.recapURL
        return self.detail {
            TitleBlock(title: boxTitle(away, home),
                       subtitle: [detail, venue].filter { !$0.isEmpty }.joined(separator: " · "),
                       live: state == .live)
        } actions: {
            if let recap { RecapButton { model.openRecap(recap) } }
        }
    }

    private func boxTitle(_ away: Side?, _ home: Side?) -> String {
        guard let away, let home else { return "Box score" }
        guard let a = away.score, let h = home.score else { return "\(away.team.abbr) at \(home.team.abbr)" }
        return "\(away.team.abbr)  \(a) – \(h)  \(home.team.abbr)"
    }

    private func player(_ id: String) -> some View {
        let card = model.players[id]
        return detail { TitleBlock(title: card?.name ?? "Player", subtitle: card?.subtitle ?? " ") }
    }

    private var team: some View {
        let page = model.stack.last.flatMap { model.teamPages[$0] }
        let season = model.teamSeason
        return detail {
            StepTitle(
                title: page?.name ?? "Team",
                subtitle: season > 0 ? Season.label(season) : " ",
                canPrev: season > TeamPage.firstSeason, canNext: season > 0 && season < model.seasonYear,
                prev: { model.stepTeamSeason(-1) }, next: { model.stepTeamSeason(1) }
            )
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Button { model.back() } label: {
                Label(backTitle, systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            SearchField(model: model)
        }
    }
}

struct TitleBlock: View {
    let title: String
    let subtitle: String
    var live = false

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 14, weight: .semibold)).monospacedDigit().lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(live ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
    }
}

/// Refreshes on click; spins while a refresh the user asked for is running.
struct RefreshButton: View {
    let model: AppModel

    var body: some View {
        ZStack {
            if model.refreshing {
                ProgressView().controlSize(.small)
            } else {
                IconButton(symbol: "arrow.clockwise") { model.refreshNow() }.help("Refresh (R)")
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// A title between two chevrons: the day in the scores, the season in the standings and on a team page.
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
                Text(title).font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1)
                Text(subtitle).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minWidth: 150)
            IconButton(symbol: "chevron.right", enabled: canNext, action: next)
        }
    }
}
