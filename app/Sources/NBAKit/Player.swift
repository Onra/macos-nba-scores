import Foundation

public struct StatLine: Codable, Hashable, Sendable, Identifiable {
    /// "Regular season", or a season: "2025-26".
    public var label = ""
    public var team = ""
    public var teamID = ""
    /// By ESPN label: GP, MIN, PTS…
    public var stats: [String: String] = [:]

    public init(label: String = "", team: String = "", teamID: String = "", stats: [String: String] = [:]) {
        self.label = label
        self.team = team
        self.teamID = teamID
        self.stats = stats
    }

    public var id: String { label + teamID }
}

/// An award or a title, with the seasons it was won, newest first.
public struct Award: Codable, Hashable, Sendable, Identifiable {
    public var name = ""
    public var seasons: [String] = []

    public var id: String { name }
    /// "2× MVP"
    public var label: String { seasons.count > 1 ? "\(seasons.count)× \(name)" : name }
}

public struct Salary: Codable, Hashable, Sendable {
    /// The season, by the year it ends.
    public var year = 0
    public var season = ""
    public var team = ""
    public var teamID = ""
    public var amount = 0
    /// "player option", "team option", "early termination option"
    public var option = ""
    /// A season to come, from Basketball-Reference.
    public var future = false
    public var yearsRemaining: Int?
}

/// One line of the salary section.
public struct SalaryRow: Hashable, Sendable, Identifiable {
    public var season = ""
    public var team = ""
    public var amount = ""
    public var note = ""
    public var current = false

    public var id: String { season }
}

public struct PlayerCard: Codable, Sendable, Identifiable {
    /// The columns every stat table of the card shows, by ESPN label.
    public static let columns = ["GP", "MIN", "PTS", "REB", "AST", "STL", "BLK", "TO", "FG%", "3P%", "FT%"]

    public var id = ""
    public var name = ""
    public var headshot: URL?
    public var jersey = ""
    public var position = ""
    public var team = ""
    public var teamID = ""
    public var teamAbbr = ""
    /// "Active", "Free Agent", or "Inactive" for a retired player (whose team is still the last he played for).
    public var status = ""
    public var age: Int?
    public var dob = ""
    public var birthplace = ""
    public var height = ""
    public var weight = ""
    public var draft = ""
    public var college = ""
    public var experience = ""
    public var injury = ""
    /// "2026-27 regular season"
    public var statsTitle = ""
    /// This season, the playoffs, the career.
    public var splits: [StatLine] = []
    /// Regular seasons, newest first.
    public var career: [StatLine] = []
    public var careerTotal: [String: String]?
    public var awards: [Award] = []
    /// NBA championships and NBA Cups won with his team.
    public var titles: [Award] = []
    /// Newest first: the seasons to come, then this one and the past.
    public var salaries: [Salary] = []

    public init() {}

    /// `teams`: ESPN team id -> abbreviation.
    public init(id: String, bio: JSON, overview: JSON?, stats: JSON?, teams: [String: String]) {
        let a = bio["athlete"]
        let t = a["team"]
        self.id = id
        name = a["displayName"].text
        headshot = URL(string: a["headshot"]["href"].text)
        jersey = a["displayJersey"].string ?? a["jersey"].string.map { "#\($0)" } ?? ""
        position = a["position"]["displayName"].text
        team = t["displayName"].text
        teamID = t["id"].text
        teamAbbr = t["abbreviation"].text
        status = a["status"]["name"].text
        age = a["age"].int
        dob = a["displayDOB"].text
        birthplace = a["displayBirthPlace"].text
        height = a["displayHeight"].text
        weight = a["displayWeight"].text
        draft = a["displayDraft"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "Undrafted"
        college = a["college"]["name"].text
        experience = a["displayExperience"].text
        if let first = a["injuries"].array.first {
            injury = [first["status"].text, first["details"]["type"].text].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        statsTitle = a["statsSummary"]["displayName"].text.replacingOccurrences(of: " stats", with: "")

        func pick(_ labels: JSON, _ values: JSON) -> [String: String] {
            var all: [String: String] = [:]
            for (label, value) in zip(labels.array, values.array) { all[label.text] = value.text }
            return Dictionary(uniqueKeysWithValues: PlayerCard.columns.map { ($0, all[$0] ?? "") })
        }

        if let overview {
            let block = overview["statistics"]
            splits = block["splits"].array.map {
                StatLine(label: $0["displayName"].text, stats: pick(block["labels"], $0["stats"]))
            }
            awards = overview["awards"].array.map { award in
                Award(name: award["name"].text,
                      seasons: award["seasons"].array.compactMap { $0.int }.map(Season.label))
            }
        }
        for category in stats?["categories"].array ?? [] where category["name"].text == "averages" {
            career = category["statistics"].array.map { row in
                let teamID = row["teamId"].text
                return StatLine(label: row["season"]["displayName"].text, team: teams[teamID] ?? "", teamID: teamID,
                                stats: pick(category["labels"], row["stats"]))
            }
            .reversed()
            careerTotal = pick(category["labels"], category["totals"])
        }
    }

    public var retired: Bool { status == "Inactive" }

    /// What the card says in place of the team: "Retired", "Free agent" or the team.
    public var teamText: String {
        if retired { return "Retired" }
        return status == "Free Agent" ? "Free agent" : team
    }

    /// "#2 · Guard · Oklahoma City Thunder"
    public var subtitle: String {
        [jersey, position, teamText].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "2026-27 regular season" -> "2026-27 season": the lines say which part.
    public var seasonTitle: String {
        statsTitle.isEmpty ? "Season" : statsTitle.replacing(/(?i) regular season$/, with: "") + " season"
    }

    /// The lines of the season section. A retired player's only split is his career, already the last career line.
    public var seasonLines: [StatLine] {
        guard !retired else { return [] }
        let names = ["Regular Season": "Regular season", "Postseason": "Playoffs"]
        return splits.map { StatLine(label: names[$0.label] ?? $0.label, stats: $0.stats) }
    }

    /// Stat by stat, whether the regular season beats the career: 1 better, -1 worse.
    public var seasonTrends: [String: Int] {
        guard let season = splits.first(where: { $0.label == "Regular Season" }),
              let career = splits.first(where: { $0.label == "Career" }) else { return [:] }
        return PlayerCard.trends(season.stats, against: career.stats)
    }

    /// The stats a season is compared on: the higher the better, but for turnovers.
    /// MIN is in, as a player's role growing or shrinking; GP is not (a season is never as long as a career).
    public static func trends(_ stats: [String: String], against reference: [String: String]) -> [String: Int] {
        var trends: [String: Int] = [:]
        for key in columns where key != "GP" {
            guard let a = Double(stats[key] ?? ""), let b = Double(reference[key] ?? ""), a != b else { continue }
            trends[key] = (a > b ? 1 : -1) * (key == "TO" ? -1 : 1)
        }
        return trends
    }

    /// Newest first: the seasons to come, with their options, this season in bold, then the past.
    public var salaryRows: [SalaryRow] {
        let paid = salaries.filter { $0.amount > 0 }
        guard !paid.isEmpty else {
            guard let first = salaries.first, !retired else { return [] }
            return [SalaryRow(season: first.season, team: first.team, amount: "n/a", note: "two-way or undisclosed")]
        }
        let hasFuture = paid.contains(where: \.future)
        let current = paid.firstIndex { !$0.future }
        return paid.enumerated().map { index, salary in
            var note = salary.option
            // Without the seasons to come, say at least how long the deal runs.
            if index == current, !hasFuture, let years = salary.yearsRemaining, years > 1 {
                note = "\(years - 1) more year\(years > 2 ? "s" : "") on the deal"
            }
            return SalaryRow(season: salary.season, team: salary.team, amount: Format.money(salary.amount),
                             note: note, current: index == current)
        }
    }

    /// ESPN files every season of a contract under the player's current team; the career lines know where
    /// he played each season. Then come the seasons to come, from Basketball-Reference.
    public mutating func setSalaries(_ contracts: [Salary], table: ContractsTable?, teams: [String: String]) {
        var teamOfSeason: [String: String] = [:]
        // A season split between two teams also has a line for the whole of it, with no team: the newest
        // line that names one is where he ended the season.
        for line in career where teamOfSeason[line.label] == nil && !line.team.isEmpty { teamOfSeason[line.label] = line.team }
        var past = contracts.filter { !$0.future }.sorted { $0.year > $1.year }
        for i in past.indices {
            past[i].team = teamOfSeason[past[i].season] ?? teams[past[i].teamID] ?? ""
        }
        var future = table?.future(name: name, team: teamAbbr, after: past.map(\.season).max() ?? "") ?? []
        for i in future.indices { future[i].team = teamAbbr }
        salaries = future.reversed() + past
    }
}

public enum Format {
    /// 40806150 -> "$40.8M"; 950000 -> "$950K"
    public static func money(_ amount: Int) -> String {
        if amount >= 1_000_000 { return "$" + String(format: "%.1f", Double(amount) / 1e6) + "M" }
        if amount >= 1000 { return "$\(Int((Double(amount) / 1000).rounded()))K" }
        return amount > 0 ? "$\(amount)" : ""
    }

    /// ESPN's US measure with the metric one after it: 6' 6" -> 6' 6" (1.98 m)
    public static func height(_ text: String) -> String {
        guard let match = text.firstMatch(of: /(\d+)'\s*(\d+)?/), let feet = Double(match.1) else { return text }
        let metres = (feet * 12 + (match.2.flatMap { Double($0) } ?? 0)) * 0.0254
        return "\(text) (\(String(format: "%.2f", metres)) m)"
    }

    /// 195 lbs -> 195 lbs (88 kg)
    public static func weight(_ text: String) -> String {
        guard let match = text.firstMatch(of: /(?i)(\d+(?:\.\d+)?)\s*lb/), let pounds = Double(match.1) else { return text }
        return "\(text) (\(Int((pounds * 0.45359237).rounded())) kg)"
    }
}

/// Basketball-Reference's table of contracts: the salaries of the seasons to come, with player and team options.
/// ESPN has no future seasons.
public struct ContractsTable: Codable, Sendable {
    public struct Player: Codable, Sendable {
        public var name = ""
        /// ESPN abbreviation.
        public var team = ""
        public var years: [Salary] = []
    }

    public var players: [Player] = []

    public init(html: String) {
        var labels: [Substring: String] = [:]
        for match in html.matches(of: /<th[^>]*data-stat="y(\d)"[^>]*>([^<]*)</) {
            labels[match.1] = match.2.trimmingCharacters(in: .whitespaces)
        }
        let options = ["salary-pl": "player option", "salary-tm": "team option", "salary-et": "early termination option"]
        for row in Text.rows(html) {
            // The name sits in a (doubled) link: <a href="/players/..."><a href='/players/...'>Name</a></a>
            guard let name = row.firstMatch(of: /data-stat="player"[^>]*>(?:<a [^>]*>)+([^<]+)<\/a>/) else { continue }
            let code = row.firstMatch(of: /data-stat="team_id"[^>]*>(?:<a[^>]*>)?([A-Z]{3})/).map { String($0.1) } ?? ""
            var player = Player(name: Text.unescape(String(name.1)), team: Teams.bbrefCodes[code] ?? code)
            for cell in row.matches(of: /<td class="right ?([a-z-]*)" data-stat="y(\d)"(?: csk="(\d+)")?/) {
                guard let amount = cell.3.flatMap({ Int($0) }), let season = labels[cell.2] else { continue }
                player.years.append(Salary(year: (Int(season.prefix(4)) ?? 0) + 1, season: season, amount: amount,
                                           option: options[String(cell.1)] ?? "", future: true))
            }
            players.append(player)
        }
    }

    /// The seasons after `last`, the latest one ESPN knows.
    public func future(name: String, team: String, after last: String) -> [Salary] {
        let key = Text.normalizedName(name)
        var hits = players.filter { Text.normalizedName($0.name) == key }
        // Two players of the same name: the one on his team.
        if hits.count > 1 { hits = hits.filter { $0.team == team }.isEmpty ? [hits[0]] : hits.filter { $0.team == team } }
        return hits.first?.years.filter { $0.season > last } ?? []
    }
}
