import Foundation

public struct PlayerLine: Identifiable, Hashable, Sendable {
    /// ESPN's athlete id.
    public var athlete = ""
    public var name = ""
    public var pos = ""
    /// Why he did not play, when he did not.
    public var reason = ""
    /// By ESPN label: MIN, PTS, REB…
    public var stats: [String: String] = [:]
    /// The team's top scorer.
    public var top = false

    public var id: String { athlete.isEmpty ? name : athlete }
    public var points: Int { Int(stats["PTS"] ?? "") ?? 0 }
}

public struct TeamBox: Hashable, Sendable {
    public var side = Side()
    public var starters: [PlayerLine] = []
    public var bench: [PlayerLine] = []
    public var dnp: [PlayerLine] = []
    public var totals: [String: String] = [:]
    /// "FG 44% · 3PT 20% · FT 75% · Paint 66 · Fast break 26 · Largest lead 2"
    public var summary = ""

    public var hasPlayers: Bool { !starters.isEmpty || !bench.isEmpty }
}

/// The home team's chance to win after a play, and where the game stood then.
public struct WinPoint: Sendable, Equatable {
    /// 0 to 1.
    public var home: Double
    public var period: Int
    public var clock: String
    public var awayScore: Int
    public var homeScore: Int

    /// `Q3 7:42`, `OT 0:12`, `2OT 4:00`.
    public var when: String {
        let name = period <= 4 ? "Q\(period)" : period == 5 ? "OT" : "\(period - 4)OT"
        return "\(name) \(clock)"
    }
}

public struct BoxScore: Identifiable, Sendable {
    /// The player columns, as ESPN labels them.
    public static let columns = ["MIN", "PTS", "REB", "AST", "STL", "BLK", "TO", "FG", "3PT", "FT", "+/-"]

    public var id = ""
    public var state = Game.State.pre
    public var detail = ""
    public var venue = ""
    /// "1"…"4", then "OT", "OT2"…
    public var periods: [String] = []
    /// Away first.
    public var teams: [TeamBox] = []
    /// The home team's chance to win after each play.
    public var winProbability: [WinPoint] = []
    /// Where each period after the first starts in `winProbability`.
    public var periodStarts: [Int] = []

    public init(_ json: JSON) {
        let comp = json["header"]["competitions"][0]
        let type = comp["status"]["type"]
        id = json["header"]["id"].text
        state = Game.State(rawValue: type["state"].text) ?? .pre
        detail = type["detail"].string ?? type["shortDetail"].text
        venue = json["gameInfo"]["venue"]["fullName"].text

        var away: Side?, home: Side?
        for c in comp["competitors"].array {
            if c["homeAway"].text == "home" { home = Side(c) } else { away = Side(c) }
        }
        let sides = [away, home].compactMap { $0 }
        let count = max(sides.map(\.lines.count).max() ?? 0, 4)
        periods = (0..<count).map { $0 < 4 ? "\($0 + 1)" : $0 == 4 ? "OT" : "OT\($0 - 3)" }

        let box = json["boxscore"]
        teams = sides.map { side in
            var team = TeamBox()
            team.side = side
            let block = box["players"].array.first { $0["team"]["id"].text == side.team.id }?["statistics"][0] ?? JSON(nil)
            let labels = (block["labels"].exists ? block["labels"] : block["names"]).array.map(\.text)
            func map(_ values: JSON) -> [String: String] {
                var stats: [String: String] = [:]
                for (label, value) in zip(labels, values.array) { stats[label] = value.text }
                return stats
            }
            var top = 0
            for a in block["athletes"].array {
                var line = PlayerLine()
                line.athlete = a["athlete"]["id"].text
                line.name = a["athlete"]["shortName"].string ?? a["athlete"]["displayName"].text
                line.pos = a["athlete"]["position"]["abbreviation"].text
                line.stats = map(a["stats"])
                if a["didNotPlay"].bool == true || a["stats"].array.isEmpty {
                    line.reason = BoxScore.sentence(a["reason"].text)
                    team.dnp.append(line)
                } else {
                    top = max(top, line.points)
                    if a["starter"].bool == true { team.starters.append(line) } else { team.bench.append(line) }
                }
            }
            if top > 0 {
                for i in team.starters.indices { team.starters[i].top = team.starters[i].points == top }
                for i in team.bench.indices { team.bench[i].top = team.bench[i].points == top }
            }
            team.totals = map(block["totals"])

            let stats = box["teams"].array.first { $0["team"]["id"].text == side.team.id }?["statistics"].array ?? []
            func stat(_ label: String) -> String? {
                let value = stats.first { $0["label"].text == label || $0["name"].text == label }?["displayValue"].text
                return value.flatMap { $0.isEmpty ? nil : $0 }
            }
            var bits: [String] = []
            if let fg = stat("Field Goal %") { bits.append("FG \(fg)%") }
            if let three = stat("Three Point %") { bits.append("3PT \(three)%") }
            if let ft = stat("Free Throw %") { bits.append("FT \(ft)%") }
            if let paint = stat("Points in Paint") { bits.append("Paint \(paint)") }
            if let fast = stat("Fast Break Points") { bits.append("Fast break \(fast)") }
            if let lead = stat("Largest Lead") { bits.append("Largest lead \(lead)") }
            team.summary = bits.joined(separator: " · ")
            return team
        }
        (winProbability, periodStarts) = BoxScore.winProbability(json)
    }

    /// ESPN's win probability, play after play; the plays say where each period starts.
    static func winProbability(_ json: JSON) -> (points: [WinPoint], periodStarts: [Int]) {
        var plays: [String: JSON] = [:]
        for play in json["plays"].array { plays[play["id"].text] = play }
        var points: [WinPoint] = [], starts: [Int] = []
        var last = WinPoint(home: 0.5, period: 1, clock: "12:00", awayScore: 0, homeScore: 0)
        for (index, item) in json["winprobability"].array.enumerated() {
            var point = last
            point.home = item["homeWinPercentage"].double ?? last.home
            if let play = plays[item["playId"].text] {
                point.period = play["period"]["number"].int ?? last.period
                point.clock = play["clock"]["displayValue"].text
                point.awayScore = play["awayScore"].int ?? last.awayScore
                point.homeScore = play["homeScore"].int ?? last.homeScore
            }
            if point.period > last.period { starts.append(index) }
            points.append(point)
            last = point
        }
        return (points, starts)
    }

    /// NBA.com's recap video, once the game is over.
    public var recapURL: URL? {
        guard state == .post, teams.count == 2 else { return nil }
        return Game.recapURL(away: teams[0].side, home: teams[1].side)
    }

    /// "COACH'S DECISION" -> "Coach's decision"
    static func sentence(_ text: String) -> String {
        guard let first = text.first else { return "" }
        return first.uppercased() + text.dropFirst().lowercased()
    }
}
