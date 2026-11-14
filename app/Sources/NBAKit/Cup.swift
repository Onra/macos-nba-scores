import Foundation

/// A team in an NBA Cup game. Empty nickname and "TBD" for a knockout place not filled yet.
public struct CupSide: Codable, Hashable, Sendable {
    public var nick = ""
    public var abbr = "TBD"
    public var name = "TBD"
    public var teamID = ""
    public var logo: URL?
    public var score = ""
    public var winner = false
    /// The score after four quarters, when the game went to overtime: Cup tiebreakers ignore overtime.
    public var regulation: Int?
    /// Knockout seed in its conference; 0 when unknown.
    public var seed = 0
    /// A place the group tables give for now, not settled yet.
    public var projected = false

    public init() {}

    init(_ c: JSON) {
        let t = c["team"]
        guard let abbr = t["abbreviation"].string, abbr != "TBD" else { return }
        self.abbr = abbr
        nick = t["name"].string ?? t["shortDisplayName"].text
        name = t["shortDisplayName"].string ?? t["displayName"].string ?? "TBD"
        teamID = t["id"].text
        logo = URL(string: t["logo"].string ?? t["logos"][0]["href"].text)
        score = c["score"].text
        winner = c["winner"].bool == true
        let lines = c["linescores"].array.map { Int($0["value"].double ?? 0) }
        if lines.count > 4 { regulation = lines.prefix(4).reduce(0, +) }
    }

    /// Points that count for the tiebreakers.
    var points: Int { regulation ?? Int(score) ?? 0 }
}

public struct CupGame: Codable, Hashable, Sendable, Identifiable {
    public var id = ""
    public var day = ""
    public var date = ""
    public var round = CupRound.group
    public var state = Game.State.pre
    public var detail = ""
    public var away = CupSide()
    public var home = CupSide()
}

extension CupRound: Codable {}

/// One line of a group table.
public struct CupRow: Codable, Hashable, Sendable, Identifiable {
    public var nick = ""
    public var name = ""
    public var abbr = ""
    public var teamID = ""
    public var logo: URL?
    public var wins = 0
    public var losses = 0
    public var pointsFor = 0
    public var pointsAgainst = 0
    public var played = 0
    public var rank = 0
    public var gamesBehind = "-"
    public var diff = "0"
    /// NBA.com's mark once a place is settled: "x" group winner, "wc" wildcard, "o" eliminated.
    public var clinch = ""
    /// Holds the conference's wildcard as the tables stand.
    public var wildcard = false

    public var id: String { nick }
    public var record: String { "\(wins)-\(losses)" }

    /// What the table says beside the team: a place in the knockout rounds, settled or held for now.
    public var tag: String {
        switch clinch {
        case "x": "group"
        case "wc": "wildcard"
        default: wildcard ? "wildcard?" : ""
        }
    }

    public var eliminated: Bool { clinch == "o" }
}

public struct CupGroup: Codable, Hashable, Sendable, Identifiable {
    /// "East Group A", or "East Group" when NBA.com's names are not known.
    public var name = ""
    public var conf = ""
    public var teams: [CupRow] = []

    public var id: String { name + (teams.first?.nick ?? "") }
    /// False before the group's first game: the order then means nothing.
    public var started: Bool { teams.contains { $0.played > 0 } }
}

/// One knockout game on the tree.
public struct CupCard: Codable, Hashable, Sendable {
    public var id = ""
    public var day = ""
    public var date = ""
    public var state = Game.State.pre
    public var detail = ""
    public var top = CupSide()
    public var bottom = CupSide()
}

public struct CupHalf: Codable, Hashable, Sendable {
    /// The first is the quarterfinal of the top seed, whose winner plays the top of the semifinal.
    public var quarterfinals: [CupCard] = []
    public var semifinal = CupCard()
}

public struct CupBracket: Codable, Hashable, Sendable {
    public var east = CupHalf()
    public var west = CupHalf()
    public var final = CupCard()
    public var champion: CupSide?
    /// Some places come from the group tables as they stand.
    public var projected = false
    /// The quarterfinals are set.
    public var set = false
}

/// The NBA Cup of a season: group tables and knockout tree.
public struct CupData: Codable, Sendable {
    /// The first Cup (then the In-Season Tournament) was 2023-24.
    public static let firstSeason = 2024

    public var season = ""
    /// The order and the clinch marks are NBA.com's.
    public var official = false
    public var groups: [CupGroup] = []
    public var bracket = CupBracket()
    /// Team nickname -> group name.
    public var teamGroup: [String: String] = [:]
    public var done = false

    /// False until a Cup game is on the schedule.
    public var hasGames: Bool { !groups.isEmpty || bracket.set }
}

/// NBA.com's Cup standings, for what ESPN lacks: the group names and the official order with the clinch marks.
public struct CupOfficial: Codable, Hashable, Sendable {
    public struct Team: Codable, Hashable, Sendable {
        public var nick = ""
        public var group = ""
        public var rank = 0
        public var wins = 0
        public var losses = 0
        public var clinch = ""
    }

    public var teams: [Team] = []

    /// nil unless the answer covers the 30 teams.
    public init?(_ json: JSON) {
        let rows = json["teams"].array
        guard rows.count == 30 else { return nil }
        teams = rows.map { t in
            Team(nick: t["teamName"].text, group: t["istGroup"].text, rank: t["istGroupRank"].int ?? 0,
                 wins: t["wins"].int ?? 0, losses: t["losses"].int ?? 0,
                 clinch: t["clinchIndicator"].text.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces))
        }
    }
}

public enum Cup {
    /// The Cup games of a day's scoreboard.
    public static func games(day: String, scoreboard: JSON) -> [CupGame] {
        scoreboard["events"].array.compactMap { event in
            let comp = event["competitions"][0]
            guard let round = CupRound(headline: comp["notes"][0]["headline"].text) else { return nil }
            let type = (event["status"].exists ? event["status"] : comp["status"])["type"]
            var game = CupGame(id: event["id"].text, day: day, date: event["date"].text, round: round,
                               state: Game.State(rawValue: type["state"].text) ?? .pre, detail: type["shortDetail"].text)
            let sides = comp["competitors"].array
            guard sides.count == 2 else { return nil }
            for c in sides {
                if c["homeAway"].text == "home" { game.home = CupSide(c) } else { game.away = CupSide(c) }
            }
            return game
        }
    }

    /// The days the Cup may be played on: late October to mid-December of the year the season starts.
    public static func window(startYear: Int) -> [String] {
        GameDay.range(from: "\(startYear)1024", to: "\(startYear)1220")
    }

    /// The five-team groups, found from the schedule: each team plays the four others of its group.
    static func groups(fromSchedule games: [CupGame]) -> [[String]] {
        var parent: [String: String] = [:]
        func find(_ x: String) -> String {
            var x = x
            while let p = parent[x], p != x { x = p }
            return x
        }
        var order: [String] = []
        for game in games {
            for nick in [game.away.nick, game.home.nick] where parent[nick] == nil {
                parent[nick] = nick
                order.append(nick)
            }
            parent[find(game.away.nick)] = find(game.home.nick)
        }
        var components: [String: [String]] = [:]
        var roots: [String] = []
        for nick in order {
            let root = find(nick)
            if components[root] == nil { roots.append(root) }
            components[root, default: []].append(nick)
        }
        return roots.map { components[$0]! }
    }

    /// The Cup group tiebreakers: wins, then head-to-head among the tied teams, then point differential,
    /// then points scored.
    static func rank(_ rows: [CupRow], games: [CupGame]) -> [CupRow] {
        var ranked: [CupRow] = []
        let byWins = Dictionary(grouping: rows, by: \.wins)
        for wins in byWins.keys.sorted(by: >) {
            let tied = byWins[wins]!
            var headToHead: [String: Int] = [:]
            if tied.count > 1 {
                let names = Set(tied.map(\.nick))
                for game in games where game.state == .post && names.contains(game.away.nick) && names.contains(game.home.nick) {
                    headToHead[(game.away.winner ? game.away : game.home).nick, default: 0] += 1
                }
            }
            ranked += tied.sorted { a, b in
                let ka = (-(headToHead[a.nick] ?? 0), -(a.pointsFor - a.pointsAgainst), -a.pointsFor)
                let kb = (-(headToHead[b.nick] ?? 0), -(b.pointsFor - b.pointsAgainst), -b.pointsFor)
                return ka != kb ? ka < kb : a.name < b.name
            }
        }
        return ranked
    }

    /// `conferences`: team nickname -> "East" or "West".
    public static func build(startYear: Int, games: [CupGame], official: CupOfficial?, conferences: [String: String]) -> CupData {
        let groupGames = games.filter { $0.round == .group }
        var teams: [String: CupRow] = [:]
        var order: [String] = []
        for game in groupGames {
            for side in [game.away, game.home] where teams[side.nick] == nil {
                teams[side.nick] = CupRow(nick: side.nick, name: side.name, abbr: side.abbr, teamID: side.teamID, logo: side.logo)
                order.append(side.nick)
            }
            guard game.state == .post else { continue }
            // Point differential and points scored leave overtime out (Cup rules).
            let (a, h) = (game.away.points, game.home.points)
            teams[game.away.nick]!.pointsFor += a
            teams[game.away.nick]!.pointsAgainst += h
            teams[game.home.nick]!.pointsFor += h
            teams[game.home.nick]!.pointsAgainst += a
            teams[game.away.nick]!.played += 1
            teams[game.home.nick]!.played += 1
            let (winner, loser) = game.away.winner ? (game.away.nick, game.home.nick) : (game.home.nick, game.away.nick)
            teams[winner]!.wins += 1
            teams[loser]!.losses += 1
        }

        // Group membership: NBA.com's names when known, else the schedule.
        let off = Dictionary((official?.teams ?? []).map { ($0.nick, $0) }, uniquingKeysWith: { a, _ in a })
        var named: [(label: String, members: [String])] = []
        if !off.isEmpty, order.allSatisfy({ off[$0] != nil }) {
            for nick in order {
                let group = off[nick]!.group
                if let index = named.firstIndex(where: { $0.label == group }) { named[index].members.append(nick) }
                else { named.append((group, [nick])) }
            }
        } else {
            for members in groups(fromSchedule: groupGames) {
                let conf = conferences[members[0]] ?? ""
                named.append(("\(conf) Group".trimmingCharacters(in: .whitespaces), members))
            }
        }

        // The official order and clinch marks are only trusted while NBA.com agrees with ESPN's results.
        let officialFresh = !off.isEmpty && teams.allSatisfy { nick, team in
            off[nick].map { $0.wins == team.wins && $0.losses == team.losses } ?? false
        }

        var data = CupData(season: Season.label(startYear + 1), official: officialFresh)
        for (label, members) in named {
            var rows = members.map { teams[$0]! }
            rows = officialFresh
                ? rows.sorted { (off[$0.nick]!.rank > 0 ? off[$0.nick]!.rank : 9) < (off[$1.nick]!.rank > 0 ? off[$1.nick]!.rank : 9) }
                : rank(rows, games: groupGames)
            let lead = rows[0]
            for i in rows.indices {
                rows[i].rank = i + 1
                let behind = Double((lead.wins - rows[i].wins) + (rows[i].losses - lead.losses)) / 2
                rows[i].gamesBehind = behind == 0 ? "-" : Game.trim(behind)
                let diff = rows[i].pointsFor - rows[i].pointsAgainst
                rows[i].diff = rows[i].played > 0 ? (diff >= 0 ? "+\(diff)" : "\(diff)") : "0"
                rows[i].clinch = officialFresh ? off[rows[i].nick]!.clinch : ""
            }
            let conf = label.hasPrefix("East") || conferences[lead.nick] == "East" ? "East" : "West"
            data.groups.append(CupGroup(name: label, conf: conf, teams: rows))
        }
        data.groups.sort { ($0.conf, $0.name, $0.teams[0].nick) < ($1.conf, $1.name, $1.teams[0].nick) }

        // The wildcard race: the best second-placed team of each conference.
        for conf in ["East", "West"] {
            let seconds = rank(data.groups.filter { $0.conf == conf && $0.teams.count > 1 }.map { $0.teams[1] }, games: [])
            guard let best = seconds.first, best.played > 0 else { continue }
            for g in data.groups.indices where data.groups[g].conf == conf {
                for t in data.groups[g].teams.indices where data.groups[g].teams[t].nick == best.nick {
                    data.groups[g].teams[t].wildcard = true
                }
            }
        }

        var knockout: [CupRound: [CupGame]] = [:]
        for round in [CupRound.quarterfinal, .semifinal, .final] {
            knockout[round] = games.filter { $0.round == round }.sorted { $0.date < $1.date }
        }
        data.bracket = bracket(groups: data.groups, knockout: knockout, conferences: conferences)
        for group in data.groups {
            for team in group.teams { data.teamGroup[team.nick] = group.name }
        }
        let final = knockout[.final] ?? []
        data.done = !final.isEmpty && final.allSatisfy { $0.state == .post }
        return data
    }

    /// The knockout seeds of a conference as the groups stand: the three group winners seeded 1-3
    /// (record, then point differential, then points), the wildcard 4th. Empty until a group game has been played.
    static func seeds(_ groups: [CupGroup], conf: String) -> [CupRow] {
        let groups = groups.filter { $0.conf == conf }
        guard groups.contains(where: \.started) else { return [] }
        let winners = rank(groups.compactMap(\.teams.first), games: [])
        return winners + groups.flatMap(\.teams).filter(\.wildcard).prefix(1)
    }

    /// The knockout tree. A place ESPN has not filled yet ("TBD") shows the team projected from the group tables.
    static func bracket(groups: [CupGroup], knockout: [CupRound: [CupGame]], conferences: [String: String]) -> CupBracket {
        var seedOf: [String: Int] = [:]
        var projection: [String: [CupRow]] = [:]
        for conf in ["East", "West"] {
            projection[conf] = seeds(groups, conf: conf)
            for (i, team) in projection[conf]!.enumerated() { seedOf[team.nick] = i + 1 }
        }

        func split(_ games: [CupGame], perSide: Int) -> [String: [CupGame]] {
            var sides: [String: [CupGame]] = ["East": [], "West": []]
            var rest: [CupGame] = []
            for game in games {
                if let conf = conferences[game.away.nick] ?? conferences[game.home.nick], sides[conf]!.count < perSide {
                    sides[conf]!.append(game)
                } else {
                    rest.append(game)
                }
            }
            // Unknown teams: the East plays first (as in every Cup so far).
            for game in rest { sides[sides["East"]!.count < perSide ? "East" : "West"]!.append(game) }
            return sides
        }
        func known(_ side: CupSide) -> CupSide {
            var side = side
            side.seed = seedOf[side.nick] ?? 0
            return side
        }
        func card(_ game: CupGame?, _ top: CupSide, _ bottom: CupSide) -> CupCard {
            CupCard(id: game?.id ?? "", day: game?.day ?? "", date: game?.date ?? "", state: game?.state ?? .pre,
                    detail: game?.detail ?? "", top: top, bottom: bottom)
        }

        let quarterfinals = split(knockout[.quarterfinal] ?? [], perSide: 2)
        let semifinals = split(knockout[.semifinal] ?? [], perSide: 1)
        var bracket = CupBracket()
        for conf in ["East", "West"] {
            let projected = projection[conf]!
            // The quarterfinal of the top seed first, when it is known.
            let games = quarterfinals[conf]!.sorted {
                min(seedOf[$0.away.nick] ?? 9, seedOf[$0.home.nick] ?? 9) < min(seedOf[$1.away.nick] ?? 9, seedOf[$1.home.nick] ?? 9)
            }
            var half = CupHalf()
            // Seed 1 v 4, then seed 2 v 3: the lower seed is the visitor, on top.
            for (i, pair) in [(top: 3, bottom: 0), (top: 2, bottom: 1)].enumerated() {
                let game = i < games.count ? games[i] : nil
                let sides = [(game?.away, pair.top), (game?.home, pair.bottom)].map { side, slot -> CupSide in
                    if let side, !side.nick.isEmpty { return known(side) }
                    guard slot < projected.count else { return CupSide() }
                    bracket.projected = true
                    var team = CupSide()
                    team.nick = projected[slot].nick
                    team.abbr = projected[slot].abbr
                    team.name = projected[slot].name
                    team.teamID = projected[slot].teamID
                    team.logo = projected[slot].logo
                    team.seed = slot + 1
                    team.projected = true
                    return team
                }
                half.quarterfinals.append(card(game, sides[0], sides[1]))
            }
            let semi = semifinals[conf]!.first
            half.semifinal = card(semi, semi.map { known($0.away) } ?? CupSide(), semi.map { known($0.home) } ?? CupSide())
            if conf == "East" { bracket.east = half } else { bracket.west = half }
        }

        let final = knockout[.final]?.first
        var sides = [final?.away ?? CupSide(), final?.home ?? CupSide()]
        // West on top, as on the tree (West on the left).
        if conferences[sides[0].nick] == "East" { sides.reverse() }
        bracket.final = card(final, sides[0], sides[1])
        if final?.state == .post { bracket.champion = sides.first(where: \.winner) }
        bracket.set = (knockout[.quarterfinal] ?? []).contains { !$0.away.nick.isEmpty }
        return bracket
    }
}
