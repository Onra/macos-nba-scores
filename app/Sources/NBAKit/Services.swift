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
        guard let info = await info, let regular = await regular else {
            _ = await (roster, playIn, playoffs)
            return cached?.value
        }
        var schedules = [2: regular]
        schedules[5] = await playIn
        schedules[3] = await playoffs
        // The current season's end year, asked for by number, is still the current one.
        let latest = regular["season"]["year"].int ?? 0
        let current = season == 0 || (latest > 0 && season >= latest)
        let page = TeamPage(id: id, info: info, roster: await roster, schedules: schedules, current: current)
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
