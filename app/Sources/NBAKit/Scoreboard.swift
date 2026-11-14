import Foundation

public struct Team: Hashable, Sendable {
    public var id = ""
    public var abbr = "TBD"
    /// Short name: "Trail Blazers".
    public var name = "TBD"
    /// Nickname, as NBA.com writes it in its addresses.
    public var nick = ""
    public var fullName = ""
    public var logo: URL?

    public init() {}
}

/// One team in one game.
public struct Side: Hashable, Sendable {
    public var team = Team()
    public var score: Int?
    public var record = ""
    public var winner = false
    /// Points by period.
    public var lines: [String] = []

    public init() {}

    init(_ c: JSON) {
        let t = c["team"]
        team.id = t["id"].text
        team.abbr = t["abbreviation"].string ?? "TBD"
        team.name = t["shortDisplayName"].string ?? t["displayName"].string ?? t["name"].string ?? "TBD"
        team.nick = t["name"].string ?? t["shortDisplayName"].text
        team.fullName = t["displayName"].text
        team.logo = URL(string: t["logo"].string ?? t["logos"][0]["href"].text)
        score = c["score"].int
        // The scoreboard says "records", the game summary "record".
        let records = c["records"].exists ? c["records"] : c["record"]
        record = records.array.first { $0["type"].text == "total" }?["summary"].text ?? ""
        winner = c["winner"].bool == true
        lines = c["linescores"].array.map { $0["displayValue"].string ?? $0["value"].text }
    }
}

/// The round of an NBA Cup game.
public enum CupRound: String, Sendable {
    case group = "Group"
    case quarterfinal = "QF"
    case semifinal = "SF"
    case final = "Final"
    case other = "Cup"

    /// ESPN notes: "NBA Cup - Group Play", "NBA Cup - Quarterfinals", "NBA Cup - Semifinals", "NBA Cup Championship".
    /// The first edition (2023-24) was the "NBA In-Season Tournament".
    public init?(headline: String) {
        guard headline.contains("NBA Cup") || headline.contains("In-Season Tournament") else { return nil }
        if headline.contains("Group") { self = .group }
        else if headline.contains("Quarterfinal") { self = .quarterfinal }
        else if headline.contains("Semifinal") { self = .semifinal }
        else if headline.contains("Championship") || headline.contains("Final") { self = .final }
        else { self = .other }
    }
}

public struct Game: Identifiable, Hashable, Sendable {
    public enum State: String, Sendable {
        case pre
        case live = "in"
        case post
    }

    /// What the status column says.
    public enum Status: Hashable, Sendable {
        case tipoff(Date)
        /// Live clock, final line, or anything else ESPN words itself ("Postponed", "TBD").
        case text(String)
    }

    public var id = ""
    public var date = Date.distantPast
    public var timeValid = true
    public var state = State.pre
    public var statusName = ""
    public var detail = ""
    public var seasonType = 0
    public var away = Side()
    public var home = Side()
    public var network = ""
    /// The betting line before tip-off: "DEN -11.5".
    public var odds = ""
    public var overUnder = ""
    /// Playoff series state, or a note such as "Paris Game".
    public var note = ""
    public var cup: CupRound?
    public var venue = ""

    public init() {}

    init(_ e: JSON) {
        let comp = e["competitions"][0]
        let status = e["status"].exists ? e["status"] : comp["status"]
        let type = status["type"]
        for c in comp["competitors"].array {
            if c["homeAway"].text == "home" { home = Side(c) } else { away = Side(c) }
        }
        id = e["id"].text
        date = Game.parseDate(e["date"].text) ?? .distantPast
        timeValid = comp["timeValid"].bool != false
        state = State(rawValue: type["state"].text) ?? .pre
        statusName = type["name"].text
        detail = type["shortDetail"].text
        seasonType = e["season"]["type"].int ?? 0
        // The national broadcast when there is one, else the first local one.
        network = comp["broadcast"].text
        if network.isEmpty { network = comp["broadcasts"][0]["names"][0].text }
        odds = comp["odds"][0]["details"].text
        if let total = comp["odds"][0]["overUnder"].double { overUnder = "O/U \(Game.trim(total))" }
        // The state of a playoff series wins over the generic note. NBA Cup games are told by their note.
        let headline = comp["notes"][0]["headline"].text
        cup = CupRound(headline: headline)
        if let series = comp["series"]["summary"].string { note = series }
        else if cup == nil { note = headline }
        venue = comp["venue"]["fullName"].text
    }

    public var status: Status {
        guard state == .pre else { return .text(detail) }
        if statusName != "STATUS_SCHEDULED" { return .text(detail) }
        return timeValid ? .tipoff(date) : .text("TBD")
    }

    /// True once the game is over, for the side that lost.
    public func lost(_ side: Side) -> Bool {
        guard state == .post, let a = away.score, let h = home.score, a != h else { return false }
        return (side == away ? a : h) < max(a, h)
    }

    /// Box scores exist once a game has tipped off.
    public var hasBoxScore: Bool { state != .pre }

    /// NBA.com's recap video of a finished game. Its address names the winner first,
    /// nicknames in lower case with dashes: game-recap-grizzlies-124-trail-blazers-103.
    public var recapURL: URL? {
        guard state == .post, let a = away.score, let h = home.score,
              !away.team.nick.isEmpty, !home.team.nick.isEmpty else { return nil }
        let (winner, loser) = h > a ? (home, away) : (away, home)
        func slug(_ side: Side) -> String {
            side.team.nick.lowercased()
                .replacing(/[^a-z0-9]+/, with: "-")
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return URL(string: "https://www.nba.com/watch/video/game-recap-\(slug(winner))-\(winner.score ?? 0)-\(slug(loser))-\(loser.score ?? 0)")
    }

    /// ESPN dates come with or without seconds: "2026-11-14T00:00Z".
    static func parseDate(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        return try? Date(text.replacingOccurrences(of: "Z", with: ":00Z"), strategy: .iso8601)
    }

    static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// One answer of ESPN's scoreboard: the games of a day, and with no day asked, what "today" is.
public struct Scoreboard: Sendable {
    /// The day ESPN reports for now; empty when a given day was asked.
    public var day = ""
    /// The current season, by the year it ends.
    public var seasonYear = 0
    public var seasonType = 0
    /// The game days of the season, sorted.
    public var days: [String] = []
    public var games: [Game] = []

    public init(_ json: JSON) {
        day = GameDay.key(fromISO: json["day"]["date"].text)
        seasonYear = json["season"]["year"].int ?? 0
        seasonType = json["season"]["type"].int ?? 0
        days = json["leagues"][0]["calendar"].array
            .map { GameDay.key(fromISO: $0.string ?? $0["startDate"].string ?? $0["value"].text) }
            .filter(GameDay.isKey)
        games = json["events"].array.map { Game($0) }.sorted { $0.date < $1.date }
    }
}

public extension [Game] {
    var liveCount: Int { count { $0.state == .live } }

    /// A finished day never changes, so its cached copy is final.
    var allFinal: Bool { !isEmpty && allSatisfy { $0.state == .post } }

    /// "Regular season · 5 games"
    var subtitle: String {
        guard let first else { return "" }
        let games = count == 1 ? "1 game" : "\(count) games"
        let phase = Season.phase(first.seasonType)
        return phase.isEmpty ? games : "\(phase) · \(games)"
    }
}
