import Foundation

/// Everything beyond the scoreboard: team pages, player cards and the search, with their caches.
/// Sources are ESPN (no key) and Basketball-Reference for what ESPN lacks.
public struct Library: Sendable {
    static let site = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba"
    static let athletes = "https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/athletes/"
    static let core = "https://sports.core.api.espn.com/v2/sports/basketball/leagues/nba/athletes/"
    static let bbref = "https://www.basketball-reference.com"

    static let day: TimeInterval = 86400

    let web: Web
    let cache: DiskCache

    public init(web: Web = Web(), cache: DiskCache = DiskCache()) {
        self.web = web
        self.cache = cache
    }

    // MARK: Teams

    /// The 30 teams of today, kept for 30 days.
    public func teams() async -> [TeamRef] {
        if let teams = cache.fresh([TeamRef].self, "teams", maxAge: 30 * Library.day) { return teams }
        if let json = await web.optionalJSON(URL(string: "\(Library.site)/teams")!) {
            let teams = Teams.parse(json)
            if !teams.isEmpty {
                cache.save(teams, "teams")
                return teams
            }
        }
        return cache.load([TeamRef].self, "teams")?.value ?? []
    }

    /// A team's page for a season (the year it ends; 0 for the current one).
    /// The current season is kept for 5 minutes, a finished past season for good.
    public func team(_ id: String, season: Int = 0) async -> TeamPage? {
        let key = "teams/\(id)-\(season)"
        let cached = cache.load(TeamPage.self, key)
        if let cached, cached.value.final || cached.age < 300 { return cached.value }

        let base = "\(Library.site)/teams/\(id)"
        let query = season > 0 ? "?season=\(season)&" : "?"
        async let info = web.optionalJSON(URL(string: base)!)
        async let roster = web.optionalJSON(URL(string: "\(base)/roster")!)
        async let regular = web.optionalJSON(URL(string: "\(base)/schedule\(query)seasontype=2")!)
        async let playIn = web.optionalJSON(URL(string: "\(base)/schedule\(query)seasontype=5")!)
        async let playoffs = web.optionalJSON(URL(string: "\(base)/schedule\(query)seasontype=3")!)
        // When the injured are expected back: the roster only says who is hurt.
        async let injured = season == 0 ? web.optionalJSON(URL(string: "\(Library.site)/injuries")!) : nil
        guard let info = await info, let regular = await regular else {
            _ = await (roster, playIn, playoffs, injured)
            return cached?.value
        }
        var schedules = [2: regular]
        schedules[5] = await playIn
        schedules[3] = await playoffs
        // The current season's end year, asked for by number, is still the current one.
        let latest = regular["season"]["year"].int ?? 0
        let current = season == 0 || (latest > 0 && season >= latest)
        let page = TeamPage(id: id, info: info, roster: await roster, schedules: schedules, current: current,
                            injuries: (await injured).map(Injuries.parse) ?? [:])
        cache.save(page, key)
        return page
    }

    // MARK: Players

    /// A player's card, kept for 6 hours.
    public func player(_ id: String) async -> PlayerCard? {
        let key = "players/\(id)"
        let cached = cache.load(PlayerCard.self, key)
        if let cached, cached.age < 6 * 3600 { return cached.value }

        async let bio = web.optionalJSON(URL(string: Library.athletes + id)!)
        async let overview = web.optionalJSON(URL(string: Library.athletes + id + "/overview")!)
        async let stats = web.optionalJSON(URL(string: Library.athletes + id + "/stats")!)
        async let contracts = contracts(id, known: cached?.value.salaries.filter { !$0.future } ?? [])
        async let teams = teams()
        async let table = contractsTable()
        guard let bio = await bio else {
            _ = await (overview, stats, contracts, teams, table)
            return cached?.value
        }
        let directory = await teams
        let abbrs = Dictionary(directory.map { ($0.id, $0.abbr) }, uniquingKeysWith: { a, _ in a })
        var card = PlayerCard(id: id, bio: bio, overview: await overview, stats: await stats, teams: abbrs)
        card.setSalaries(await contracts, table: await table, teams: abbrs)
        card.titles = await titles(id, career: card.career, teams: directory)
        cache.save(card, key)
        return card
    }

    /// The salary of each season under contract, up to this one. Past salaries never change: they come from `known`.
    func contracts(_ id: String, known: [Salary]) async -> [Salary] {
        guard let index = await web.optionalJSON(URL(string: Library.core + id + "/contracts?limit=50")!) else { return known }
        let refs: [(year: Int, url: URL)] = index["items"].array.compactMap { item in
            let ref = item["$ref"].text.replacingOccurrences(of: "http://", with: "https://")
            guard let year = ref.firstMatch(of: /\/contracts\/(\d+)/).flatMap({ Int($0.1) }), let url = URL(string: ref) else { return nil }
            return (year, url)
        }
        let current = refs.map(\.year).max() ?? 0
        let old = Dictionary(known.map { ($0.year, $0) }, uniquingKeysWith: { a, _ in a })
        return await withTaskGroup(of: Salary?.self) { group in
            for ref in refs {
                group.addTask {
                    if ref.year < current, let salary = old[ref.year] { return salary }
                    guard let contract = await web.optionalJSON(ref.url) else { return old[ref.year] }
                    let team = contract["team"]["$ref"].text.firstMatch(of: /\/teams\/(\d+)/).map { String($0.1) } ?? ""
                    return Salary(year: ref.year, season: Season.label(ref.year), teamID: team,
                                  amount: contract["salary"].int ?? 0, yearsRemaining: contract["yearsRemaining"].int)
                }
            }
            var salaries: [Salary] = []
            for await salary in group { if let salary { salaries.append(salary) } }
            return salaries.sorted { $0.year > $1.year }
        }
    }

    /// One page for every player, fetched at most once a day. A stale table beats none.
    func contractsTable() async -> ContractsTable? {
        if let table = cache.fresh(ContractsTable.self, "bbref-contracts", maxAge: Library.day) { return table }
        if let html = await web.page(URL(string: "\(Library.bbref)/contracts/players.html")!) {
            let table = ContractsTable(html: html)
            if !table.players.isEmpty {
                cache.save(table, "bbref-contracts")
                return table
            }
        }
        return cache.load(ContractsTable.self, "bbref-contracts")?.value
    }

    // MARK: Titles

    /// Season end year -> ESPN team id of the NBA champion: one page for every season, kept for a week.
    public func champions(teams: [TeamRef]) async -> [Int: String] {
        if let champions = cache.fresh([Int: String].self, "champions", maxAge: 7 * Library.day) { return champions }
        if let html = await web.page(URL(string: "\(Library.bbref)/leagues/")!) {
            let champions = Titles.champions(html: html, teams: teams)
            if !champions.isEmpty {
                cache.save(champions, "champions")
                return champions
            }
        }
        return cache.load([Int: String].self, "champions")?.value ?? [:]
    }

    /// Season end year -> winner of the NBA Cup. A Cup is looked for once its final is past, and kept once found.
    public func cupWinners(now: Date = Date()) async -> [Int: Titles.CupFinal] {
        var cups = cache.load([Int: Titles.CupFinal].self, "cups")?.value ?? [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let thisYear = calendar.component(.year, from: now)
        let todo = (Titles.firstCup...(thisYear + 1)).filter { year in
            guard cups[year] == nil,
                  let last = calendar.date(from: DateComponents(year: year - 1, month: 12, day: Titles.cupDays.upperBound + 1))
            else { return false }
            return last < now
        }
        guard !todo.isEmpty else { return cups }
        for year in todo {
            let found = await withTaskGroup(of: Titles.CupFinal?.self) { group in
                for day in Titles.cupDays {
                    group.addTask {
                        let key = String(format: "%d12%02d", year - 1, day)
                        guard let board = await web.optionalJSON(ESPN.scoreboardURL(day: key)) else { return nil }
                        return Titles.cupFinal(scoreboard: board)
                    }
                }
                var found: Titles.CupFinal?
                for await final in group { found = found ?? final }
                return found
            }
            if let found { cups[year] = found }
        }
        cache.save(cups, "cups")
        return cups
    }

    func titles(_ id: String, career: [StatLine], teams: [TeamRef]) async -> [Award] {
        async let champions = champions(teams: teams)
        async let cups = cupWinners()
        let (nba, cup) = await (champions, cups)
        let needed = Titles.candidates(career: career, champions: nba, cups: cup)
        let seasons = Set(needed.nba + needed.cup)
        let logs = await withTaskGroup(of: (Int, [Titles.LogGame]).self) { group in
            for season in seasons {
                group.addTask {
                    let log = await web.optionalJSON(URL(string: Library.athletes + id + "/gamelog?season=\(season)")!)
                    return (season, log.map(Titles.games) ?? [])
                }
            }
            var logs: [Int: [Titles.LogGame]] = [:]
            for await (season, log) in group { logs[season] = log }
            return logs
        }
        return Titles.won(career: career, champions: nba, cups: cup, logs: logs)
    }

    // MARK: NBA Cup and playoffs

    /// The games of one day, as last fetched. A finished day is never fetched again.
    struct DayEntry<G: Codable & Sendable>: Codable, Sendable {
        var games: [G]
        var final: Bool
        var at: Date
    }

    struct CupCache: Codable, Sendable {
        var days: [String: DayEntry<CupGame>] = [:]
        var official: CupOfficial?
        var officialAt: Date?
        var conferences: [String: String] = [:]
    }

    struct PlayoffCache: Codable, Sendable {
        var days: [String: DayEntry<PlayoffGame>] = [:]
        var teams: [String: SeededTeam] = [:]
        var teamsAt: Date?
    }

    /// The days of a window that need fetching: not the finished ones, nor the ones to come that were
    /// looked at in the last 6 hours (the knockout schedule is only set once the groups are done).
    static func stale<G>(_ window: [String], in days: [String: DayEntry<G>], today: String, now: Date, horizon: Int? = nil) -> [String] {
        window.filter { day in
            if let entry = days[day] {
                if entry.final { return false }
                if day > today, now.timeIntervalSince(entry.at) < 6 * 3600 { return false }
            }
            // Months away: nothing is scheduled yet.
            if let horizon, day > today, GameDay.days(from: today, to: day) > horizon { return false }
            return true
        }
    }

    /// The NBA Cup of a season (the year it ends). `today`: the day ESPN reports for now.
    /// The scoreboard of each day of the Cup is the reliable source for every result; NBA.com adds the group
    /// names and the clinch marks when it answers.
    public func cup(season: Int, today: String) async -> CupData? {
        let start = season - 1
        let key = "cup-\(Season.label(season))"
        var cached = cache.load(CupCache.self, key)?.value ?? CupCache()
        let now = Date()
        let todo = Library.stale(Cup.window(startYear: start), in: cached.days, today: today, now: now)

        // A Cup played long ago does not change, and NBA.com is slow to say so.
        let askOfficial = !(cached.officialAt.map { now.timeIntervalSince($0) < 600 } ?? false)
            && !(cached.official != nil && todo.isEmpty)
        let askConferences = cached.conferences.isEmpty
        async let boards = web.scoreboards(todo)
        async let official = askOfficial ? cupOfficial(season: season) : nil
        async let conferences = askConferences ? self.conferences() : nil

        let fetched = await boards
        for (day, board) in fetched {
            let games = Cup.games(day: day, scoreboard: board)
            cached.days[day] = DayEntry(games: games, final: day < today && games.allSatisfy { $0.state == .post }, at: now)
        }
        // The group names never change in a season: keep what we had when NBA.com does not answer.
        if let official = await official {
            cached.official = official
            cached.officialAt = now
        }
        if let conferences = await conferences { cached.conferences = conferences }
        if cached.days.isEmpty { return nil }
        cache.save(cached, key)
        let games = cached.days.keys.sorted().flatMap { cached.days[$0]!.games }
        return Cup.build(startYear: start, games: games, official: cached.official, conferences: cached.conferences)
    }

    func cupOfficial(season: Int) async -> CupOfficial? {
        let url = URL(string: "https://stats.nba.com/stats/iststandings?LeagueID=00&Season=\(Season.label(season))&Section=group")!
        return await web.nbaStats(url).flatMap(CupOfficial.init)
    }

    /// Team nickname -> "East" or "West".
    func conferences() async -> [String: String]? {
        guard let teams = await seededTeams(season: nil) else { return nil }
        return Dictionary(teams.values.map { ($0.nick, $0.conf) }, uniquingKeysWith: { a, _ in a })
    }

    func seededTeams(season: Int?) async -> [String: SeededTeam]? {
        guard let json = await web.optionalJSON(ESPN.standingsURL(season: season)) else { return nil }
        let teams = SeededTeam.parse(standings: json)
        return teams.isEmpty ? nil : teams
    }

    /// The playoffs of a season (the year it ends): play-in, bracket of series, champion.
    /// The regular-season standings give the seeds and, before the playoffs, the projected bracket.
    public func playoffs(season: Int, today: String) async -> PlayoffBracket? {
        let key = "playoffs-\(season)"
        var cached = cache.load(PlayoffCache.self, key)?.value ?? PlayoffCache()
        let now = Date()
        let todo = Library.stale(Playoffs.window(season: season), in: cached.days, today: today, now: now, horizon: 60)

        // The standings of a finished season do not move.
        let askTeams = !(cached.teamsAt.map { now.timeIntervalSince($0) < 3 * 3600 } ?? false)
            && !(!cached.teams.isEmpty && todo.isEmpty)
        async let boards = web.scoreboards(todo)
        async let teams = askTeams ? seededTeams(season: season) : nil

        let fetched = await boards
        for (day, board) in fetched {
            let games = Playoffs.games(day: day, scoreboard: board)
            cached.days[day] = DayEntry(games: games, final: day < today && games.allSatisfy { $0.state == .post }, at: now)
        }
        if let teams = await teams {
            cached.teams = teams
            cached.teamsAt = now
        }
        if cached.teams.isEmpty { return nil }
        cache.save(cached, key)
        // A game can show up under two days (late tip-offs): keep it once.
        var seen: Set<String> = []
        let games = cached.days.keys.sorted().flatMap { cached.days[$0]!.games }.filter { seen.insert($0.id).inserted }
        return Playoffs.build(season: season, games: games, teams: cached.teams)
    }

    // MARK: Award voting

    /// The voting of an award in a season, from Basketball-Reference's page of that season's awards: one page
    /// for every award, kept for good, which keeps clear of the site's rate limit. nil when it can't be reached.
    public func award(_ kind: AwardKind, season: Int) async -> AwardPage? {
        let key = "awards/\(season)"
        var tables = cache.load([String: [Vote]].self, key)?.value
        if tables == nil {
            let (html, status) = await web.pageWithStatus(URL(string: "\(Library.bbref)/awards/awards_\(season).html")!)
            // A season without a page: no voting.
            if status == 404 { return AwardPage(kind: kind, season: season) }
            let parsed = status == 200 ? Awards.parse(html: html) : [:]
            guard !parsed.isEmpty else { return nil }
            cache.save(parsed, key)
            tables = parsed
        }
        var rows = Awards.rows(kind, in: tables ?? [:])
        guard !rows.isEmpty else { return AwardPage(kind: kind, season: season) }
        async let ids = athleteIDs(rows.map(\.name))
        let directory = await teams()
        let athletes = await ids
        for i in rows.indices {
            rows[i].athlete = athletes[rows[i].name] ?? ""
            rows[i].teamID = Awards.teamID(rows[i].team, season: season, teams: directory)
        }
        return AwardPage(kind: kind, season: season, rows: rows)
    }

    /// Name -> ESPN athlete id ("" when its search does not find him): the page only names the players.
    func athleteIDs(_ names: [String]) async -> [String: String] {
        var known = cache.load([String: String].self, "awards/ids")?.value ?? [:]
        let todo = Set(names).filter { known[$0] == nil }
        guard !todo.isEmpty else { return known }
        var rest = Array(todo)[...]
        while !rest.isEmpty {
            let batch = rest.prefix(8)
            rest = rest.dropFirst(8)
            await withTaskGroup(of: (String, String?).self) { group in
                for name in batch {
                    group.addTask {
                        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                              let url = URL(string: "https://site.web.api.espn.com/apis/search/v2?limit=25&query=\(encoded)"),
                              let json = await web.optionalJSON(url, timeout: 8) else { return (name, nil) }
                        return (name, Awards.match(name, among: Search.parse(json).players))
                    }
                }
                // A search that failed is asked again next time; one that found nobody is not.
                for await (name, id) in group { if let id { known[name] = id } }
            }
        }
        cache.save(known, "awards/ids")
        return known
    }

    // MARK: Search

    /// NBA teams and players, past ones included. Empty under two characters.
    public func search(_ query: String) async -> [SearchResult] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))),
              let url = URL(string: "https://site.web.api.espn.com/apis/search/v2?limit=25&query=\(encoded)")
        else { return [] }
        async let directory = teams()
        let found = Search.parse(await web.optionalJSON(url, timeout: 8) ?? JSON(nil))
        let teams = found.teams + Search.aliases(query, teams: await directory, known: Set(found.teams.map(\.target)))
        let players = Array(found.players.prefix(max(0, Search.limit - teams.count)))
        return Search.merge(teams: teams, players: players, status: await statuses(players.map(\.target)))
    }

    /// ESPN athlete id -> "Active", "Free Agent" or "Inactive", from the athlete's bio, kept for a week.
    func statuses(_ ids: [String]) async -> [String: String] {
        struct Entry: Codable {
            var status: String
            var at: Date
        }
        var known = cache.load([String: Entry].self, "status")?.value ?? [:]
        let now = Date()
        let todo = ids.filter { known[$0].map { now.timeIntervalSince($0.at) > 7 * Library.day } ?? true }
        if !todo.isEmpty {
            await withTaskGroup(of: (String, String?).self) { group in
                for id in todo {
                    group.addTask {
                        let bio = await web.optionalJSON(URL(string: Library.athletes + id)!, timeout: 8)
                        return (id, bio?["athlete"]["status"]["name"].string)
                    }
                }
                for await (id, status) in group {
                    if let status { known[id] = Entry(status: status, at: now) }
                }
            }
            cache.save(known, "status")
        }
        return known.filter { ids.contains($0.key) }.mapValues(\.status)
    }
}
