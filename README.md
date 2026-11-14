# NBA Scores for macOS

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

NBA Scores is a menu bar app for macOS: the games of the day, box scores, player cards, team pages, standings, the NBA Cup and the playoffs, one click away from the menu bar. It is a native port of [omarchy-nba-scores](https://github.com/Onra/omarchy-nba-scores), the same widget for the Omarchy shell.

**Work in progress.** Only the UI mockup exists for now; it shows fake data.

## Mockup

`prototype/` is a throwaway SwiftUI mockup of the main screens: the menu bar item, the scores, a box score, a player card, the standings and the playoff bracket. It needs macOS 26 and Xcode 26 or later.

```sh
cd prototype
swift run
```

A basketball appears in the menu bar. Click it to open the panel, and right-click it for the menu with Quit.

To render every screen to PNG files, in light and dark, without opening anything:

```sh
swift run NBAScoresMock --snapshot /tmp/nba-scores-shots
```

## Plan

- Pure Swift and SwiftUI, no helper process. The data comes from ESPN's public API, which needs no key, plus Basketball-Reference and stats.nba.com for salaries, titles, award voting and the NBA Cup groups.
- The same features as the Omarchy widget: scores with live refresh, box scores, player cards, search, team pages, standings, the NBA Cup and the playoff brackets, award voting, recap links and keyboard control.
- A global hotkey to open the panel, and launch at login.

## License

[MIT](LICENSE)
