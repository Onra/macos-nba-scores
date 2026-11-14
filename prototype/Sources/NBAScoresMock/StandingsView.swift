import SwiftUI

struct StandingsView: View {
    static let columns = ["W-L", "GB", "Home", "Away", "L10", "Strk"]
    static let widths: [CGFloat] = [42, 26, 42, 42, 36, 34]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            conference("Western Conference", Mock.west)
            conference("Eastern Conference", Mock.east)
        }
        .padding(.vertical, 6)
    }

    private func conference(_ title: String, _ teams: [Standing]) -> some View {
        VStack(spacing: 1) {
            SectionHeader(title: title, columns: StandingsView.columns, widths: StandingsView.widths)
            ForEach(teams) { standing in
                Row(height: 27, action: {}) {
                    HStack(spacing: 6) {
                        Text("\(standing.seed)")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .trailing)
                        Logo(team: standing.team, size: 20)
                        Text(standing.team.name).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 0)
                        Cells(values: standing.values, widths: StandingsView.widths, bold: [0])
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                // Playoff line under the 6th seed, play-in line under the 10th.
                if standing.seed == 6 || standing.seed == 10 {
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
