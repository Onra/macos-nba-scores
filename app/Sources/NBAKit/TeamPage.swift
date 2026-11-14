import Foundation

public struct RosterPlayer: Codable, Hashable, Sendable, Identifiable {
    public var id = ""
    public var name = ""
    public var jersey = ""
    public var pos = ""
    public var age: Int?
    /// "Out", or "Out · 22 Nov" once the league's injury list says when he is expected back.
    public var injury = ""
}

public struct TeamGameSide: Codable, Hashable, Sendable {
    public var id = ""
    public var abbr = "TBD"
    public var name = ""
    public var logo: URL?
    public var score = ""
    public var winner = false

    init(_ c: JSON) {
        let t = c["team"]
        id = t["id"].text
        abbr = t["abbreviation"].string ?? "TBD"
        name = t["shortDisplayName"].string ?? t["displayName"].text
        logo = URL(string: t["logos"][0]["href"].text)
        // A number on the scoreboard, an object in a team's schedule.
        score = c["score"]["displayValue"].string ?? c["score"].text
        winner = c["winner"].bool == true
    }

    public var team: Team {
        var team = Team()
        team.id = id
        team.abbr = abbr
        team.name = name
        team.logo = logo
        return team
    }
}

/// One game of a team's season, seen from that team.
public struct TeamGame: Codable, Hashable, Sendable, Identifiable {
    public var id = ""
    /// The NBA's game day, a US Eastern date: "20261021".
    public var day = ""
    public var date: Date?
    /// ESPN season type: 2 regular season, 5 play-in, 3 playoffs.
    public var phase = 2
    public var state = Game.State.pre
    public var detail = ""
    /// "NBA Cup - Group Play", "Rescheduled from Jan 9"…
    public var note = ""
    public var atHome = false
    public var us: TeamGameSide
    public var opp: TeamGameSide
    /// "W", "L", or "" until the game is over.
    public var result = ""

    public var cup: CupRound? { CupRound(headline: note) }

    /// The Cup round, beside the opponent: "Cup", "Cup QF", "Cup final".
    public var cupTag: String? {
        switch cup {
        case nil: nil
        case .group, .other: "Cup"
        case .final: "Cup final"
        case .quarterfinal, .semifinal: "Cup \(cup!.rawValue)"
        }
    }

    /// "W 127–105", "L 98–110 OT", "Q3 5:12  54–60"; nil before tip-off.
    public var resultText: String? {
        guard state != .pre else { return nil }
        let score = "\(us.score)–\(opp.score)"
        guard state == .post else { return "\(detail)  \(score)" }
        let extra = detail.isEmpty || detail == "Final" ? "" : " " + detail.replacingOccurrences(of: "Final/", with: "")
        return "\(result) \(score)\(extra)"
    }
}

extension Game.State: Codable {}

/// A team's page: record, standing, coach, roster and the games of a season.
public struct TeamPage: Codable, Sendable {
    /// ESPN has no full schedules before 1992-93.
    public static let firstSeason = 1993
    /// ESPN season types, in the order the page lists them.
    public static let phases: [(type: Int, label: String)] = [(2, "Regular season"), (5, "Play-in"), (3, "Playoffs")]

    public var id = ""
    public var abbr = ""
    public var name = ""
    public var logo: URL?
    /// The season, by the year it ends.
    public var season = 0
    public var seasonLabel = ""
    /// The season being played: the only one ESPN has a roster and a standing for.
    public var current = false
    public var record = ""
    public var homeRecord = ""
    public var roadRecord = ""
    public var standing = ""
    public var coach = ""
    /// The season's head coaches, from Basketball-Reference: past seasons too.
    public var coaches: [CoachRef] = []
    public var roster: [RosterPlayer] = []
    public var games: [TeamGame] = []

    /// `schedules`: by ESPN season type. `injuries`: the league's injury list, by athlete id.
    public init(id: String, info: JSON, roster rosterJSON: JSON?, schedules: [Int: JSON], current: Bool,
                injuries: [String: Injury] = [:]) {
        let t = info["team"]
        self.id = id
        abbr = t["abbreviation"].text
        name = t["displayName"].text
        logo = URL(string: t["logos"][0]["href"].text)
        let requested = schedules[2]?["requestedSeason"]
        season = requested?["year"].int ?? 0
        seasonLabel = requested?["displayName"].text ?? ""
        self.current = current
        games = TeamPage.phases
            .flatMap { TeamPage.games(schedules[$0.type], team: id, phase: $0.type) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        // The NBA Cup final is in ESPN's regular season but not in the standings.
        let counted = games.filter { $0.phase == 2 && $0.cup != .final }
        func record(_ games: [TeamGame]) -> String {
            let wins = games.count { $0.result == "W" }, losses = games.count { $0.result == "L" }
            return wins + losses > 0 ? "\(wins)-\(losses)" : ""
        }
        self.record = record(counted)
        homeRecord = record(counted.filter(\.atHome))
        roadRecord = record(counted.filter { !$0.atHome })

        guard current else { return }
        standing = t["standingSummary"].text
        if let rosterJSON {
            roster = rosterJSON["athletes"].array.map { a in
                RosterPlayer(id: a["id"].text, name: a["displayName"].text, jersey: a["jersey"].text,
                             pos: a["position"]["abbreviation"].text, age: a["age"].int,
                             injury: injuries[a["id"].text]?.short ?? a["injuries"][0]["status"].text)
            }
            .sorted { (Int($0.jersey) ?? 999, $0.name) < (Int($1.jersey) ?? 999, $1.name) }
            let first = rosterJSON["coach"][0]
            coach = [first["firstName"].text, first["lastName"].text].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    static func games(_ json: JSON?, team: String, phase: Int) -> [TeamGame] {
        (json?["events"].array ?? []).compactMap { event in
            let comp = event["competitions"][0]
            let type = (comp["status"].exists ? comp["status"] : event["status"])["type"]
            var away: TeamGameSide?, home: TeamGameSide?
            for c in comp["competitors"].array {
                if c["homeAway"].text == "home" { home = TeamGameSide(c) } else { away = TeamGameSide(c) }
            }
            guard let away, let home else { return nil }
            let atHome = home.id == team
            let (us, opp) = atHome ? (home, away) : (away, home)
            let state = Game.State(rawValue: type["state"].text) ?? .pre
            // A postponed game is over with no winner (2020: the players' strike).
            if state == .post, !us.winner, !opp.winner { return nil }
            let date = Game.parseDate(event["date"].text)
            return TeamGame(
                id: event["id"].text, day: date.map(GameDay.eastern) ?? GameDay.key(fromISO: event["date"].text),
                date: date, phase: phase, state: state, detail: type["shortDetail"].text,
                note: comp["notes"][0]["headline"].text, atHome: atHome, us: us, opp: opp,
                result: state == .post ? (us.winner ? "W" : "L") : ""
            )
        }
    }

    /// "61-21 · home 33-8 · away 28-13 · 1st in Pacific Division"
    public var subtitle: String {
        var bits: [String] = []
        if !record.isEmpty { bits.append(record) }
        if !homeRecord.isEmpty { bits.append("home \(homeRecord)") }
        if !roadRecord.isEmpty { bits.append("away \(roadRecord)") }
        if !standing.isEmpty { bits.append(standing) }
        if bits.isEmpty { bits.append(games.isEmpty ? "no games this season" : "no games played yet") }
        return bits.joined(separator: " · ")
    }

    /// A past season whose games are all over never changes.
    public var final: Bool { !current && games.allSatisfy { $0.state == .post } }
}

public extension GameDay {
    /// The NBA's game day of a date: "2026-10-22T02:00Z" -> "20261021".
    static func eastern(_ date: Date) -> String {
        easternFormatter.string(from: date)
    }

    private static let easternFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
