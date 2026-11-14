import AppKit
import NBAKit
import Observation

enum Tab: String, CaseIterable {
    case scores = "Scores"
    case standings = "Standings"
}

/// A view opened on top of the scores or the standings; Esc steps back.
enum Route: Hashable {
    case box(String)
}

/// Everything the panel shows: the games by day, the box scores, the standings, and where the user is.
@MainActor @Observable
final class AppModel {
    // Scores
    private(set) var days: [String] = []
    /// The day ESPN reports for now.
    private(set) var currentDay = ""
    /// The day the panel shows.
    private(set) var viewDay = ""
    private(set) var seasonType = 0
    /// ESPN's current season, by the year it ends.
    private(set) var seasonYear = 0
    private(set) var games: [String: [Game]] = [:]
    private(set) var boxes: [String: BoxScore] = [:]

    // Standings, by season
    private(set) var standings: [Int: Standings] = [:]
    private(set) var standingsSeason = 0

    // Navigation
    private(set) var tab = Tab.scores
    private(set) var stack: [Route] = []
    /// The keyboard cursor in the scores; nil until an arrow key is used.
    private(set) var selected: Int?

    private(set) var error: String?
    /// A refresh the user asked for is running.
    private(set) var refreshing = false
    private(set) var panelOpen = false

    private let espn = ESPN()
    private var poller: Task<Void, Never>?

    // MARK: Derived

    var viewGames: [Game] { games[viewDay] ?? [] }
    var viewLoaded: Bool { games[viewDay] != nil }
    var viewingCurrent: Bool { viewDay == currentDay }
    var liveCount: Int { games[currentDay]?.liveCount ?? 0 }
    var dayIndex: Int? { days.firstIndex(of: viewDay) }

    /// Until this season's first game, the latest season is the one before.
    var latestSeason: Int { seasonYear == 0 ? 0 : seasonType >= 2 ? seasonYear : seasonYear - 1 }

    var openBoxID: String? {
        if case .box(let id) = stack.last { id } else { nil }
    }

    func game(_ id: String) -> Game? { viewGames.first { $0.id == id } }

    /// Changes whenever another screen is shown.
    var screen: AnyHashable {
        if let route = stack.last { return AnyHashable(route) }
        return tab == .scores ? AnyHashable(viewDay) : AnyHashable(standingsSeason)
    }

    // MARK: Fetching

    func fetchCurrent() async {
        do {
            let board = try await espn.scoreboard()
            guard !board.day.isEmpty else { return }
            days = GameDay.merge(days, board.days, [board.day])
            // The panel follows the day rollover unless the user has gone to another day.
            let following = currentDay.isEmpty || viewDay == currentDay
            currentDay = board.day
            if board.seasonType > 0 { seasonType = board.seasonType }
            if board.seasonYear > 0 { seasonYear = board.seasonYear }
            if following { viewDay = board.day }
            games[board.day] = board.games
            error = nil
        } catch {
            self.error = "Couldn't reach ESPN"
        }
    }

    func fetchView() async {
        if viewDay.isEmpty || viewingCurrent { return await fetchCurrent() }
        // A finished day never changes: the cached copy is the answer.
        if viewGames.allFinal { return }
        let day = viewDay
        do {
            games[day] = try await espn.scoreboard(day: day).games
            error = nil
        } catch {
            self.error = "Couldn't reach ESPN"
        }
    }

    func fetchBox(force: Bool = false) async {
        guard let id = openBoxID else { return }
        if !force, boxes[id]?.state == .post { return }
        do {
            boxes[id] = try await espn.boxScore(game: id)
            error = nil
        } catch {
            self.error = "Couldn't reach ESPN"
        }
    }

    func fetchStandings(force: Bool = false) async {
        let season = standingsSeason > 0 ? standingsSeason : latestSeason
        // A past season is final.
        if !force, season > 0, season < latestSeason, standings[season] != nil { return }
        do {
            let result = try await espn.standings(season: season > 0 ? season : nil)
            standings[season] = result
            error = nil
        } catch {
            self.error = "Couldn't reach ESPN"
        }
    }

    /// What is on screen, plus today for the menu bar.
    func refresh(force: Bool = false) async {
        await fetchCurrent()
        guard panelOpen || force else { return }
        if tab == .standings { await fetchStandings(force: force) }
        else if !viewingCurrent { await fetchView() }
        if openBoxID != nil { await fetchBox(force: force) }
    }

    /// A refresh the user asked for: shown for at least 0.8 s so that a fast one is still seen.
    func refreshNow() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            async let floor: Void? = try? Task.sleep(for: .milliseconds(800))
            await refresh(force: true)
            _ = await floor
            refreshing = false
        }
    }

    /// Every 30 s while a game is live, every 5 minutes otherwise.
    /// The viewed day, the standings and the box score are only refreshed while on screen.
    func start() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let boxLive = self.openBoxID.flatMap { self.boxes[$0] }?.state == .live
                let live = self.liveCount > 0 || (self.panelOpen && boxLive)
                try? await Task.sleep(for: .seconds(live ? 30 : 300))
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: Navigation

    /// Opening the panel always returns to today's scores.
    func panelOpened() {
        guard !panelOpen else { return }
        panelOpen = true
        stack = []
        tab = .scores
        selected = nil
        if !currentDay.isEmpty { viewDay = currentDay }
        Task { await refresh() }
    }

    func panelClosed() {
        panelOpen = false
    }

    func show(_ tab: Tab) {
        stack = []
        guard tab != self.tab else { return }
        self.tab = tab
        error = nil
        if tab == .standings {
            standingsSeason = latestSeason
            Task { await fetchStandings() }
        }
    }

    func back() {
        if !stack.isEmpty { stack.removeLast() }
    }

    func stepDay(_ delta: Int) {
        guard !days.isEmpty else { return }
        let index = dayIndex ?? 0
        let next = min(max(index + delta, 0), days.count - 1)
        guard next != index else { return }
        viewDay = days[next]
        selected = nil
        error = nil
        Task { await fetchView() }
    }

    func goCurrent() {
        guard !currentDay.isEmpty, !viewingCurrent else { return }
        viewDay = currentDay
        selected = nil
        error = nil
    }

    func stepSeason(_ delta: Int) {
        let season = standingsSeason + delta
        guard season >= Standings.firstSeason, season <= max(seasonYear, latestSeason) else { return }
        standingsSeason = season
        error = nil
        Task { await fetchStandings() }
    }

    func moveSelection(_ delta: Int) {
        guard !viewGames.isEmpty else { return }
        selected = min(max((selected ?? (delta > 0 ? -1 : viewGames.count)) + delta, 0), viewGames.count - 1)
    }

    func clearSelection() {
        selected = nil
    }

    func openSelected() {
        if let selected, viewGames.indices.contains(selected) { openBox(viewGames[selected]) }
    }

    func openBox(_ game: Game) {
        guard game.hasBoxScore else { return }
        stack.append(.box(game.id))
        error = nil
        Task { await fetchBox() }
    }

    /// The previous or next game of the day, from inside a box score.
    func stepBox(_ delta: Int) {
        guard let id = openBoxID, let index = viewGames.firstIndex(where: { $0.id == id }) else { return }
        var next = index + delta
        while viewGames.indices.contains(next) {
            if viewGames[next].hasBoxScore {
                stack[stack.count - 1] = .box(viewGames[next].id)
                error = nil
                Task { await fetchBox() }
                return
            }
            next += delta
        }
    }

    /// The recap of the open box score, else of the game under the keyboard cursor.
    var recapTarget: Game? {
        if let id = openBoxID { return game(id) }
        if let selected, viewGames.indices.contains(selected) { return viewGames[selected] }
        return nil
    }

    func openRecap(_ game: Game) {
        guard let url = game.recapURL else { return }
        NSWorkspace.shared.open(url)
        StatusItem.closePanel()
    }
}
