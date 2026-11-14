import SwiftUI

struct PlayerView: View {
    static let columns = ["GP", "MIN", "PTS", "REB", "AST", "STL", "BLK", "TO", "FG%", "3P%", "FT%"]
    static let widths: [CGFloat] = [34, 42, 42, 40, 40, 38, 38, 38, 44, 44, 44]

    var body: some View {
        VStack(spacing: 20) {
            bio
            section(Mock.seasonLabel, columns: true) {
                let career = Mock.averages.last!
                ForEach(Mock.averages) { row in
                    StatLine(row: row, bold: row.id == Mock.averages[0].id, against: row.id == Mock.averages[0].id ? career : nil)
                }
            }
            section("Salary") {
                ForEach(Mock.salaries) { salary in
                    Row(height: 24) {
                        HStack(spacing: 6) {
                            Text(salary.season).monospacedDigit()
                            Text(salary.team).font(.system(size: 10)).foregroundStyle(.secondary)
                            if let note = salary.note {
                                Text(note).font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(salary.amount).monospacedDigit()
                        }
                        .font(.system(size: 12.5, weight: salary.current ? .semibold : .regular))
                    }
                }
            }
            section("Titles and awards") {
                ForEach(Mock.awards, id: \.name) { award in
                    Row(height: 24, action: {}) {
                        HStack(spacing: 6) {
                            if award.title {
                                Image(systemName: "trophy.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                            }
                            Text(award.name).font(.system(size: 12.5))
                            Spacer()
                            Text(award.seasons).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            section("Career · regular season averages", columns: true) {
                ForEach(Mock.career) { row in
                    StatLine(row: row, bold: row.team == nil, action: row.team == nil ? nil : {})
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var bio: some View {
        HStack(alignment: .top, spacing: 16) {
            RemoteImage(Mock.headshot)
                .frame(width: 124, height: 90)
                .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
                .clipShape(.rect(cornerRadius: 10))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(Mock.bio, id: \.label) { item in
                    GridRow {
                        Caption(item.label)
                        Text(item.value).font(.system(size: 12.5)).monospacedDigit()
                    }
                }
                GridRow {
                    Caption("Injury")
                    Text(Mock.injury).font(.system(size: 12.5)).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.rowInset)
    }

    private func section(_ title: String, columns: Bool = false, @ViewBuilder rows: () -> some View) -> some View {
        VStack(spacing: 2) {
            SectionHeader(
                title: title,
                columns: columns ? PlayerView.columns : [],
                widths: columns ? PlayerView.widths : []
            )
            rows()
        }
    }
}

/// One line of averages. With `against`, each figure gets an arrow: green when it beats that line, red when it does not.
struct StatLine: View {
    let row: StatRow
    var bold = false
    var against: StatRow?
    var action: (() -> Void)?

    var body: some View {
        Row(height: 24, action: action) {
            HStack(spacing: 6) {
                Text(row.label).font(.system(size: 12.5, weight: bold ? .semibold : .regular)).monospacedDigit()
                if let team = row.team {
                    Text(team).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(row.values.indices, id: \.self) { i in
                        HStack(spacing: 2) {
                            arrow(i)
                            Text(row.values[i]).fontWeight(i == 2 || bold ? .semibold : .regular)
                        }
                        .frame(width: PlayerView.widths[i], alignment: .trailing)
                    }
                }
                .font(.system(size: 12))
                .monospacedDigit()
            }
        }
    }

    @ViewBuilder private func arrow(_ i: Int) -> some View {
        // No arrow on games played; fewer turnovers (column 7) is better.
        if i > 0, let against, let value = Double(row.values[i]), let base = Double(against.values[i]), value != base {
            let up = value > base
            Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 5.5))
                .foregroundStyle(up == (i != 7) ? .green : .red)
        }
    }
}
