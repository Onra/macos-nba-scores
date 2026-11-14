import NBAKit
import SwiftUI

struct PlayerView: View {
    let model: AppModel
    let id: String

    static let widths: [CGFloat] = [34, 42, 42, 40, 40, 38, 38, 38, 44, 44, 44]

    var body: some View {
        if let card = model.players[id] {
            VStack(spacing: 20) {
                bio(card)
                let lines = card.seasonLines
                if !lines.isEmpty {
                    section(card.seasonTitle, columns: true) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            StatLineView(line: line, bold: index == 0, trends: index == 0 ? card.seasonTrends : [:])
                        }
                    }
                }
                let salaries = card.salaryRows
                if !salaries.isEmpty {
                    section("Salary") {
                        ForEach(salaries) { salary in
                            Row(height: 24) {
                                HStack(spacing: 6) {
                                    Text(salary.season).monospacedDigit()
                                    Text(salary.team).font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(salary.note).font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(salary.amount).monospacedDigit()
                                }
                                .font(.system(size: 12.5, weight: salary.current ? .semibold : .regular))
                            }
                        }
                    }
                }
                if !card.titles.isEmpty || !card.awards.isEmpty {
                    section(card.titles.isEmpty ? "Awards" : "Titles and awards") {
                        ForEach(card.titles) { award($0, title: true) }
                        ForEach(card.awards) { award($0, title: false) }
                    }
                }
                if !card.career.isEmpty {
                    section("Career by season", columns: true) {
                        ForEach(card.career) { line in
                            StatLineView(line: line, action: line.teamID.isEmpty ? nil : {
                                model.openTeam(line.teamID, season: Season.endYear(line.label))
                            })
                        }
                        if let total = card.careerTotal {
                            StatLineView(line: StatLine(label: "Career", stats: total), bold: true)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        } else if model.failed.contains(.player(id)) {
            Placeholder(text: "Couldn't reach ESPN")
        } else {
            Placeholder(text: "Loading…", loading: true)
        }
    }

    private func bio(_ card: PlayerCard) -> some View {
        let facts: [(String, String)] = [
            ("Age", [card.age.map(String.init) ?? "", card.dob.isEmpty ? "" : "(\(card.dob))"].filter { !$0.isEmpty }.joined(separator: "  ")),
            ("Size", [Format.height(card.height), Format.weight(card.weight)].filter { !$0.isEmpty }.joined(separator: " · ")),
            ("Born", card.birthplace),
            ("Draft", card.draft),
            ("College", card.college),
            ("NBA", card.experience),
        ].filter { !$0.1.isEmpty }
        return HStack(alignment: .top, spacing: 16) {
            RemoteImage(card.headshot)
                .frame(width: 124, height: 90)
                .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
                .clipShape(.rect(cornerRadius: 10))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(facts, id: \.0) { fact in
                    GridRow {
                        Caption(fact.0)
                        Text(fact.1).font(.system(size: 12.5)).monospacedDigit()
                    }
                }
                if !card.injury.isEmpty {
                    GridRow {
                        Caption("Injury")
                        // ESPN's estimate of his return, beside the injury.
                        HStack(spacing: 5) {
                            Text(card.injury).foregroundStyle(.red)
                            if let back = card.injuryReturn {
                                Text(back.hasPrefix("Out") ? "(\(back.lowercased()))" : "(est. \(back))")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 12.5))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.rowInset)
    }

    private func award(_ award: Award, title: Bool) -> some View {
        Row(height: 24) {
            HStack(spacing: 6) {
                if title {
                    Image(systemName: "trophy.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                }
                Text(award.label).font(.system(size: 12.5)).lineLimit(1)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(Array(award.seasons.enumerated()), id: \.offset) { index, season in
                        SeasonLink(season: season, action: link(award, season: season, title: title))
                        if index < award.seasons.count - 1 { Text(", ") }
                    }
                }
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    /// A title opens the bracket of its season, an award its voting, when there is one.
    private func link(_ award: Award, season: String, title: Bool) -> (() -> Void)? {
        let year = Season.endYear(season)
        if title {
            let table: Table = award.name.contains("Cup") ? .cup : .playoffs
            return year >= table.firstSeason ? { model.openBracket(table, season: year) } : nil
        }
        guard let kind = AwardKind(awardName: award.name), year >= kind.firstSeason else { return nil }
        return { model.openAward(kind, season: year, me: id) }
    }

    private func section(_ title: String, columns: Bool = false, @ViewBuilder rows: () -> some View) -> some View {
        VStack(spacing: 2) {
            SectionHeader(title: title, columns: columns ? PlayerCard.columns : [], widths: columns ? PlayerView.widths : [])
            rows()
        }
    }
}

/// A season of an award: underlined under the pointer when it opens something.
struct SeasonLink: View {
    let season: String
    let action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) { Text(season).underline(hovering).foregroundStyle(hovering ? .primary : .secondary) }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            Text(season)
        }
    }
}

/// One line of averages. With `trends`, a figure gets an arrow: green when it beats the career, red when it does not.
struct StatLineView: View {
    let line: StatLine
    var bold = false
    var trends: [String: Int] = [:]
    var action: (() -> Void)?

    var body: some View {
        Row(height: 24, action: action) {
            HStack(spacing: 6) {
                Text(line.label).font(.system(size: 12.5, weight: bold ? .semibold : .regular)).monospacedDigit()
                if !line.team.isEmpty {
                    Text(line.team).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(Array(PlayerCard.columns.enumerated()), id: \.offset) { i, key in
                        HStack(spacing: 2) {
                            if let trend = trends[key] {
                                // Up or down says where the figure went; the colour says whether that is good.
                                let up = (trend > 0) == (key != "TO")
                                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                    .font(.system(size: 5.5))
                                    .foregroundStyle(trend > 0 ? .green : .red)
                            }
                            Text(line.stats[key] ?? "").fontWeight(key == "PTS" || bold ? .semibold : .regular)
                        }
                        .frame(width: PlayerView.widths[i], alignment: .trailing)
                    }
                }
                .font(.system(size: 12))
                .monospacedDigit()
            }
        }
    }
}
