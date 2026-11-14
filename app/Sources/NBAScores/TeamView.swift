import NBAKit
import SwiftUI

struct TeamView: View {
    let model: AppModel

    var body: some View {
        if let route = model.stack.last, let page = model.teamPages[route] {
            VStack(spacing: 18) {
                banner(page)
                if !page.roster.isEmpty { roster(page) }
                ForEach(TeamPage.phases, id: \.type) { phase in
                    let games = page.games.filter { $0.phase == phase.type }
                    if !games.isEmpty {
                        VStack(spacing: 1) {
                            SectionHeader(title: phase.label)
                            ForEach(games) { game in
                                TeamGameRow(model: model, game: game, season: page.current ? 0 : page.season)
                            }
                        }
                    }
                }
                if page.games.isEmpty {
                    Placeholder(text: "No games this season")
                }
            }
            .padding(.vertical, 6)
        } else if let route = model.stack.last, model.failed.contains(route) {
            Placeholder(text: "Couldn't reach ESPN")
        } else {
            Placeholder(text: "Loading…", loading: true)
        }
    }

    private func banner(_ page: TeamPage) -> some View {
        HStack(spacing: 12) {
            RemoteImage(page.logo).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.record.isEmpty ? page.seasonLabel : page.record).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                Text(details(page)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Layout.rowInset)
    }

    /// Under the record: "home 33-8 · away 28-13 · 1st in Pacific Division"
    private func details(_ page: TeamPage) -> String {
        guard !page.record.isEmpty else { return page.subtitle }
        var bits: [String] = []
        if !page.homeRecord.isEmpty { bits.append("home \(page.homeRecord)") }
        if !page.roadRecord.isEmpty { bits.append("away \(page.roadRecord)") }
        if !page.standing.isEmpty { bits.append(page.standing) }
        return bits.joined(separator: " · ")
    }

    /// Two columns, by number.
    private func roster(_ page: TeamPage) -> some View {
        let half = (page.roster.count + 1) / 2
        return VStack(spacing: 2) {
            SectionHeader(title: page.coach.isEmpty ? "Roster" : "Roster · coach \(page.coach)")
            HStack(alignment: .top, spacing: 12) {
                ForEach([Array(page.roster.prefix(half)), Array(page.roster.dropFirst(half))], id: \.self) { column in
                    VStack(spacing: 1) {
                        ForEach(column) { player in
                            Row(height: 24, action: { model.openPlayer(player.id) }) {
                                HStack(spacing: 6) {
                                    Text(player.jersey)
                                        .font(.system(size: 11))
                                        .monospacedDigit()
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 18, alignment: .trailing)
                                    Text(player.name).font(.system(size: 12.5)).lineLimit(1)
                                    Text(player.pos).font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Spacer(minLength: 0)
                                    if !player.injury.isEmpty {
                                        Text(player.injury).font(.system(size: 10.5)).foregroundStyle(.red).lineLimit(1)
                                    } else if let age = player.age {
                                        Text("\(age)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One game of the team: the day, home or away, the opponent, the result.
struct TeamGameRow: View {
    let model: AppModel
    let game: TeamGame
    /// The season of the page, for the opponent's link.
    let season: Int

    var body: some View {
        Row(height: 26, action: game.state == .pre ? nil : { model.openBox(id: game.id) }) {
            HStack(spacing: 8) {
                Text(GameDay.label(game.day))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 78, alignment: .leading)
                Text(game.atHome ? "vs" : "@")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, alignment: .leading)
                TeamLink(model: model, team: game.opp.team, season: season, logoSize: 18, font: .system(size: 12.5))
                if let tag = game.cupTag {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill").font(.system(size: 8))
                        Text(tag)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                result
            }
        }
    }

    @ViewBuilder private var result: some View {
        if let text = game.resultText {
            Text(text)
                .font(.system(size: 12, weight: game.result == "W" ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(game.state == .live ? AnyShapeStyle(.red) : game.result == "L" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        } else if let date = game.date {
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// A team's logo and name, which open its page. Underlined under the pointer.
struct TeamLink: View {
    let model: AppModel
    let team: Team
    var season = 0
    var logoSize: CGFloat = 22
    var font = Font.system(size: 13)
    var spacing: CGFloat = 8
    var dimmed = false
    @State private var hovering = false

    var body: some View {
        let label = HStack(spacing: spacing) {
            Logo(team: team, size: logoSize).opacity(dimmed ? 0.7 : 1)
            Text(team.name).font(font).lineLimit(1).underline(hovering && !team.id.isEmpty)
        }
        if team.id.isEmpty {
            label
        } else {
            Button { model.openTeam(team.id, season: season) } label: { label.contentShape(.rect) }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        }
    }
}
