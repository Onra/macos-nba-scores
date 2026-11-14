import AppKit
import NBAKit
import SwiftUI

/// `--snapshot <dir>` fetches live data and renders every screen to a PNG, in light and dark, without showing anything.
@MainActor
enum Snapshot {
    static func run(to directory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let model = AppModel()
            await model.fetchCurrent()
            await model.fetch(TableKey(table: .cup, season: model.seasonYear))
            await shoot(model, "scores", to: directory)

            if let game = model.viewGames.first(where: \.hasBoxScore) {
                model.openBox(game)
                await model.fetchBox()
                await shoot(model, "box", to: directory)
                if let player = model.boxes[game.id]?.teams.first?.starters.first {
                    model.openPlayer(player.athlete)
                    await model.fetchPlayer()
                    await shoot(model, "player", to: directory)
                    model.back()
                }
                // An MVP's card, then the voting of his first MVP and of his first All-NBA team.
                model.openPlayer("4278073")
                await model.fetchPlayer()
                await shoot(model, "player-mvp", to: directory)
                for (kind, name) in [(AwardKind.mvp, "award"), (.allNBA, "award-teams")] {
                    model.openAward(kind, season: 2025, me: "4278073")
                    await model.fetchAward()
                    await shoot(model, name, to: directory)
                    model.back()
                }
                model.back()
                do {
                }
                model.openTeam(game.home.team.id)
                await model.fetchTeam()
                await shoot(model, "team", to: directory)
                model.stepTeamSeason(-1)
                await model.fetchTeam()
                await shoot(model, "team-past", to: directory)
                model.back()
                model.back()
            }

            model.openSearch()
            model.query = "sonics"
            try? await Task.sleep(for: .seconds(3))
            await shoot(model, "search", to: directory)
            model.back()

            model.stepDay(1)
            await model.fetchView()
            await shoot(model, "scores-next", to: directory)

            model.show(Tab.standings)
            await model.fetchStandings()
            await shoot(model, "standings", to: directory)
            for (table, name) in [(Table.cup, "cup"), (.playoffs, "playoffs")] {
                model.show(table)
                await model.fetchStandings()
                await shoot(model, name, to: directory)
                model.stepSeason(-1)
                await model.fetchStandings()
                await shoot(model, "\(name)-past", to: directory)
                model.stepSeason(1)
            }
            if let series = model.brackets[model.seasonYear - 1]?.finals, !series.games.isEmpty {
                model.openSeries(series)
                await shoot(model, "series", to: directory)
                model.back()
            }
            exit(0)
        }
        app.run()
    }

    private static func shoot(_ model: AppModel, _ name: String, to directory: String) async {
        for dark in [false, true] {
            await capture(PanelView(model: model), dark: dark, to: "\(directory)/\(name)-\(dark ? "dark" : "light").png")
        }
    }

    private static func capture(_ view: some View, dark: Bool, to file: String) async {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 400, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        // A few passes: logos load, and the scroll area takes the height of its content once that is measured.
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            window.setContentSize(host.fittingSize)
            try? await Task.sleep(for: .milliseconds(150))
        }
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
        }
        window.orderOut(nil)
    }
}
