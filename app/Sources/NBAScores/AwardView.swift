import NBAKit
import SwiftUI

/// The voting of an award in a season, with the player whose card opened it marked.
struct AwardView: View {
    let model: AppModel
    let key: AwardKey

    var body: some View {
        if let page = model.awards[key] {
            if page.rows.isEmpty {
                Placeholder(text: "No voting this season")
            } else {
                let grouped = key.kind.grouped
                VStack(spacing: 1) {
                    if grouped {
                        let groups = page.rows.reduce(into: [String]()) { if $0.last != $1.group { $0.append($1.group) } }
                        ForEach(groups, id: \.self) { group in
                            header(group.isEmpty ? "Votes" : group, grouped: true).padding(.top, group == groups.first ? 0 : 12)
                            ForEach(page.rows.filter { $0.group == group }) { row($0, grouped: true) }
                        }
                    } else {
                        header("Voting", grouped: false)
                        ForEach(page.rows) { row($0, grouped: false) }
                    }
                }
                .padding(.vertical, 6)
            }
        } else if model.failedAwards.contains(key) {
            Placeholder(text: "Couldn't reach Basketball-Reference")
        } else {
            Placeholder(text: "Loading…", loading: true)
        }
    }

    private func columns(_ grouped: Bool) -> [String] { grouped ? ["Pts", "Share"] : ["1st", "Pts", "Share"] }
    private func widths(_ grouped: Bool) -> [CGFloat] { grouped ? [56, 64] : [48, 56, 64] }

    private func header(_ title: String, grouped: Bool) -> some View {
        SectionHeader(title: title, columns: columns(grouped), widths: widths(grouped))
    }

    private func row(_ vote: Vote, grouped: Bool) -> some View {
        let me = !key.me.isEmpty && vote.athlete == key.me
        return Row(height: 26, selected: me, action: vote.athlete.isEmpty ? nil : { model.openPlayer(vote.athlete) }) {
            HStack(spacing: 8) {
                Text(grouped ? vote.pos : vote.rank)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, alignment: .trailing)
                Text(vote.name).font(.system(size: 13, weight: me ? .semibold : .regular)).lineLimit(1)
                TeamCode(code: vote.team, action: vote.teamID.isEmpty ? nil : { model.openTeam(vote.teamID, season: key.season) })
                Spacer(minLength: 0)
                Cells(values: grouped ? [vote.points, vote.shareText] : [vote.first, vote.points, vote.shareText],
                      widths: widths(grouped), bold: me ? Set(0..<3) : [])
                    .font(.system(size: 12))
                    .foregroundStyle(me ? .primary : .secondary)
            }
        }
    }
}

/// A team's code, which opens its page of that season when there is one.
struct TeamCode: View {
    let code: String
    let action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let label = Text(code).font(.system(size: 10.5)).foregroundStyle(.secondary).underline(hovering && action != nil)
        if let action {
            Button(action: action) { label }.buttonStyle(.plain).onHover { hovering = $0 }
        } else {
            label
        }
    }
}
