import NBAKit
import SwiftUI

struct PanelView: View {
    let model: AppModel
    @FocusState private var focused: Bool

    private var width: CGFloat {
        if !model.stack.isEmpty { return Layout.detail }
        return model.tab == .scores ? Layout.compact : Layout.wide
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
        .onKeyPress(phases: .down) { press in handle(press) ? .handled : .ignored }
    }

    @ViewBuilder private var content: some View {
        switch model.stack.last {
        case .box(let id): BoxScoreView(model: model, id: id)
        case nil:
            switch model.tab {
            case .scores: ScoresView(model: model)
            case .standings: StandingsView(model: model)
            }
        }
    }

    /// Whether the screen shows data: an error is then a footnote, not the whole view.
    private var hasContent: Bool {
        switch model.stack.last {
        case .box(let id): model.boxes[id] != nil
        case nil: model.tab == .scores ? model.viewLoaded : model.standings[model.standingsSeason] != nil
        }
    }

    private func handle(_ press: KeyPress) -> Bool {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return false }
        let inBox = model.openBoxID != nil
        switch press.key {
        case .escape:
            if model.stack.isEmpty { StatusItem.closePanel() } else { model.back() }
        case .leftArrow, .rightArrow:
            let delta = press.key == .leftArrow ? -1 : 1
            if inBox { model.stepBox(delta) }
            else if model.tab == .scores { model.stepDay(delta) }
            else { model.stepSeason(delta) }
        case .upArrow, .downArrow:
            guard !inBox, model.tab == .scores else { return false }
            model.moveSelection(press.key == .upArrow ? -1 : 1)
        case .return:
            guard !inBox, model.tab == .scores else { return false }
            model.openSelected()
        default:
            switch press.characters {
            case "r": model.refreshNow()
            case "t": model.show(.scores); model.goCurrent()
            case "b": model.show(.scores)
            case "s": model.show(model.tab == .standings && model.stack.isEmpty ? .scores : .standings)
            case "y":
                guard let game = model.recapTarget else { return false }
                model.openRecap(game)
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
            case nil: top
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var top: some View {
        HStack(spacing: 10) {
            Picker("View", selection: Binding(get: { model.tab }, set: { model.show($0) })) {
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
                    title: Season.label(model.standingsSeason), subtitle: "Regular season",
                    canPrev: model.standingsSeason > Standings.firstSeason,
                    canNext: model.standingsSeason < max(model.seasonYear, model.latestSeason),
                    prev: { model.stepSeason(-1) }, next: { model.stepSeason(1) }
                )
            }
            Spacer(minLength: 0)
            RefreshButton(model: model)
        }
    }

    private var daySubtitle: String {
        let games = model.viewGames
        if model.viewingCurrent, !games.isEmpty {
            return "Today · \(games.count == 1 ? "1 game" : "\(games.count) games")"
        }
        return games.isEmpty ? (model.viewingCurrent ? "Today" : " ") : games.subtitle
    }

    private func box(_ id: String) -> some View {
        let game = model.game(id)
        let box = model.boxes[id]
        let away = box?.teams.first?.side ?? game?.away
        let home = box?.teams.last?.side ?? game?.home
        let state = box?.state ?? game?.state ?? .pre
        let detail = box?.detail ?? game?.detail ?? ""
        let venue = box?.venue ?? game?.venue ?? ""
        return ZStack {
            HStack {
                Button { model.back() } label: {
                    Label(model.tab.rawValue, systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                if let game, game.recapURL != nil { RecapButton { model.openRecap(game) } }
                RefreshButton(model: model)
            }
            VStack(spacing: 1) {
                Text(title(away, home)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                Text([detail, venue].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(state == .live ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
        }
    }

    private func title(_ away: Side?, _ home: Side?) -> String {
        guard let away, let home else { return "Box score" }
        guard let a = away.score, let h = home.score else { return "\(away.team.abbr) at \(home.team.abbr)" }
        return "\(away.team.abbr)  \(a) – \(h)  \(home.team.abbr)"
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
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minWidth: 150)
            IconButton(symbol: "chevron.right", enabled: canNext, action: next)
        }
    }
}
