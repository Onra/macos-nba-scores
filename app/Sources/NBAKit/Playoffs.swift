import Foundation

/// A team in a bracket game: empty id and "TBD" for a place not filled yet.
public struct BracketTeam: Codable, Hashable, Sendable {
    public var id = ""
    public var abbr = "TBD"
    public var logo: URL?
    public var score = ""
    public var winner = false

    public init() {}

    init(_ c: JSON) {
        let t = c["team"]
        guard let abbr = t["abbreviation"].string, abbr != "TBD" else { return }
        id = t["id"].text
        self.abbr = abbr
        logo = URL(string: t["logo"].string ?? t["logos"][0]["href"].text)
        score = c["score"].text
        winner = c["winner"].bool == true
    }
}

/// One play-in or playoff game.
public struct PlayoffGame: Codable, Hashable, Sendable, Identifiable {
    public enum Stage: String, Codable, Sendable {
        case playIn78 = "pi78", playIn910 = "pi910", playIn8 = "pi8"
        case round1 = "r1", round2 = "r2", conferenceFinals = "cf", finals

        var playIn: Bool { self == .playIn78 || self == .playIn910 || self == .playIn8 }
    }

    public var id = ""
    public var day = ""
    public var date = ""
    /// "East", "West", or "" for the Finals.
    public var conf = ""
    public var stage = Stage.round1
    /// The game's number in its series; 0 when the note does not say.
    public var number = 0
    public var state = Game.State.pre
    public var detail = ""
    public var away = BracketTeam()
    public var home = BracketTeam()
    public var seriesCompleted = false
    /// ESPN's own count of the series, by team id.
    public var seriesWins: [String: Int] = [:]

    public var tipoff: Date? { Game.parseDate(date) }
}

public struct SeriesSide: Codable, Hashable, Sendable {
    public var id = ""
    public var abbr = "TBD"
    public var logo: URL?
    public var seed = 0
    public var wins = 0
    public var winner = false
    /// A place the standings give for now, not settled yet.
    public var projected = false
}

/// One series of the bracket, the higher seed on top.
public struct SeriesCard: Codable, Hashable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable {
        case pre, live, between, post
    }

    public var top = SeriesSide()
    public var bottom = SeriesSide()
    public var state = State.pre
    /// "East semifinals", "NBA Finals"; empty for a series still to come.
    public var label = ""
    public var games: [PlayoffGame] = []

    public var id: String { "\(label):\(top.id):\(bottom.id)" }
}

public struct PlayInSlot: Codable, Hashable, Sendable, Identifiable {
    public var label = ""
    public var game: PlayoffGame?

    public var id: String { label }
}

public struct ConferenceBracket: Codable, Hashable, Sendable {
    /// Top to bottom: 1-8, 4-5, 3-6, 2-7.
    public var round1: [SeriesCard] = []
    public var round2: [SeriesCard] = []
    public var finals = SeriesCard()
    public var playIn: [PlayInSlot] = []

    public var hasPlayIn: Bool { playIn.contains { $0.game != nil } }
}

/// The playoffs of a season: play-in, bracket of series, champion.
public struct PlayoffBracket: Codable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case upcoming = "no games yet"
        case projected = "projected from the standings"
        case playIn = "play-in"
        case playoffs = "in progress"
        case done = "final"
    }

    /// The first season ESPN labels playoff rounds for, by the year it ends.
    public static let firstSeason = 2008

    public var season = ""
    public var phase = Phase.upcoming
    public var east = ConferenceBracket()
    public var west = ConferenceBracket()
    public var finals = SeriesCard()
    public var champion: SeriesSide?
    public var projected = false
}

/// A team of the regular-season standings, as the bracket needs it.
public struct SeededTeam: Codable, Hashable, Sendable {
    public var id = ""
    public var abbr = ""
    public var nick = ""
    public var logo: URL?
    public var conf = ""
    public var seed = 0
    public var played = 0

    public static func parse(standings json: JSON) -> [String: SeededTeam] {
        var teams: [String: SeededTeam] = [:]
        for child in json["children"].array {
            let conf = child["name"].text.contains("East") ? "East" : "West"
            for entry in child["standings"]["entries"].array {
                func value(_ name: String) -> Int {
                    Int(entry["stats"].array.first { $0["name"].text == name }?["value"].double ?? 0)
                }
                let t = entry["team"]
                teams[t["id"].text] = SeededTeam(
                    id: t["id"].text, abbr: t["abbreviation"].text, nick: t["name"].text,
                    logo: URL(string: t["logos"][0]["href"].text), conf: conf,
                    seed: value("playoffSeed"), played: value("wins") + value("losses"))
            }
        }
        return teams
    }
}

public enum Playoffs {
    /// The seed pairs of the first round, top to bottom of a conference's half of the tree.
    static let slots = [(1, 8), (4, 5), (3, 6), (2, 7)]

    /// The conference and the stage of a game, from its note; nil for other games.
    /// ESPN's wording changed over the years: "East 1st Round - Game 2" today,
    /// "EASTERN CONFERENCE 1ST ROUND - GAME 2" or "… FIRST ROUND …" before.
    public static func classify(_ note: String) -> (conf: String, stage: PlayoffGame.Stage)? {
        let n = note.lowercased()
        if n.contains("play-in") {
            let conf = n.contains(" east") ? "East" : "West"
            if n.contains("7th place") { return (conf, .playIn78) }
            if n.contains("9th place") { return (conf, .playIn910) }
            return (conf, .playIn8)
        }
        if n.hasPrefix("nba finals") { return ("", .finals) }
        for conf in ["East", "West"] where n.hasPrefix(conf.lowercased()) {
            if n.contains("1st round") || n.contains("first round") { return (conf, .round1) }
            if n.contains("semifinals") { return (conf, .round2) }
            if n.contains("finals") { return (conf, .conferenceFinals) }
        }
        return nil
    }

    /// The play-in and playoff games of a day's scoreboard.
    public static func games(day: String, scoreboard: JSON) -> [PlayoffGame] {
        scoreboard["events"].array.compactMap { event in
            guard [3, 5].contains(event["season"]["type"].int ?? 0) else { return nil }
            let comp = event["competitions"][0]
            let note = comp["notes"][0]["headline"].text
            guard let (conf, stage) = classify(note) else { return nil }
            let type = (event["status"].exists ? event["status"] : comp["status"])["type"]
            var game = PlayoffGame(id: event["id"].text, day: day, date: event["date"].text, conf: conf, stage: stage)
            for c in comp["competitors"].array {
                if c["homeAway"].text == "home" { game.home = BracketTeam(c) } else { game.away = BracketTeam(c) }
            }
            game.state = Game.State(rawValue: type["state"].text) ?? .pre
            // A postponed game is over with no winner (2020: the players' strike).
            if game.state == .post, !game.away.winner, !game.home.winner { return nil }
            game.detail = type["shortDetail"].text
            game.number = note.firstMatch(of: /(?i)game (\d+)/).flatMap { Int($0.1) } ?? 0
            game.seriesCompleted = comp["series"]["completed"].bool == true
            for c in comp["series"]["competitors"].array { game.seriesWins[c["id"].text] = c["wins"].int ?? 0 }
            return game
        }
    }

    /// The days the playoffs may be played on: early April to the end of June.
    public static func window(season: Int) -> [String] {
        // 2020: the season resumed in the Orlando bubble, playoffs from August.
        season == 2020 ? GameDay.range(from: "20200801", to: "20201015")
            : GameDay.range(from: "\(season)0405", to: "\(season)0630")
    }

    private struct Series {
        var stage: PlayoffGame.Stage
        var conf: String
        var ids: Set<String>
        var games: [PlayoffGame] = []
        var wins: [String: Int] = [:]
        var done = false
        var live = false
        var started = false
    }

    private static func series(_ games: [PlayoffGame]) -> [Series] {
        var all: [Series] = []
        for game in games.sorted(by: { $0.date < $1.date }) where !game.stage.playIn {
            let ids = Set([game.away.id, game.home.id].filter { !$0.isEmpty })
            if let index = all.firstIndex(where: { $0.stage == game.stage && $0.conf == game.conf && $0.ids == ids }) {
                all[index].games.append(game)
            } else {
                all.append(Series(stage: game.stage, conf: game.conf, ids: ids, games: [game]))
            }
        }
        for i in all.indices {
            var wins: [String: Int] = [:]
            for game in all[i].games where game.state == .post {
                wins[(game.away.winner ? game.away : game.home).id, default: 0] += 1
            }
            // ESPN's own count when it has one (it knows games we may not have).
            let last = all[i].games[all[i].games.count - 1]
            for (id, count) in last.seriesWins { wins[id] = max(wins[id] ?? 0, count) }
            all[i].wins = wins
            all[i].done = last.seriesCompleted || wins.values.contains { $0 >= 4 }
            all[i].live = all[i].games.contains { $0.state == .live }
            all[i].started = all[i].games.contains { $0.state != .pre }
        }
        return all
    }

    /// The bracket follows the NBA's: in each conference 1-8 and 4-5 meet in the second round, so do 3-6 and 2-7;
    /// the conference champions meet in the Finals. `teams`: the regular-season standings of that season, by team id.
    public static func build(season: Int, games: [PlayoffGame], teams: [String: SeededTeam]) -> PlayoffBracket {
        let played = teams.values.contains { $0.played > 0 }

        // Seeds 1-6 from the standings once the regular season is over (the play-in is then on the schedule);
        // 7 and 8 from the play-in when it is played. Before that, every place is a projection.
        var seedOf: [String: Int] = [:]
        if !games.isEmpty {
            for (id, team) in teams where (1...6).contains(team.seed) { seedOf[id] = team.seed }
        }
        for game in games where game.state == .post {
            let winner = game.away.winner ? game.away : game.home
            if game.stage == .playIn78 { seedOf[winner.id] = 7 }
            if game.stage == .playIn8 { seedOf[winner.id] = 8 }
        }
        // The playoff games themselves settle it too: a team in a first-round series against the 1 seed is the 8 seed.
        let all = series(games)
        for s in all where s.stage == .round1 && s.ids.count == 2 {
            let pair = Array(s.ids)
            for (x, y) in [(pair[0], pair[1]), (pair[1], pair[0])] {
                if seedOf[x] == nil, let other = seedOf[y], other > 0 { seedOf[x] = 9 - other }
            }
        }

        func side(_ id: String, seed: Int, wins: Int = 0, winner: Bool = false, projected: Bool = false) -> SeriesSide {
            let team = teams[id]
            return SeriesSide(id: team?.id ?? "", abbr: team.map { $0.abbr.isEmpty ? "TBD" : $0.abbr } ?? "TBD",
                              logo: team?.logo, seed: seed, wins: wins, winner: winner, projected: projected)
        }
        func card(_ s: Series?, seeds: [String: Int], label: String) -> SeriesCard? {
            guard let s else { return nil }
            let best = s.wins.values.max() ?? 0
            var sides = s.ids.sorted { (seeds[$0] ?? 99, $0) < (seeds[$1] ?? 99, $1) }.map { id in
                let wins = s.wins[id] ?? 0
                return side(id, seed: seeds[id] ?? 0, wins: wins, winner: s.done && wins == best)
            }
            while sides.count < 2 { sides.append(SeriesSide()) }
            let state: SeriesCard.State = s.done ? .post : s.live ? .live : s.started ? .between : .pre
            return SeriesCard(top: sides[0], bottom: sides[1], state: state, label: label, games: s.games)
        }

        var bracket = PlayoffBracket(season: Season.label(season))
        for conf in ["East", "West"] {
            let conference = teams.filter { $0.value.conf == conf }
            var bySeed: [Int: String] = [:], projection: [Int: String] = [:]
            for (id, team) in conference {
                if let seed = seedOf[id] { bySeed[seed] = id }
                if team.seed > 0 { projection[team.seed] = id }
            }
            var half = ConferenceBracket()
            for (a, b) in slots {
                let found = all.first { s in
                    s.stage == .round1 && s.conf == conf && s.ids.contains { [a, b].contains(seedOf[$0] ?? 0) }
                }
                if let card = card(found, seeds: seedOf, label: "\(conf) 1st round") {
                    half.round1.append(card)
                    continue
                }
                let sides = [a, b].map { seed -> SeriesSide in
                    if let id = bySeed[seed] { return side(id, seed: seed) }
                    if played, let id = projection[seed] {
                        bracket.projected = true
                        return side(id, seed: seed, projected: true)
                    }
                    return SeriesSide(seed: seed)
                }
                half.round1.append(SeriesCard(top: sides[0], bottom: sides[1]))
            }
            for seeds in [[1, 8, 4, 5], [3, 6, 2, 7]] {
                let found = all.first { s in
                    s.stage == .round2 && s.conf == conf && s.ids.contains { seeds.contains(seedOf[$0] ?? 0) }
                }
                half.round2.append(card(found, seeds: seedOf, label: "\(conf) semifinals") ?? SeriesCard())
            }
            half.finals = card(all.first { $0.stage == .conferenceFinals && $0.conf == conf }, seeds: seedOf,
                               label: "\(conf) finals") ?? SeriesCard()
            let stages: [(PlayoffGame.Stage, String)] = [(.playIn78, "7 v 8"), (.playIn910, "9 v 10"), (.playIn8, "8th seed")]
            half.playIn = stages.map { stage, label in
                PlayInSlot(label: label, game: games.first { $0.conf == conf && $0.stage == stage })
            }
            if conf == "East" { bracket.east = half } else { bracket.west = half }
        }

        if var finals = card(all.first { $0.stage == .finals }, seeds: [:], label: "NBA Finals") {
            // No seeds across conferences: West on top, as on the tree (West on the left).
            if teams[finals.top.id]?.conf == "East" { swap(&finals.top, &finals.bottom) }
            finals.top.seed = seedOf[finals.top.id] ?? 0
            finals.bottom.seed = seedOf[finals.bottom.id] ?? 0
            bracket.finals = finals
        }
        if bracket.finals.state == .post {
            bracket.champion = [bracket.finals.top, bracket.finals.bottom].first(where: \.winner)
        }
        bracket.phase = bracket.champion != nil ? .done
            : all.contains(where: \.started) ? .playoffs
            : games.contains { $0.state != .pre } ? .playIn
            : played ? .projected : .upcoming
        return bracket
    }
}

public extension GameDay {
    /// Every day from one key to another, both included.
    static func range(from: String, to: String) -> [String] {
        guard var day = date(from), let end = date(to) else { return [] }
        var days: [String] = []
        while day <= end {
            days.append(keyFormatter.string(from: day))
            day = day.addingTimeInterval(86400)
        }
        return days
    }

    /// The number of days from one key to another.
    static func days(from: String, to: String) -> Int {
        guard let a = date(from), let b = date(to) else { return 0 }
        return Int((b.timeIntervalSince(a) / 86400).rounded())
    }

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
