import Foundation
import Testing
@testable import NBAKit

func coachPage(_ code: String) throws -> CoachPage {
    CoachPage(code: code, html: try page("bbref-coach-\(code)"))
}

@Suite struct CoachTests {
    @Test func bio() throws {
        let coach = try coachPage("carliri01c")
        #expect(coach.name == "Rick Carlisle")
        #expect(coach.photo?.absoluteString.hasSuffix("/headshots/carliri01c.png") == true)
        #expect(coach.born == "1959-10-27")
        #expect(coach.birthplace == "Ogdensburg, New York")
        #expect(coach.died == "")
        #expect(coach.highSchool == "Lisbon Central in Lisbon, New York")
        #expect(coach.college == "University of Maine")
        #expect(coach.asPlayer == "188 G, 2.2 PPG, 0.8 RPG, 1.1 APG")
        #expect(coach.hallOfFame == "")
        #expect(coach.age(now: try Date("2026-11-14T00:00:00Z", strategy: .iso8601)) == 67)
    }

    @Test func record() throws {
        let coach = try coachPage("carliri01c")
        #expect(coach.recordText == "1017-931 (.522)")
        #expect(coach.playoffsText == "86-87")
        #expect(coach.titles == ["2010-11"])
        #expect(coach.coachOfTheYear == ["2001-02"])
        #expect(coach.headCoach)
    }

    @Test func seasons() throws {
        let seasons = try coachPage("carliri01c").seasons
        // Newest first, assistant years included.
        #expect(seasons.first?.season == "2026-27")
        #expect(seasons.first?.team == "IND")
        #expect(seasons.first?.record == "5-8")
        #expect(seasons.last?.season == "1989-90")
        #expect(seasons.last?.team == "NJN")
        #expect(seasons.last?.assistant == true)
        #expect(seasons.last?.playoffs == "")
        let title = try #require(seasons.first { $0.season == "2010-11" })
        #expect(title.team == "DAL")
        #expect(title.year == 2011)
        #expect(title.record == "57-25")
        #expect(title.pct == ".695")
        #expect(title.finishText == "2nd")
        #expect(title.playoffs == "16-5")
        #expect(title.champion)
        #expect(seasons.first { $0.season == "2024-25" }?.remark == "EC Champions")
        #expect(seasons.first { $0.season == "2024-25" }?.champion == false)
        // A season without playoffs.
        #expect(seasons.first { $0.season == "2025-26" }?.playoffs == "")
    }

    @Test func withoutAPhoto() throws {
        let coach = try coachPage("daignma99c")
        #expect(coach.name == "Mark Daigneault")
        #expect(coach.photo == nil)
        #expect(coach.college == "UConn")
        #expect(coach.asPlayer == "")
        #expect(coach.seasons.contains { $0.assistant })
    }

    @Test func hallOfFamer() throws {
        let coach = try coachPage("auerbre99c")
        #expect(coach.name == "Red Auerbach")
        #expect(coach.died == "2006-10-28")
        #expect(coach.hallOfFame == "Inducted as Coach in 1969")
        #expect(coach.college == "")
        #expect(coach.age() == 89)
        #expect(coach.titles.count == 9)
        #expect(coach.coachOfTheYear == ["1964-65"])
    }

    @Test func finishes() {
        #expect(CoachSeason(finish: "1").finishText == "1st")
        #expect(CoachSeason(finish: "2").finishText == "2nd")
        #expect(CoachSeason(finish: "3").finishText == "3rd")
        #expect(CoachSeason(finish: "4").finishText == "4th")
        #expect(CoachSeason(finish: "11").finishText == "11th")
        #expect(CoachSeason(finish: "").finishText == "")
    }

    @Test func teamCoaches() throws {
        let mil = Coaches.teamCoaches(html: try page("bbref-team-MIL-2024"))
        #expect(mil.map(\.name) == ["Adrian Griffin", "Joe Prunty", "Doc Rivers"])
        #expect(mil.map(\.code) == ["griffad01c", "pruntjo01c", "riverdo01c"])
        #expect(mil.map(\.record) == ["30-13", "2-1", "17-19"])
        #expect(Coaches.teamCoaches(html: try page("bbref-team-IND-2027")) == [CoachRef(code: "carliri01c", name: "Rick Carlisle", record: "5-8")])
        #expect(Coaches.teamCoaches(html: "<p>nothing</p>").isEmpty)
    }

    @Test func franchiseCodes() {
        #expect(Coaches.bbrefCode("OKC", season: 2008) == "SEA")
        #expect(Coaches.bbrefCode("OKC", season: 2009) == "OKC")
        #expect(Coaches.bbrefCode("BKN", season: 2012) == "NJN")
        #expect(Coaches.bbrefCode("BKN", season: 2013) == "BRK")
        #expect(Coaches.bbrefCode("MEM", season: 2001) == "VAN")
        #expect(Coaches.bbrefCode("WSH", season: 1997) == "WSB")
        #expect(Coaches.bbrefCode("WSH", season: 2026) == "WAS")
        #expect(Coaches.bbrefCode("CHA", season: 1999) == "CHH")
        #expect(Coaches.bbrefCode("CHA", season: 2004) == "")
        #expect(Coaches.bbrefCode("CHA", season: 2010) == "CHA")
        #expect(Coaches.bbrefCode("CHA", season: 2026) == "CHO")
        #expect(Coaches.bbrefCode("NO", season: 2002) == "")
        #expect(Coaches.bbrefCode("NO", season: 2004) == "NOH")
        #expect(Coaches.bbrefCode("NO", season: 2007) == "NOK")
        #expect(Coaches.bbrefCode("NO", season: 2010) == "NOH")
        #expect(Coaches.bbrefCode("NO", season: 2026) == "NOP")
        #expect(Coaches.bbrefCode("GS", season: 2026) == "GSW")
        #expect(Coaches.bbrefCode("UTAH", season: 2026) == "UTA")
        #expect(Coaches.bbrefCode("PHX", season: 2026) == "PHO")
        #expect(Coaches.bbrefCode("IND", season: 2026) == "IND")
        #expect(Coaches.nbaTeamIDs.count == 30)
    }

    @Test func nbaPhotoID() throws {
        let html = try page("nba-team-coaches")
        #expect(Coaches.nbaCoachID(html: html, name: "Mark Daigneault") == "1627327")
        #expect(Coaches.nbaCoachID(html: html, name: "Dave Bliss") == "1629758")
        #expect(Coaches.nbaCoachID(html: html, name: "Rick Carlisle") == nil)
        #expect(Coaches.nbaHeadshot("1627327").absoluteString == "https://cdn.nba.com/headshots/nba/latest/260x190/1627327.png")
    }

    @Test func coachOfTheYearVoting() throws {
        let rows = Awards.rows(.coy, in: Awards.parse(html: try page("bbref-awards-2025")))
        #expect(rows.count == 6)
        let winner = try #require(rows.first)
        #expect(winner.name == "Kenny Atkinson")
        #expect(winner.coach == "atkinke01c")
        #expect(winner.team == "CLE")
        #expect(winner.first == "59")
        #expect(winner.shareText == "80.2%")
        #expect(winner.athlete == "")
        // Player tables name no coach.
        #expect(Awards.rows(.mvp, in: Awards.parse(html: try page("bbref-awards-2025"))).allSatisfy { $0.coach.isEmpty })
    }
}
