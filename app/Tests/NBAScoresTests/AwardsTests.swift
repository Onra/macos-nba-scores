import Foundation
import Testing
@testable import NBAKit

@Suite struct AwardsTests {
    @Test func kinds() {
        #expect(AwardKind(awardName: "MVP") == .mvp)
        #expect(AwardKind(awardName: "All-NBA 1st Team") == .allNBA)
        #expect(AwardKind(awardName: "All-Rookie 2nd Team") == .allRookie)
        #expect(AwardKind(awardName: "All-Defensive 2nd Team") == .allDefensive)
        #expect(AwardKind(awardName: "Clutch Player of the Year") == .clutch)
        #expect(AwardKind(awardName: "Sixth Man of the Year") == .smoy)
        // No voting to show.
        #expect(AwardKind(awardName: "Finals MVP") == nil)
        #expect(AwardKind(awardName: "NBA Cup All-Tournament Team") == nil)
        #expect(AwardKind.allNBA.grouped)
        #expect(!AwardKind.mvp.grouped)
    }

    @Test func mvpVoting() throws {
        let tables = Awards.parse(html: try page("bbref-awards-2025"))
        let rows = Awards.rows(.mvp, in: tables)
        #expect(rows.count == 12)
        let winner = try #require(rows.first)
        #expect(winner.rank == "1")
        #expect(winner.name == "Shai Gilgeous-Alexander")
        #expect(winner.team == "OKC")
        #expect(winner.first == "71")
        #expect(winner.points == "913")
        #expect(winner.share == "0.913")
        #expect(winner.shareText == "91.3%")
        #expect(winner.group == "")
    }

    @Test func allNBATeams() throws {
        // The table sits in an HTML comment in the fixture, as Basketball-Reference hides some.
        let rows = Awards.rows(.allNBA, in: Awards.parse(html: try page("bbref-awards-2025")))
        let groups = Dictionary(grouping: rows, by: \.group)
        #expect(groups["1st team"]?.count == 5)
        #expect(groups["2nd team"]?.count == 5)
        #expect(groups["3rd team"]?.count == 5)
        #expect(groups["Other votes"]?.contains { $0.name == "Devin Booker" && $0.team == "PHO" } == true)
        #expect(groups["1st team"]?.contains { $0.name == "Shai Gilgeous-Alexander" } == true)
        // Listed in the page's order: the teams, then the others.
        #expect(rows.first?.group == "1st team")
        #expect(rows.last?.group == "Other votes")
        #expect(Awards.rows(.roy, in: [:]).isEmpty)
    }

    @Test func abaYears() {
        let tables = ["nba_mvp": [Vote(name: "Kareem Abdul-Jabbar")], "aba_mvp": [Vote(name: "Julius Erving")]]
        #expect(Awards.rows(.mvp, in: tables).map(\.name) == ["Kareem Abdul-Jabbar"])
    }

    @Test func shares() {
        #expect(Vote(share: "1").shareText == "100%")
        #expect(Vote(share: "0.935").shareText == "93.5%")
        #expect(Vote(share: "").shareText == "")
    }

    @Test func teamCodes() throws {
        let teams = try directory()
        #expect(Awards.teamID("PHO", season: 2025, teams: teams) == Teams.resolve("PHX", in: teams))
        // The Sonics' page is the Thunder's.
        #expect(Awards.teamID("SEA", season: 1996, teams: teams) == "25")
        // No team page before 1992-93, nor for a player traded during the season.
        #expect(Awards.teamID("BOS", season: 1986, teams: teams) == "")
        #expect(Awards.teamID("TOT", season: 2025, teams: teams) == "")
    }

    @Test func matchingNames() {
        let found = [SearchResult(kind: .player, target: "2", name: "Gary Payton II"),
                     SearchResult(kind: .player, target: "1", name: "Gary Payton"),
                     SearchResult(kind: .player, target: "3", name: "Nikola Jokic")]
        #expect(Awards.match("Gary Payton", among: found) == "1")
        #expect(Awards.match("Gary Payton II", among: found) == "2")
        #expect(Awards.match("Nikola Jokić", among: found) == "3")
        #expect(Awards.match("Nobody", among: found) == "")
    }

    @Test func lastSeason() throws {
        let november = try Date("2026-11-14T00:00:00Z", strategy: .iso8601)
        let march = try Date("2026-03-01T00:00:00Z", strategy: .iso8601)
        #expect(Awards.lastSeason(now: november) == 2026)
        #expect(Awards.lastSeason(now: march) == 2025)
    }
}
