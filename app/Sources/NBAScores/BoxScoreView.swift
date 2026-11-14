import NBAKit
import SwiftUI

struct BoxScoreView: View {
    let model: AppModel
    let id: String

    static let widths: [CGFloat] = [34, 34, 34, 34, 30, 30, 30, 50, 46, 46, 36]

    var body: some View {
        if let box = model.boxes[id] {
            VStack(spacing: 18) {
                LineScore(box: box).padding(.top, 6)
                ForEach(box.teams, id: \.side.team.id) { team in
                    TeamBoxView(model: model, team: team)
                }
            }
            .padding(.bottom, 6)
        } else {
            Placeholder(text: model.error ?? "Loading…", loading: model.error == nil)
        }
    }
}

/// The score by period.
struct LineScore: View {
    let box: BoxScore

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 76, height: 1)
                ForEach(box.periods, id: \.self) { Caption($0).frame(width: 36, alignment: .trailing) }
                Caption("T").frame(width: 46, alignment: .trailing)
            }
            ForEach(box.teams, id: \.side.team.id) { team in
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Logo(team: team.side.team, size: 18)
                        Text(team.side.team.abbr).font(.system(size: 12, weight: .semibold))
                    }
                    .frame(width: 76, alignment: .leading)
                    ForEach(box.periods.indices, id: \.self) { i in
                        Text(i < team.side.lines.count ? team.side.lines[i] : "")
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    Text(team.side.score.map(String.init) ?? "").fontWeight(.semibold).frame(width: 46, alignment: .trailing)
                }
                .font(.system(size: 12))
                .monospacedDigit()
            }
        }
    }
}

struct TeamBoxView: View {
    let model: AppModel
    let team: TeamBox

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TeamLink(model: model, team: fullNamed, logoSize: 24, font: .system(size: 14, weight: .semibold))
                Text(team.side.score.map(String.init) ?? "").font(.system(size: 14)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Layout.rowInset)
            .padding(.bottom, 10)

            if team.hasPlayers {
                group("Starters", team.starters)
                if !team.bench.isEmpty || !team.dnp.isEmpty {
                    group("Bench", team.bench).padding(.top, 8)
                }
                ForEach(team.dnp) { player in
                    Row(height: 24, action: { model.openPlayer(player.athlete) }) {
                        HStack(spacing: 6) {
                            Text(player.name).font(.system(size: 12))
                            Text(player.reason.isEmpty ? "DNP" : "DNP · \(player.reason)").font(.system(size: 11))
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
                Divider().padding(.horizontal, Layout.rowInset).padding(.top, 2)
                Row(height: 26) {
                    HStack(spacing: 0) {
                        Text("Total").font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                        Cells(values: cells(team.totals), widths: BoxScoreView.widths).font(.system(size: 12, weight: .semibold))
                    }
                }
                if !team.summary.isEmpty {
                    Text(team.summary)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Layout.rowInset)
                        .padding(.top, 4)
                }
            } else {
                Text("No box score yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Layout.rowInset)
            }
        }
    }

    /// The banner names the team in full.
    private var fullNamed: Team {
        var team = team.side.team
        if !team.fullName.isEmpty { team.name = team.fullName }
        return team
    }

    private func cells(_ stats: [String: String]) -> [String] {
        BoxScore.columns.map { stats[$0] ?? "" }
    }

    private func group(_ title: String, _ players: [PlayerLine]) -> some View {
        VStack(spacing: 2) {
            SectionHeader(title: title, columns: BoxScore.columns, widths: BoxScoreView.widths)
            ForEach(players) { player in
                Row(height: 24, action: { model.openPlayer(player.athlete) }) {
                    HStack(spacing: 0) {
                        Text(player.name).font(.system(size: 12.5)).lineLimit(1)
                        Text(player.pos).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.leading, 5)
                        Spacer(minLength: 0)
                        Cells(values: cells(player.stats), widths: BoxScoreView.widths, bold: player.top ? [1] : [])
                            .font(.system(size: 12))
                    }
                }
            }
        }
    }
}
