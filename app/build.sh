#!/bin/zsh
# Builds "NBA Scores.app".
#   ./build.sh           build into app/build/
#   ./build.sh install   also copy to /Applications and relaunch
set -euo pipefail
cd "${0:A:h}"

APP="build/NBA Scores.app"
swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Support/Info.plist "$APP/Contents/"
cp .build/release/NBAScores "$APP/Contents/MacOS/"
# Ad-hoc signature: fine for a personal app.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == install ]]; then
  pkill -x NBAScores || true
  rm -rf "/Applications/NBA Scores.app"
  cp -R "$APP" /Applications/
  open "/Applications/NBA Scores.app"
  echo "Installed and launched /Applications/NBA Scores.app"
fi
