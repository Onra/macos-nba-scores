import NBAKit
import SwiftUI

struct CoachView: View {
    let model: AppModel
    let code: String

    static let columns = ["W-L", "PCT", "Finish", "Playoffs"]
    static let widths: [CGFloat] = [54, 48, 52, 64]

    var body: some View {
        if let coach = model.coaches[code] {
            VStack(spacing: 20) {
                bio(coach)
                if !coach.titles.isEmpty || !coach.coachOfTheYear.isEmpty {
                    VStack(spacing: 2) {
                        SectionHeader(title: coach.titles.isEmpty ? "Awards" : "Titles and awards")
                        if !coach.titles.isEmpty {
                            honor("NBA Champion", seasons: coach.titles, title: true)
                        }
                        if !coach.coachOfTheYear.isEmpty {
                            honor("Coach of the Year", seasons: coach.coachOfTheYear, title: false)
                        }
                    }
                }
                if !coach.seasons.isEmpty {
                    VStack(spacing: 2) {
                        SectionHeader(title: "Career by season", columns: CoachView.columns, widths: CoachView.widths)
                        ForEach(coach.seasons) { season($0) }
                    }
                }
            }
            .padding(.vertical, 6)
        } else if model.failed.contains(.coach(code)) {
            Placeholder(text: "Couldn't reach Basketball-Reference")
        } else {
            Placeholder(text: "Loading…", loading: true)
        }
    }

    private func bio(_ coach: CoachPage) -> some View {
        let born = coach.birthDate.map { $0.formatted(.dateTime.day().month().year().locale(Locale.current)) } ?? ""
        var facts: [(String, String)] = []
        if coach.died.isEmpty {
            facts.append(("Age", [coach.age().map(String.init) ?? "", born.isEmpty ? "" : "(\(born))"].filter { !$0.isEmpty }.joined(separator: "  ")))
        } else {
            facts.append(("Born", born))
            let died = coach.deathDate.map { $0.formatted(.dateTime.day().month().year().locale(Locale.current)) } ?? ""
            facts.append(("Died", [died, coach.age().map { "(aged \($0))" } ?? ""].filter { !$0.isEmpty }.joined(separator: " ")))
        }
        facts += [
            ("From", coach.birthplace),
            ("College", coach.college),
            ("Record", coach.recordText),
            ("Playoffs", coach.playoffsText),
            ("Hall of Fame", coach.hallOfFame),
        ]
        return HStack(alignment: .top, spacing: 16) {
            ZStack {
                if coach.photo == nil {
                    Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(.quaternary)
                }
                RemoteImage(coach.photo)
            }
            .frame(width: 124, height: 90)
            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 10))
            .clipShape(.rect(cornerRadius: 10))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(facts.filter { !$0.1.isEmpty }, id: \.0) { fact in
                    GridRow {
                        Caption(fact.0)
                        Text(fact.1).font(.system(size: 12.5)).monospacedDigit()
                    }
                }
                if !coach.asPlayer.isEmpty {
                    GridRow {
                        Caption("As player")
                        // His card, found on ESPN by his name.
                        Button { model.openPlayer(named: coach.name) } label: {
                            HStack(spacing: 4) {
                                Text(coach.asPlayer)
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 12.5))
                            .monospacedDigit()
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.rowInset)
    }

    /// A title opens the bracket of its season, an award its voting with his line marked.
    private func honor(_ name: String, seasons: [String], title: Bool) -> some View {
        HonorRow(label: seasons.count > 1 ? "\(seasons.count)× \(name)" : name, seasons: seasons, title: title) { season in
            let year = Season.endYear(season)
            if title {
                return year >= Table.playoffs.firstSeason ? { model.openBracket(.playoffs, season: year) } : nil
            }
            return year >= AwardKind.coy.firstSeason ? { model.openAward(.coy, season: year, me: code) } : nil
        }
    }

    /// A season with a team, which opens that team's page for that season.
    private func season(_ season: CoachSeason) -> some View {
        Row(height: 24, action: season.teamID.isEmpty ? nil : { model.openTeam(season.teamID, season: season.year) }) {
            HStack(spacing: 6) {
                Text(season.season).font(.system(size: 12.5, weight: season.champion ? .semibold : .regular)).monospacedDigit()
                Text(season.team).font(.system(size: 10)).foregroundStyle(.secondary)
                if season.champion {
                    Image(systemName: "trophy.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                }
                Text(season.assistant ? "Assistant coach" : season.remark)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !season.assistant {
                    Cells(values: [season.record, season.pct, season.finishText, season.playoffs], widths: CoachView.widths, bold: [0])
                        .font(.system(size: 12))
                }
            }
            .foregroundStyle(season.assistant ? .secondary : .primary)
        }
    }
}

/// A coach's name, which opens his page. Underlined under the pointer.
struct CoachLink: View {
    let model: AppModel
    let coach: CoachRef
    var showRecord = false
    @State private var hovering = false

    var body: some View {
        Button { model.openCoach(coach.code) } label: {
            HStack(spacing: 4) {
                Text(coach.name).underline(hovering)
                if showRecord { Text("(\(coach.record))").foregroundStyle(.tertiary).monospacedDigit() }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
