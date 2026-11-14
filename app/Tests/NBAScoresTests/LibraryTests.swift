import Foundation
import Testing
@testable import NBAKit

func page(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

func directory() throws -> [TeamRef] { Teams.parse(try fixture("teams")) }

func sga() throws -> PlayerCard {
    let abbrs = Dictionary(uniqueKeysWithValues: try directory().map { ($0.id, $0.abbr) })
    return PlayerCard(id: "4278073", bio: try fixture("player-bio"), overview: try fixture("player-overview"),
                      stats: try fixture("player-stats"), teams: abbrs)
}

@Suite struct TextTests {
    @Test func normalizedNames() {
        #expect(Text.normalizedName("Nikola Jokić") == "nikola jokic")
        #expect(Text.normalizedName("Jaren Jackson Jr.") == "jaren jackson")
        #expect(Text.normalizedName("De'Aaron Fox") == "de aaron fox")
        #expect(Text.normalizedName("Shai Gilgeous-Alexander") == "shai gilgeous alexander")
        #expect(Text.normalizedName("  Gary  Payton II ") == "gary payton")
    }

    @Test func unescape() {
        #expect(Text.unescape("De&#39;Aaron Fox") == "De'Aaron Fox")
        #expect(Text.unescape("A &amp; B") == "A & B")
        #expect(Text.unescape("plain") == "plain")
    }

    @Test func format() {
        #expect(Format.money(40_806_150) == "$40.8M")
        #expect(Format.money(950_000) == "$950K")
        #expect(Format.money(500) == "$500")
        #expect(Format.money(0) == "")
        #expect(Format.height("6' 6\"") == "6' 6\" (1.98 m)")
        #expect(Format.height("7'") == "7' (2.13 m)")
        #expect(Format.height("") == "")
        #expect(Format.weight("195 lbs") == "195 lbs (88 kg)")
        #expect(Format.weight("n/a") == "n/a")
    }
}

@Suite struct TeamsTests {
    @Test func directoryAndCodes() throws {
        let teams = try directory()
        #expect(teams.count == 30)
        #expect(Teams.resolve("OKC", in: teams) == "25")
        #expect(Teams.resolve("okc", in: teams) == "25")
        #expect(Teams.resolve("NYK", in: teams) == "18")
        #expect(Teams.resolve("13", in: teams) == "13")
        #expect(Teams.resolve("XXX", in: teams) == "")
    }
}

@Suite struct PlayerTests {
    @Test func bio() throws {
        let card = try sga()
        #expect(card.name == "Shai Gilgeous-Alexander")
        #expect(card.jersey == "#2")
        #expect(card.position == "Guard")
        #expect(card.team == "Oklahoma City Thunder")
        #expect(card.teamID == "25")
        #expect(card.teamAbbr == "OKC")
        #expect(card.age == 28)
        #expect(card.dob == "12/7/1998")
        #expect(card.birthplace == "Toronto, ON")
        #expect(card.draft == "2018: Rd 1, Pk 11 (CHA)")
        #expect(card.college == "Kentucky")
        #expect(card.experience == "9th Season")
        #expect(card.injury == "")
        #expect(card.headshot != nil)
        #expect(!card.retired)
        #expect(card.subtitle == "#2 · Guard · Oklahoma City Thunder")
        #expect(card.seasonTitle == "2026-27 season")
    }

    @Test func stats() throws {
        let card = try sga()
        #expect(card.seasonLines.map(\.label) == ["Regular season", "Career"])
        #expect(card.seasonLines[0].stats["PTS"] == "29.7")
        #expect(card.seasonLines[0].stats["GP"] == "12")
        #expect(card.career.count == 9)
        #expect(card.career.first?.label == "2026-27")
        #expect(card.career.first?.team == "OKC")
        #expect(card.career.last?.label == "2018-19")
        #expect(card.career.last?.team == "LAC")
        #expect(card.career.last?.stats["PTS"] == "10.8")
        #expect(card.careerTotal?["PTS"] == "25.4")
        #expect(Set(card.career[0].stats.keys) == Set(PlayerCard.columns))
    }

    @Test func trends() throws {
        let trends = try sga().seasonTrends
        #expect(trends["PTS"] == 1)
        #expect(trends["FG%"] == -1)
        #expect(trends["STL"] == -1)
        // Fewer turnovers than his career: better.
        #expect(trends["TO"] == 1)
        #expect(trends["GP"] == nil)
        #expect(PlayerCard.trends(["PTS": "20.0"], against: ["PTS": "20.0"]).isEmpty)
        #expect(PlayerCard.trends(["TO": "3.0"], against: ["TO": "2.0"]) == ["TO": -1])
    }

    @Test func awards() throws {
        let card = try sga()
        let mvp = try #require(card.awards.first { $0.name == "MVP" })
        #expect(mvp.seasons == ["2025-26", "2024-25"])
        #expect(mvp.label == "2× MVP")
        #expect(card.awards.first { $0.name == "Finals MVP" }?.label == "Finals MVP")
    }

    @Test func retiredAndFreeAgent() {
        var card = PlayerCard()
        card.team = "Chicago Bulls"
        card.status = "Inactive"
        card.splits = [StatLine(label: "Career")]
        #expect(card.teamText == "Retired")
        #expect(card.seasonLines.isEmpty)
        card.status = "Free Agent"
        #expect(card.teamText == "Free agent")
    }
}

@Suite struct SalaryTests {
    @Test func contractsTable() throws {
        let table = ContractsTable(html: try page("bbref-contracts"))
        #expect(table.players.map(\.name) == ["Shai Gilgeous-Alexander", "Jaren Jackson Jr.", "Nikola Jokić", "Jalen Suggs"])
        let future = table.future(name: "Shai Gilgeous-Alexander", team: "OKC", after: "2026-27")
        #expect(future.map(\.season) == ["2027-28", "2028-29", "2029-30", "2030-31"])
        #expect(future.map(\.amount) == [61_005_000, 65_885_400, 70_765_800, 75_646_200])
        #expect(future.map(\.option) == ["", "", "", "player option"])
        #expect(future.allSatisfy { $0.future })
        #expect(future[0].year == 2028)
        // Accents and suffixes do not matter.
        #expect(!table.future(name: "Nikola Jokic", team: "DEN", after: "").isEmpty)
        #expect(!table.future(name: "Jaren Jackson", team: "UTAH", after: "").isEmpty)
        #expect(table.future(name: "Nobody", team: "", after: "").isEmpty)
        #expect(table.players.flatMap(\.years).contains { $0.option == "team option" })
    }

    @Test func salaryRows() throws {
        var card = try sga()
        let contracts = [
            Salary(year: 2019, season: "2018-19", teamID: "25", amount: 3_375_360),
            Salary(year: 2027, season: "2026-27", teamID: "25", amount: 40_806_150, yearsRemaining: 5),
        ]
        card.setSalaries(contracts, table: ContractsTable(html: try page("bbref-contracts")), teams: ["25": "OKC"])
        let rows = card.salaryRows
        #expect(rows.map(\.season) == ["2030-31", "2029-30", "2028-29", "2027-28", "2026-27", "2018-19"])
        #expect(rows[0].note == "player option")
        #expect(rows[0].amount == "$75.6M")
        #expect(rows.map(\.current) == [false, false, false, false, true, false])
        // ESPN files every season under his current team; the career knows he was a Clipper then.
        #expect(rows[5].team == "LAC")
        #expect(rows[4].team == "OKC")
        #expect(rows[4].note == "")
    }

    @Test func tradedDuringTheSeason() {
        var card = PlayerCard()
        // Newest first: the whole season, then where he ended it, then where he started it.
        card.career = [StatLine(label: "2023-24"), StatLine(label: "2023-24", team: "NY", teamID: "18"),
                       StatLine(label: "2023-24", team: "TOR", teamID: "28")]
        card.setSalaries([Salary(year: 2024, season: "2023-24", teamID: "18", amount: 18_642_857)], table: nil, teams: [:])
        #expect(card.salaryRows.first?.team == "NY")
    }

    @Test func withoutTheSeasonsToCome() throws {
        var card = try sga()
        card.setSalaries([Salary(year: 2027, season: "2026-27", teamID: "25", amount: 40_806_150, yearsRemaining: 5)],
                         table: nil, teams: [:])
        #expect(card.salaryRows.map(\.note) == ["4 more years on the deal"])
        card.setSalaries([Salary(year: 2027, season: "2026-27", teamID: "25", amount: 0)], table: nil, teams: [:])
        #expect(card.salaryRows.map(\.amount) == ["n/a"])
    }
}

@Suite struct TitlesTests {
    @Test func champions() throws {
        let champions = Titles.champions(html: try page("bbref-leagues"), teams: try directory())
        #expect(champions[2026] == "18")
        #expect(champions[2025] == "25")
        #expect(champions[2024] == "2")
        // The Sonics are the Thunder today.
        #expect(champions[1979] == "25")
        // The season being played has no champion, and the ABA's are not NBA titles.
        #expect(champions[2027] == nil)
        #expect(champions[1976] == nil)
    }

    @Test func gameLog() throws {
        let games = Titles.games(gamelog: try fixture("player-gamelog-2025"))
        #expect(!games.isEmpty)
        #expect(games == games.sorted { $0.date < $1.date })
        // All his games but the two of the All-Star weekend are the Thunder's.
        #expect(games.count { $0.teamID == "25" } >= games.count - 2)
        #expect(games.last?.teamID == "25")
        // The last game of 2024-25 is game 7 of the Finals, in June.
        #expect(games.last?.date.hasPrefix("2025-06") == true)
    }

    @Test func cupFinal() throws {
        let board = try JSON(data: Data("""
        {"events": [
          {"date": "2025-12-17T01:30Z", "competitions": [{"notes": [{"headline": "NBA Cup - Semifinals"}],
            "status": {"type": {"completed": true}}, "competitors": [{"winner": true, "team": {"id": "1"}}]}]},
          {"date": "2025-12-17T01:30Z", "competitions": [{"notes": [{"headline": "NBA Cup Championship"}],
            "status": {"type": {"completed": true}},
            "competitors": [{"winner": false, "team": {"id": "24"}}, {"winner": true, "team": {"id": "18"}}]}]}
        ]}
        """.utf8))
        #expect(Titles.cupFinal(scoreboard: board) == Titles.CupFinal(teamID: "18", date: "2025-12-17T01:30Z"))
        #expect(Titles.cupFinal(scoreboard: JSON(nil)) == nil)
    }

    @Test func wonWithHisTeam() throws {
        let card = try sga()
        let champions = [2025: "25", 2026: "18", 2019: "28"]
        let log = Titles.games(gamelog: try fixture("player-gamelog-2025"))
        let cups = [2025: Titles.CupFinal(teamID: "15", date: "2024-12-18T01:30Z"),
                    2026: Titles.CupFinal(teamID: "25", date: "2025-12-17T01:30Z")]
        #expect(Titles.candidates(career: card.career, champions: champions, cups: cups).nba == [2025])
        let titles = Titles.won(career: card.career, champions: champions, cups: cups, logs: [2025: log])
        #expect(titles.map(\.name) == ["NBA Champion", "NBA Cup Champion"])
        #expect(titles[0].seasons == ["2024-25"])
        // No game log for 2025-26: a season spent with that team only counts.
        #expect(titles[1].seasons == ["2025-26"])
    }

    @Test func tradedAwayBeforeTheTitle() {
        let career = [StatLine(label: "2024-25", teamID: "25"), StatLine(label: "2024-25", teamID: "7")]
        let log = [Titles.LogGame(date: "2024-11-01T00:00Z", teamID: "25"), Titles.LogGame(date: "2025-04-10T00:00Z", teamID: "7")]
        #expect(Titles.won(career: career, champions: [2025: "25"], cups: [:], logs: [2025: log]).isEmpty)
        // Traded to the champion: his.
        #expect(Titles.won(career: career, champions: [2025: "7"], cups: [:], logs: [2025: log]).map(\.name) == ["NBA Champion"])
        // The Cup counts where he was on the day of the final.
        let cup = [2025: Titles.CupFinal(teamID: "25", date: "2024-12-18T01:30Z")]
        #expect(Titles.won(career: career, champions: [:], cups: cup, logs: [2025: log]).map(\.name) == ["NBA Cup Champion"])
        // Without a log, two teams in the season is not enough to say.
        #expect(Titles.won(career: career, champions: [2025: "25"], cups: [:], logs: [:]).isEmpty)
    }

    @Test func oldSeasonsNamedByTheirEndYear() {
        let career = [StatLine(label: "1993", teamID: "4")]
        #expect(Titles.won(career: career, champions: [1993: "4"], cups: [:], logs: [:]).first?.seasons == ["1992-93"])
    }
}

@Suite struct TeamPageTests {
    func current() throws -> TeamPage {
        TeamPage(id: "25", info: try fixture("team-info"), roster: try fixture("team-roster"),
                 schedules: [2: try fixture("team-schedule2")], current: true)
    }

    @Test func page() throws {
        let page = try current()
        #expect(page.abbr == "OKC")
        #expect(page.name == "Oklahoma City Thunder")
        #expect(page.season == 2027)
        #expect(page.seasonLabel == "2026-27")
        #expect(page.record == "8-5")
        #expect(page.homeRecord == "5-0")
        #expect(page.roadRecord == "3-5")
        #expect(page.standing == "7th in Western Conference Division")
        #expect(page.subtitle == "8-5 · home 5-0 · away 3-5 · 7th in Western Conference Division")
        #expect(page.coach == "Mark Daigneault")
        #expect(!page.final)
    }

    @Test func roster() throws {
        let roster = try current().roster
        #expect(roster.count == 18)
        #expect(roster.first?.jersey == "2")
        // Players without a number come last.
        #expect(roster.suffix(2).allSatisfy { $0.jersey.isEmpty })
        #expect(roster.first?.name == "Shai Gilgeous-Alexander")
    }

    @Test func games() throws {
        let games = try current().games
        #expect(games.count == 80)
        let first = try #require(games.first)
        // Tipped off at 01:50 UTC on the 21st: the 20th for the NBA.
        #expect(first.day == "20261020")
        #expect(!first.atHome)
        #expect(first.opp.abbr == "SA")
        #expect(first.result == "W")
        #expect(first.resultText == "W 116–104")
        #expect(first.cupTag == nil)
        let cup = try #require(games.first { $0.cup != nil })
        #expect(cup.cupTag == "Cup")
        #expect(cup.opp.abbr == "MEM")
        let next = try #require(games.first { $0.state == .pre })
        #expect(next.resultText == nil)
        #expect(next.result == "")
    }

    @Test func pastSeason() throws {
        let page = TeamPage(id: "25", info: try fixture("team-info"), roster: try fixture("team-roster"),
                            schedules: [2: JSON(nil), 3: try fixture("team-schedule3-2026")], current: false)
        #expect(page.roster.isEmpty)
        #expect(page.standing == "")
        #expect(page.coach == "")
        #expect(page.games.count == 15)
        #expect(page.games.allSatisfy { $0.phase == 3 })
        #expect(page.games.first?.resultText == "W 119–84")
        // Playoff games are not in the record.
        #expect(page.record == "")
        #expect(page.final)
    }

    @Test func resultText() {
        var game = TeamGame(us: TeamGameSide(JSON(nil)), opp: TeamGameSide(JSON(nil)))
        game.us.score = "98"
        game.opp.score = "110"
        game.state = .post
        game.result = "L"
        game.detail = "Final/OT"
        #expect(game.resultText == "L 98–110 OT")
        game.state = .live
        game.detail = "Q3 5:12"
        #expect(game.resultText == "Q3 5:12  98–110")
        game.note = "NBA Cup Championship"
        #expect(game.cupTag == "Cup final")
        game.note = "NBA Cup - Quarterfinals"
        #expect(game.cupTag == "Cup QF")
    }

    @Test func easternDay() throws {
        let night = try Date("2026-10-22T02:00:00Z", strategy: .iso8601)
        let afternoon = try Date("2026-10-22T18:00:00Z", strategy: .iso8601)
        #expect(GameDay.eastern(night) == "20261021")
        #expect(GameDay.eastern(afternoon) == "20261022")
    }
}

@Suite struct InjuryTests {
    @Test func leagueList() throws {
        let injuries = Injuries.parse(try fixture("injuries"))
        let holmgren = try #require(injuries["4433255"])
        #expect(holmgren.status == "Out")
        #expect(holmgren.type == "Knee")
        #expect(holmgren.returnDay == "20270102")
        #expect(holmgren.summary == "Out · Knee")
        #expect(holmgren.returnText == "Sat 2 Jan")
        #expect(holmgren.short == "Out · 2 Jan")
        #expect(!holmgren.seasonEnding)
        let flemings = try #require(injuries["5149077"])
        #expect(flemings.short == "Day-To-Day · 15 Nov")
    }

    @Test func seasonEndingAndUnknown() throws {
        let ended = Injury(try JSON(data: Data(#"{"status": "Out", "details": {"type": "Knee", "returnDate": "2027-07-01", "fantasyStatus": {"abbreviation": "OFS"}}}"#.utf8)))
        #expect(ended.returnText == "Out for the season")
        #expect(ended.short == "Out · season")
        let unknown = Injury(try JSON(data: Data(#"{"status": "Out"}"#.utf8)))
        #expect(unknown.returnText == nil)
        #expect(unknown.short == "Out")
        #expect(unknown.summary == "Out")
    }

    @Test func onAPlayerCard() throws {
        let bio = try JSON(data: Data(#"""
        {"athlete": {"displayName": "Tyrese Haliburton", "injuries": [{"status": "Out", "date": "2026-11-11T22:29:00.000+00:00",
          "details": {"type": "Hamstring", "returnDate": "2026-11-22T00:00:00.000+00:00", "fantasyStatus": {"abbreviation": "OUT"}}}]}}
        """#.utf8))
        let card = PlayerCard(id: "1", bio: bio, overview: nil, stats: nil, teams: [:])
        #expect(card.injury == "Out · Hamstring")
        #expect(card.injuryReturn == "Sun 22 Nov")
        #expect(try sga().injuryReturn == nil)
    }

    @Test func onARoster() throws {
        let page = TeamPage(id: "25", info: try fixture("team-info"), roster: try fixture("team-roster"),
                            schedules: [2: try fixture("team-schedule2")], current: true,
                            injuries: Injuries.parse(try fixture("injuries")))
        #expect(page.roster.first { $0.name == "Chet Holmgren" }?.injury == "Out · 2 Jan")
        #expect(page.roster.first { $0.name == "Shai Gilgeous-Alexander" }?.injury == "")
        // Without the league's list, the roster still says who is hurt.
        let plain = TeamPage(id: "25", info: try fixture("team-info"), roster: try fixture("team-roster"),
                             schedules: [2: try fixture("team-schedule2")], current: true)
        #expect(plain.roster.first { $0.name == "Chet Holmgren" }?.injury == "Out")
    }
}

@Suite struct SearchTests {
    @Test func parse() throws {
        let found = Search.parse(try fixture("search-jordan"))
        // Only the NBA: no Jordan Love, no Jordan's soccer team.
        #expect(found.teams.isEmpty)
        #expect(found.players.count == 5)
        #expect(found.players[0].name == "Michael Jordan")
        #expect(found.players[0].target == "1035")
        #expect(found.players[0].subtitle == "Washington Wizards")
    }

    @Test func retiredPlayersSaySo() throws {
        let found = Search.parse(try fixture("search-jordan"))
        let results = Search.merge(teams: [], players: found.players, status: ["1035": "Inactive", "4277956": "Active"])
        #expect(results[0].subtitle == "Retired")
        #expect(results[1].subtitle == "New Orleans Pelicans")
        #expect(results.allSatisfy { $0.image != nil })
    }

    @Test func oldFranchiseNames() throws {
        let teams = try directory()
        let sonics = Search.aliases("Sonics", teams: teams, known: [])
        #expect(sonics.map(\.name) == ["Seattle SuperSonics"])
        #expect(sonics[0].target == "25")
        #expect(sonics[0].subtitle == "Now the Oklahoma City Thunder")
        #expect(Search.aliases("bobcats", teams: teams, known: []).first?.subtitle == "Now the Charlotte Hornets")
        #expect(Search.aliases("New Jersey Nets", teams: teams, known: []).map(\.name) == ["New Jersey Nets"])
        // The team is already in the results, or the query is too short to mean anything.
        #expect(Search.aliases("sonics", teams: teams, known: ["25"]).isEmpty)
        #expect(Search.aliases("ne", teams: teams, known: []).isEmpty)
        #expect(Search.aliases("lebron", teams: teams, known: []).isEmpty)
    }

    @Test func limit() {
        let players = (0..<20).map { SearchResult(kind: .player, target: "\($0)", name: "P\($0)") }
        #expect(Search.merge(teams: [], players: players, status: [:]).count == 10)
    }
}

@Suite struct DiskCacheTests {
    @Test func roundTrip() {
        let cache = DiskCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(cache.load([String].self, "a/b") == nil)
        cache.save(["x", "y"], "a/b")
        #expect(cache.load([String].self, "a/b")?.value == ["x", "y"])
        #expect(cache.fresh([String].self, "a/b", maxAge: 60) == ["x", "y"])
        #expect(cache.fresh([String].self, "a/b", maxAge: 0) == nil)
        try? FileManager.default.removeItem(at: cache.directory)
    }
}
