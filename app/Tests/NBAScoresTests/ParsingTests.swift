import Foundation
import Testing
@testable import NBAKit

func fixture(_ name: String) throws -> JSON {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try JSON(data: Data(contentsOf: url))
}

@Suite struct GameDayTests {
    @Test func keyFromISO() {
        #expect(GameDay.key(fromISO: "2026-10-12") == "20261012")
        #expect(GameDay.key(fromISO: "2026-10-12T07:00Z") == "20261012")
        #expect(GameDay.key(fromISO: "") == "")
    }

    @Test func label() {
        #expect(GameDay.label("20261114") == "Sat 14 Nov")
        #expect(GameDay.label("20270101") == "Fri 1 Jan")
        #expect(GameDay.label("nope") == "")
    }

    @Test func mergeKeepsEveryKnownDaySorted() {
        #expect(GameDay.merge(["20261113", "20261115"], ["20261114", "20261113", ""]) == ["20261113", "20261114", "20261115"])
    }

    @Test func seasonLabel() {
        #expect(Season.label(2026) == "2025-26")
        #expect(Season.label(2000) == "1999-00")
        #expect(Season.label(0) == "")
    }
}

@Suite struct ScoreboardTests {
    @Test func currentDay() throws {
        let board = Scoreboard(try fixture("scoreboard-current"))
        // Fetched on the morning of 14 Nov in Paris: the NBA day is still the 13th.
        #expect(board.day == "20261113")
        #expect(board.seasonYear == 2027)
        #expect(board.seasonType == 2)
        #expect(board.days.count == 174)
        #expect(board.days.first == "20261003")
        #expect(board.days == board.days.sorted())
        #expect(board.games.count == 9)
        #expect(board.games.allFinal)
        #expect(board.games.liveCount == 0)
        #expect(board.games.subtitle == "Regular season · 9 games")
    }

    @Test func finalGame() throws {
        let board = Scoreboard(try fixture("scoreboard-current"))
        let game = try #require(board.games.first { $0.id == "401909296" })
        #expect(game.state == .post)
        #expect(game.status == .text("Final"))
        #expect(game.away.team.abbr == "NY")
        #expect(game.away.score == 104)
        #expect(game.home.team.abbr == "IND")
        #expect(game.home.score == 106)
        #expect(game.home.team.name == "Pacers")
        #expect(game.home.team.logo != nil)
        #expect(game.lost(game.away))
        #expect(!game.lost(game.home))
        #expect(game.cup == .group)
        #expect(game.note == "")
        #expect(game.network == "Prime Video")
        #expect(game.hasBoxScore)
        #expect(game.recapURL?.absoluteString == "https://www.nba.com/watch/video/game-recap-pacers-106-knicks-104")
    }

    @Test func overtime() throws {
        let board = Scoreboard(try fixture("scoreboard-current"))
        let game = try #require(board.games.first { $0.id == "401909299" })
        #expect(game.status == .text("Final/OT"))
    }

    @Test func scheduledDay() throws {
        let board = Scoreboard(try fixture("scoreboard-20261114"))
        // A dated answer does not say what today is.
        #expect(board.day == "")
        let game = try #require(board.games.first { $0.id == "401909980" })
        #expect(game.state == .pre)
        #expect(game.status == .tipoff(try Date("2026-11-15T00:00:00Z", strategy: .iso8601)))
        #expect(game.away.team.abbr == "DEN")
        #expect(game.away.record == "6-4")
        #expect(game.home.record == "4-9")
        #expect(game.odds == "DEN -11.5")
        #expect(game.overUnder == "O/U 234.5")
        #expect(game.network == "GCSEN")
        #expect(game.venue == "Smoothie King Center")
        #expect(!game.hasBoxScore)
        #expect(game.recapURL == nil)
        #expect(!board.games.allFinal)
        #expect(board.games == board.games.sorted { $0.date < $1.date })
    }

    @Test func cupRounds() {
        #expect(CupRound(headline: "NBA Cup - Group Play") == .group)
        #expect(CupRound(headline: "NBA Cup - Quarterfinals") == .quarterfinal)
        #expect(CupRound(headline: "NBA Cup - Semifinals") == .semifinal)
        #expect(CupRound(headline: "NBA Cup Championship") == .final)
        #expect(CupRound(headline: "In-Season Tournament - Group Play") == .group)
        #expect(CupRound(headline: "NBA Cup") == .other)
        #expect(CupRound(headline: "Paris Game") == nil)
        #expect(CupRound(headline: "") == nil)
    }

    @Test func recapSlugsNicknames() {
        var game = Game()
        game.state = .post
        game.away.team.nick = "Trail Blazers"
        game.away.score = 103
        game.home.team.nick = "76ers"
        game.home.score = 124
        #expect(game.recapURL?.absoluteString == "https://www.nba.com/watch/video/game-recap-76ers-124-trail-blazers-103")
    }

    @Test func emptyAnswer() throws {
        let board = Scoreboard(try JSON(data: Data("{}".utf8)))
        #expect(board.games.isEmpty)
        #expect(board.day == "")
        #expect(!board.games.allFinal)
        #expect(board.games.subtitle == "")
    }
}

@Suite struct BoxScoreTests {
    @Test func overtimeGame() throws {
        let box = BoxScore(try fixture("summary-401909299"))
        #expect(box.id == "401909299")
        #expect(box.state == .post)
        #expect(box.detail == "Final/OT")
        #expect(box.venue == "United Center")
        #expect(box.periods == ["1", "2", "3", "4", "OT"])
        #expect(box.teams.map(\.side.team.abbr) == ["ATL", "CHI"])
        #expect(box.teams[0].side.score == 117)
        #expect(box.teams[0].side.lines == ["24", "29", "30", "27", "7"])
        #expect(box.teams[0].side.record == "7-6")
        #expect(box.teams[1].side.team.fullName == "Chicago Bulls")
    }

    @Test func players() throws {
        let team = BoxScore(try fixture("summary-401909299")).teams[0]
        #expect(team.starters.count == 5)
        let okongwu = try #require(team.starters.first { $0.name == "O. Okongwu" })
        #expect(okongwu.athlete == "4431680")
        #expect(okongwu.pos == "F")
        #expect(okongwu.stats["MIN"] == "35")
        #expect(okongwu.stats["FG"] == "7-13")
        #expect(okongwu.stats["+/-"] == "+2")
        #expect(okongwu.points == 17)
        let dennis = try #require(team.dnp.first { $0.name == "R. Dennis" })
        #expect(dennis.reason == "Coach's decision")
        // The players' points add up to the team's.
        #expect((team.starters + team.bench).map(\.points).reduce(0, +) == 117)
        // One top scorer at least, and he has the most points.
        let top = (team.starters + team.bench).filter(\.top)
        #expect(!top.isEmpty)
        #expect(top.allSatisfy { $0.points == (team.starters + team.bench).map(\.points).max() })
        #expect(team.totals["PTS"] == "117")
        #expect(team.totals["FG"] == "47-107")
        #expect(team.summary == "FG 44% · 3PT 20% · FT 75% · Paint 66 · Fast break 26 · Largest lead 2")
    }
}

@Suite struct StandingsTests {
    @Test func season() throws {
        let standings = Standings(try fixture("standings-2026"))
        #expect(standings.seasonLabel == "2025-26")
        #expect(standings.played)
        #expect(standings.conferences.map(\.name) == ["Eastern Conference", "Western Conference"])
        let east = standings.conferences[0].teams
        #expect(east.count == 15)
        #expect(east.map(\.seed) == Array(1...15))
        #expect(east[0].team.name == "Pistons")
        #expect(east[0].record == "60-22")
        #expect(east[0].gamesBehind == "-")
        #expect(east[0].home == "31-9")
        #expect(east[0].road == "28-13")
        #expect(east[0].lastTen == "8-2")
        #expect(east[0].streak == "W3")
        #expect(east[0].team.logo != nil)
    }
}
