# NBA Scores for macOS

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

NBA Scores is a menu bar app for macOS: the games of the day, box scores, player cards, team pages, standings, the NBA Cup and the playoffs, one click away from the menu bar. It is a native port of [omarchy-nba-scores](https://github.com/Onra/omarchy-nba-scores), the same widget for the Omarchy shell.

**Work in progress.** What works today: the scores of every game day with live refresh, box scores, recap links, the regular-season standings, player cards, team pages and the search. The NBA Cup, the playoffs and award voting are still to come.

The data comes from ESPN's public API, which needs no key. The salaries of the seasons to come and the list of NBA champions come from Basketball-Reference.

## Install

It needs macOS 26 and Xcode 26 or later.

```sh
cd app
./build.sh install
```

This builds `NBA Scores.app`, copies it to `/Applications` and launches it. A basketball appears in the menu bar, with `● 3` next to it while three games are live. The app starts at login; the right-click menu turns that off.

## Usage

Click the basketball to open the panel, and right-click it for Refresh, Launch at Login and Quit.

| Key | Action |
| --- | --- |
| `←` `→` | Previous or next game day; in a box score, previous or next game; in the standings and on a team page, previous or next season |
| `↑` `↓` | Move through the games, or the search results |
| `Enter` | Open the box score of the selected game, or the selected search result |
| `Esc` | Back, or close the panel |
| `y` | Open the recap of the selected game or of the open box score |
| `/` or `⌘F` | Search teams and players, past and present |
| `r` | Refresh |
| `t` | Back to today |
| `b` | Scores |
| `s` | Standings |

Team logos and names open the team's page everywhere, and a player's name in a box score or a roster opens his card: bio, averages against his career, salary season by season with the seasons to come, titles and awards, and his career by season. The search also knows the old names of today's franchises: `Sonics` finds the Thunder.

A day is a US Eastern date, as for the NBA: a game that tips off at 01:30 in Paris belongs to the day before. Live games refresh every 30 seconds, and everything else every 5 minutes.

## Development

```sh
cd app
swift test
swift run NBAScores --snapshot /tmp/nba-scores-shots
```

The second command fetches live data and renders every screen to PNG files, in light and dark, without opening anything.

`prototype/` is the throwaway SwiftUI mockup the design was approved on; it shows fake data and will go once the app covers every screen.

## Plan

- Pure Swift and SwiftUI, no helper process. The data comes from ESPN's public API, which needs no key, plus Basketball-Reference and stats.nba.com for salaries, titles, award voting and the NBA Cup groups.
- The same features as the Omarchy widget: scores with live refresh, box scores, player cards, search, team pages, standings, the NBA Cup and the playoff brackets, award voting, recap links and keyboard control.
- A global hotkey to open the panel, and launch at login.

## License

[MIT](LICENSE)
