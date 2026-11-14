import Foundation
import Testing
@testable import NBAKit

// MARK: Playoffs

/// Ten teams a conference, ids "e1"… and "w1"…, seeded in that order.
func seeded(played: Int = 82) -> [String: SeededTeam] {
    var teams: [String: SeededTeam] = [:]
    for (prefix, conf) in [("e", "East"), ("w", "West")] {
        for seed in 1...10 {
            let id = "\(prefix)\(seed)"
            teams[id] = SeededTeam(id: id, abbr: id.uppercased(), nick: id, conf: conf, seed: seed, played: played)
        }
    }
    return teams
}

func playoffGame(_ id: String, _ conf: String, _ stage: PlayoffGame.Stage, _ away: String, _ home: String,
                 winner: String? = nil, state: Game.State = .post, date: String? = nil) -> PlayoffGame {
    var game = PlayoffGame(id: id, day: "20260420", date: date ?? "2026-04-20T00:00Z-\(id)", conf: conf, stage: stage, state: state)
    game.away.id = away
    game.away.abbr = away.uppercased()
    game.home.id = home
    game.home.abbr = home.uppercased()
    game.away.winner = winner == away
    game.home.winner = winner == home
    return game
}

/// A series won 4-1 by `winner`.
func sweepish(_ prefix: String, _ conf: String, _ stage: PlayoffGame.Stage, _ winner: String, _ loser: String) -> [PlayoffGame] {
    (1...5).map { playoffGame("\(prefix)\($0)", conf, stage, loser, winner, winner: $0 == 2 ? loser : winner) }
}

@Suite struct PlayoffsTests {
    @Test func classify() {
        #expect(Playoffs.classify("East 1st Round - Game 2")! == ("East", .round1))
        #expect(Playoffs.classify("EASTERN CONFERENCE FIRST ROUND - GAME 2")! == ("East", .round1))
        #expect(Playoffs.classify("West Semifinals - Game 5")! == ("West", .round2))
        #expect(Playoffs.classify("West Finals - Game 1")! == ("West", .conferenceFinals))
        #expect(Playoffs.classify("NBA Finals - Game 7")! == ("", .finals))
        #expect(Playoffs.classify("NBA Play-In - East - 7th Place vs 8th Place")! == ("East", .playIn78))
        #expect(Playoffs.classify("NBA Play-In - West - 9th Place vs 10th Place")! == ("West", .playIn910))
        #expect(Playoffs.classify("NBA Play-In - West - 8th Seed Game")! == ("West", .playIn8))
        #expect(Playoffs.classify("NBA Cup - Group Play") == nil)
        #expect(Playoffs.classify("") == nil)
    }

    @Test func window() {
        #expect(Playoffs.window(season: 2026).count == 87)
        #expect(Playoffs.window(season: 2026).first == "20260405")
        #expect(Playoffs.window(season: 2026).last == "20260630")
        // The Orlando bubble.
        #expect(Playoffs.window(season: 2020).first == "20200801")
    }

    @Test func gamesOfADay() throws {
        let board = try JSON(data: Data("""
        {"events": [
          {"id": "1", "date": "2026-04-19T19:30Z", "season": {"type": 3}, "status": {"type": {"state": "post", "shortDetail": "Final"}},
           "competitions": [{"notes": [{"headline": "West 1st Round - Game 2"}],
             "series": {"completed": false, "competitors": [{"id": "25", "wins": 2}, {"id": "21", "wins": 0}]},
             "competitors": [{"homeAway": "home", "winner": true, "score": "119", "team": {"id": "25", "abbreviation": "OKC", "logo": "https://x/okc.png"}},
                             {"homeAway": "away", "winner": false, "score": "84", "team": {"id": "21", "abbreviation": "PHX"}}]}]},
          {"id": "2", "date": "2026-04-19T22:00Z", "season": {"type": 2}, "competitions": [{"notes": [{"headline": "West 1st Round - Game 1"}]}]},
          {"id": "3", "date": "2026-04-19T22:00Z", "season": {"type": 3}, "status": {"type": {"state": "post"}},
           "competitions": [{"notes": [{"headline": "East 1st Round - Game 1"}],
             "competitors": [{"homeAway": "home", "team": {"id": "1", "abbreviation": "ATL"}}, {"homeAway": "away", "team": {"id": "2", "abbreviation": "BOS"}}]}]},
          {"id": "4", "date": "2026-06-01T00:00Z", "season": {"type": 3}, "status": {"type": {"state": "pre"}},
           "competitions": [{"notes": [{"headline": "NBA Finals - Game 1"}],
             "competitors": [{"homeAway": "home", "team": {"id": "25", "abbreviation": "OKC"}}, {"homeAway": "away", "team": {"abbreviation": "TBD"}}]}]}
        ]}
        """.utf8))
        let games = Playoffs.games(day: "20260419", scoreboard: board)
        // The regular-season game is not a playoff game, and a game over with no winner was postponed.
        #expect(games.map(\.id) == ["1", "4"])
        #expect(games[0].conf == "West")
        #expect(games[0].stage == .round1)
        #expect(games[0].number == 2)
        #expect(games[0].home.abbr == "OKC")
        #expect(games[0].home.winner)
        #expect(games[0].seriesWins == ["25": 2, "21": 0])
        #expect(games[1].stage == .finals)
        #expect(games[1].away.id == "")
        #expect(games[1].away.abbr == "TBD")
    }

    @Test func beforeTheSeason() {
        let bracket = Playoffs.build(season: 2027, games: [], teams: seeded(played: 0))
        #expect(bracket.season == "2026-27")
        #expect(bracket.phase == .upcoming)
        #expect(!bracket.projected)
        #expect(bracket.east.round1.map(\.top.seed) == [1, 4, 3, 2])
        #expect(bracket.east.round1.map(\.bottom.seed) == [8, 5, 6, 7])
        #expect(bracket.east.round1.allSatisfy { $0.top.abbr == "TBD" && $0.state == .pre })
        #expect(bracket.champion == nil)
    }

    @Test func projectedFromTheStandings() {
        let bracket = Playoffs.build(season: 2027, games: [], teams: seeded())
        #expect(bracket.phase == .projected)
        #expect(bracket.projected)
        #expect(bracket.west.round1.map(\.top.abbr) == ["W1", "W4", "W3", "W2"])
        #expect(bracket.west.round1.map(\.bottom.abbr) == ["W8", "W5", "W6", "W7"])
        #expect(bracket.west.round1.allSatisfy { $0.top.projected && $0.bottom.projected })
        #expect(bracket.west.round2.allSatisfy { $0.top.abbr == "TBD" })
        #expect(!bracket.east.hasPlayIn)
    }

    @Test func playIn() {
        let games = [
            playoffGame("a", "East", .playIn78, "e8", "e7", winner: "e7"),
            playoffGame("b", "East", .playIn910, "e10", "e9", state: .pre),
        ]
        let bracket = Playoffs.build(season: 2026, games: games, teams: seeded())
        #expect(bracket.phase == .playIn)
        // The top six are settled once the play-in is on the schedule; the winner of 7 v 8 is the 7th seed.
        let twoSeven = bracket.east.round1[3]
        #expect(twoSeven.top.abbr == "E2")
        #expect(!twoSeven.top.projected)
        #expect(twoSeven.bottom.abbr == "E7")
        #expect(!twoSeven.bottom.projected)
        // The 8th seed is still to be played for.
        #expect(bracket.east.round1[0].bottom.projected)
        #expect(bracket.east.playIn.map(\.label) == ["7 v 8", "9 v 10", "8th seed"])
        #expect(bracket.east.playIn.map { $0.game?.id } == ["a", "b", nil])
        #expect(bracket.east.hasPlayIn)
        #expect(!bracket.west.hasPlayIn)
    }

    @Test func seriesAndChampion() {
        var games = sweepish("r1e", "East", .round1, "e1", "e9")
            + sweepish("r2e", "East", .round2, "e1", "e4")
            + sweepish("cfe", "East", .conferenceFinals, "e1", "e2")
            + sweepish("cfw", "West", .conferenceFinals, "w3", "w1")
            + sweepish("f", "", .finals, "e1", "w3")
        games.append(playoffGame("r1w", "West", .round1, "w6", "w3", state: .live))
        let bracket = Playoffs.build(season: 2026, games: games, teams: seeded())

        let first = bracket.east.round1[0]
        #expect(first.top.abbr == "E1")
        #expect(first.top.wins == 4)
        #expect(first.top.winner)
        // Facing the 1 seed in the first round: the 8th seed, whatever the standings said.
        #expect(first.bottom.abbr == "E9")
        #expect(first.bottom.seed == 8)
        #expect(first.bottom.wins == 1)
        #expect(!first.bottom.winner)
        #expect(first.state == .post)
        #expect(first.label == "East 1st round")
        #expect(first.games.count == 5)

        #expect(bracket.east.round2[0].top.abbr == "E1")
        #expect(bracket.east.round2[1].top.abbr == "TBD")
        #expect(bracket.east.finals.bottom.abbr == "E2")
        #expect(bracket.west.round1[2].state == .live)
        #expect(bracket.west.round1[2].top.abbr == "W3")

        // West on top in the Finals, as on the tree.
        #expect(bracket.finals.top.abbr == "W3")
        #expect(bracket.finals.top.seed == 3)
        #expect(bracket.finals.bottom.abbr == "E1")
        #expect(bracket.finals.bottom.wins == 4)
        #expect(bracket.champion?.abbr == "E1")
        #expect(bracket.phase == .done)
    }

    @Test func espnsCountOfASeries() {
        var game = playoffGame("g1", "East", .round1, "e8", "e1", winner: "e1")
        game.seriesWins = ["e1": 3, "e8": 1]
        let series = Playoffs.build(season: 2026, games: [game], teams: seeded()).east.round1[0]
        // ESPN knows games we may not have.
        #expect(series.top.wins == 3)
        #expect(series.bottom.wins == 1)
        #expect(series.state == .between)
    }
}

// MARK: NBA Cup

func cupGame(_ id: String, _ away: String, _ awayScore: Int, _ home: String, _ homeScore: Int,
             round: CupRound = .group, state: Game.State = .post) -> CupGame {
    var game = CupGame(id: id, day: "20261113", date: "2026-11-13T00:00Z-\(id)", round: round, state: state)
    for (side, score, isHome) in [(away, awayScore, false), (home, homeScore, true)] {
        var team = CupSide()
        if !side.isEmpty {
            team.nick = side
            team.name = side
            team.abbr = side.uppercased()
            team.score = "\(score)"
            team.winner = state == .post && score == max(awayScore, homeScore)
        }
        if isHome { game.home = team } else { game.away = team }
    }
    return game
}

/// Two groups a conference, three teams each, everyone has played everyone.
/// East A: a1 2-0, a2 1-1, a3 0-2. East B: b1 2-0, b2 1-1 (better differential than a2), b3 0-2. Same in the West.
func cupGroups() -> (games: [CupGame], conferences: [String: String]) {
    var games: [CupGame] = [], conferences: [String: String] = [:]
    for (conf, prefix) in [("East", "e"), ("West", "w")] {
        for (group, margin) in [("a", 5), ("b", 10)] {
            let t = (1...3).map { "\(prefix)\(group)\($0)" }
            t.forEach { conferences[$0] = conf }
            games.append(cupGame("\(t[0])-\(t[1])", t[1], 100, t[0], 100 + margin))
            games.append(cupGame("\(t[0])-\(t[2])", t[2], 100, t[0], 100 + margin))
            games.append(cupGame("\(t[1])-\(t[2])", t[2], 100, t[1], 100 + 2 * margin))
        }
    }
    return (games, conferences)
}

@Suite struct CupTests {
    @Test func gamesOfADay() throws {
        let games = Cup.games(day: "20261113", scoreboard: try fixture("scoreboard-current"))
        #expect(games.count == 9)
        #expect(games.allSatisfy { $0.round == .group && $0.state == .post })
        let knicks = try #require(games.first { $0.id == "401909296" })
        #expect(knicks.away.nick == "Knicks")
        #expect(knicks.home.nick == "Pacers")
        #expect(knicks.home.winner)
        #expect(knicks.home.score == "106")
        #expect(knicks.home.regulation == nil)
        #expect(!knicks.home.teamID.isEmpty)
        // Overtime: the tiebreakers count the score after four quarters, 110-110.
        let overtime = try #require(games.first { $0.id == "401909299" })
        #expect(overtime.home.score == "125")
        #expect(overtime.home.points == 110)
        #expect(overtime.away.points == 110)
        // The day after has no Cup game.
        #expect(Cup.games(day: "20261114", scoreboard: try fixture("scoreboard-20261114")).isEmpty)
    }

    @Test func window() {
        let days = Cup.window(startYear: 2026)
        #expect(days.count == 58)
        #expect(days.first == "20261024")
        #expect(days.last == "20261220")
    }

    @Test func groupsFromTheSchedule() {
        let groups = Cup.groups(fromSchedule: cupGroups().games)
        #expect(groups.count == 4)
        #expect(groups.allSatisfy { $0.count == 3 })
        #expect(Set(groups[0]) == ["ea1", "ea2", "ea3"])
    }

    @Test func tiebreakers() {
        func row(_ nick: String, _ wins: Int, _ pf: Int, _ pa: Int) -> CupRow {
            CupRow(nick: nick, name: nick, wins: wins, pointsFor: pf, pointsAgainst: pa, played: 4)
        }
        // Wins first.
        #expect(Cup.rank([row("a", 2, 400, 300), row("b", 3, 300, 400)], games: []).map(\.nick) == ["b", "a"])
        // Then head-to-head among the tied teams, over the point differential.
        let headToHead = [cupGame("1", "a", 90, "b", 100)]
        #expect(Cup.rank([row("a", 3, 450, 300), row("b", 3, 400, 390)], games: headToHead).map(\.nick) == ["b", "a"])
        // Then the point differential, then the points scored.
        #expect(Cup.rank([row("a", 3, 400, 390), row("b", 3, 420, 400)], games: []).map(\.nick) == ["b", "a"])
        #expect(Cup.rank([row("a", 3, 400, 390), row("b", 3, 410, 400)], games: []).map(\.nick) == ["b", "a"])
    }

    @Test func tables() {
        let (games, conferences) = cupGroups()
        let cup = Cup.build(startYear: 2026, games: games, official: nil, conferences: conferences)
        #expect(cup.season == "2026-27")
        #expect(!cup.official)
        #expect(cup.groups.map(\.conf) == ["East", "East", "West", "West"])
        // Without NBA.com, groups have no letter.
        #expect(cup.groups[0].name == "East Group")
        let group = cup.groups[0]
        #expect(group.teams.map(\.nick) == ["ea1", "ea2", "ea3"])
        #expect(group.teams.map(\.record) == ["2-0", "1-1", "0-2"])
        #expect(group.teams.map(\.gamesBehind) == ["-", "1", "2"])
        #expect(group.teams.map(\.diff) == ["+10", "+5", "-15"])
        #expect(group.teams.map(\.rank) == [1, 2, 3])
        // The wildcard goes to the best second: b2, on point differential.
        let wildcards = cup.groups.flatMap(\.teams).filter(\.wildcard).map(\.nick)
        #expect(Set(wildcards) == ["eb2", "wb2"])
        #expect(cup.groups[1].teams[1].tag == "wildcard?")
        #expect(cup.teamGroup["ea1"] == "East Group")
        #expect(!cup.done)
    }

    @Test func projectedBracket() {
        let (games, conferences) = cupGroups()
        let bracket = Cup.build(startYear: 2026, games: games, official: nil, conferences: conferences).bracket
        #expect(bracket.projected)
        #expect(!bracket.set)
        // Group winners seeded by record then differential: b1 (+20), a1 (+10); the wildcard b2 is third here.
        let quarterfinals = bracket.east.quarterfinals
        #expect(quarterfinals[0].bottom.nick == "eb1")
        #expect(quarterfinals[0].bottom.seed == 1)
        #expect(quarterfinals[0].bottom.projected)
        #expect(quarterfinals[1].bottom.nick == "ea1")
        #expect(quarterfinals[1].top.nick == "eb2")
        #expect(quarterfinals[1].top.seed == 3)
        #expect(bracket.east.semifinal.top.abbr == "TBD")
        #expect(bracket.champion == nil)
    }

    @Test func officialNamesAndMarks() throws {
        let (games, conferences) = cupGroups()
        func official(_ wins: Int) throws -> CupOfficial {
            var teams: [[String: Any]] = []
            for (prefix, conf) in [("e", "East"), ("w", "West")] {
                for group in ["a", "b"] {
                    for (i, record) in [(wins, 0), (1, 1), (0, 2)].enumerated() {
                        teams.append(["teamName": "\(prefix)\(group)\(i + 1)", "istGroup": "\(conf) Group \(group.uppercased())",
                                      "istGroupRank": i + 1, "wins": record.0, "losses": record.1,
                                      "clinchIndicator": i == 0 ? " - x" : i == 2 ? " - o" : ""])
                    }
                }
            }
            // NBA.com lists the 30 teams.
            while teams.count < 30 { teams.append(["teamName": "other\(teams.count)"]) }
            return try #require(CupOfficial(JSON(["teams": teams])))
        }
        let cup = Cup.build(startYear: 2026, games: games, official: try official(2), conferences: conferences)
        #expect(cup.official)
        #expect(cup.groups.map(\.name) == ["East Group A", "East Group B", "West Group A", "West Group B"])
        #expect(cup.groups[0].teams[0].tag == "group")
        #expect(cup.groups[0].teams[2].eliminated)
        // NBA.com behind on a result: its names still hold, its order and marks do not.
        let behind = Cup.build(startYear: 2026, games: games, official: try official(1), conferences: conferences)
        #expect(!behind.official)
        #expect(behind.groups[0].name == "East Group A")
        #expect(behind.groups[0].teams[0].tag == "")
        #expect(CupOfficial(JSON(["teams": [["teamName": "x"]]])) == nil)
    }

    @Test func knockoutRounds() {
        var (games, conferences) = cupGroups()
        games += [
            cupGame("q1", "eb2", 90, "eb1", 100, round: .quarterfinal),
            cupGame("q2", "", 0, "", 0, round: .quarterfinal, state: .pre),
            cupGame("q3", "wb2", 101, "wb1", 99, round: .quarterfinal),
            cupGame("s1", "eb1", 0, "", 0, round: .semifinal, state: .pre),
            cupGame("f", "eb1", 110, "wb2", 105, round: .final),
        ]
        let cup = Cup.build(startYear: 2026, games: games, official: nil, conferences: conferences)
        let bracket = cup.bracket
        #expect(bracket.set)
        #expect(bracket.east.quarterfinals[0].id == "q1")
        #expect(bracket.east.quarterfinals[0].bottom.nick == "eb1")
        #expect(bracket.east.quarterfinals[0].bottom.winner)
        #expect(bracket.east.quarterfinals[0].bottom.seed == 1)
        // The game with no teams yet is the East's second, since the East has only one so far.
        #expect(bracket.east.quarterfinals[1].id == "q2")
        #expect(bracket.east.quarterfinals[1].bottom.projected)
        #expect(bracket.west.quarterfinals[0].id == "q3")
        #expect(bracket.west.quarterfinals[0].top.winner)
        #expect(bracket.east.semifinal.top.nick == "eb1")
        #expect(bracket.east.semifinal.bottom.abbr == "TBD")
        // West on top in the final.
        #expect(bracket.final.top.nick == "wb2")
        #expect(bracket.final.bottom.nick == "eb1")
        #expect(bracket.champion?.nick == "eb1")
        #expect(cup.done)
    }
}

@Suite struct DayCacheTests {
    @Test func whichDaysToFetch() {
        typealias Entry = Library.DayEntry<CupGame>
        let now = Date()
        let days: [String: Entry] = [
            "20261101": Entry(games: [], final: true, at: now.addingTimeInterval(-86400)),
            "20261102": Entry(games: [], final: false, at: now.addingTimeInterval(-86400)),
            "20261120": Entry(games: [], final: false, at: now.addingTimeInterval(-3600)),
            "20261121": Entry(games: [], final: false, at: now.addingTimeInterval(-7 * 3600)),
        ]
        let window = ["20261101", "20261102", "20261103", "20261120", "20261121", "20270301"]
        // Not the finished day, nor the day to come looked at an hour ago.
        #expect(Library.stale(window, in: days, today: "20261114", now: now) == ["20261102", "20261103", "20261121", "20270301"])
        // With a horizon, days months away are left for later.
        #expect(Library.stale(window, in: days, today: "20261114", now: now, horizon: 60) == ["20261102", "20261103", "20261121"])
    }

    @Test func dayRanges() {
        #expect(GameDay.range(from: "20261230", to: "20270102") == ["20261230", "20261231", "20270101", "20270102"])
        #expect(GameDay.days(from: "20261114", to: "20270301") == 107)
        #expect(GameDay.range(from: "x", to: "y").isEmpty)
    }
}
