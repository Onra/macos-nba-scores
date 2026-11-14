import NBAKit
import SwiftUI

struct StandingsView: View {
    let model: AppModel

    static let columns = ["W-L", "GB", "Home", "Away", "L10", "Strk"]
    static let widths: [CGFloat] = [42, 26, 42, 42, 36, 34]

    var body: some View {
        if let standings = model.standings[model.standingsSeason] {
            // West on the left, as in the playoff bracket.
            let conferences = standings.conferences.sorted { $0.name > $1.name }
            HStack(alignment: .top, spacing: 16) {
                ForEach(conferences) { conference in
                    table(conference, cutLines: standings.played)
                }
            }
            .padding(.vertical, 6)
        } else {
            Placeholder(text: model.error ?? "Loading…", loading: model.error == nil)
        }
    }

    private func table(_ conference: Conference, cutLines: Bool) -> some View {
        VStack(spacing: 1) {
            SectionHeader(title: conference.name, columns: StandingsView.columns, widths: StandingsView.widths)
            ForEach(conference.teams) { standing in
                Row(height: 27, action: { model.openTeam(standing.team.id, season: model.standingsSeason) }) {
                    HStack(spacing: 6) {
                        Text(standing.seed > 0 ? "\(standing.seed)" : "")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .trailing)
                        Logo(team: standing.team, size: 20)
                        Text(standing.team.name).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 0)
                        Cells(
                            values: [standing.record, standing.gamesBehind, standing.home, standing.road, standing.lastTen, standing.streak],
                            widths: StandingsView.widths, bold: [0]
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }
                // The playoff line under the 6th seed, the play-in line under the 10th.
                if cutLines, standing.seed == 6 || standing.seed == 10 {
                    CutLine(label: standing.seed == 6 ? "Play-in" : "Out")
                }
            }
        }
    }
}

struct CutLine: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased()).font(.system(size: 8.5, weight: .medium)).kerning(0.6).foregroundStyle(.tertiary)
            Rectangle().fill(.primary.opacity(0.18)).frame(height: 1)
        }
        .padding(.horizontal, Layout.rowInset)
        .frame(height: 9)
    }
}
