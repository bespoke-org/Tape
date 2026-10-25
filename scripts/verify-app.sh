#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="${1:-$project_dir/build/Tape.app}"
plist="$app_dir/Contents/Info.plist"

plutil -lint "$plist"
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
icon=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")
[[ "$icon" == *.icns ]] || icon="$icon.icns"
test -n "$executable"
test -x "$app_dir/Contents/MacOS/$executable"
test -s "$app_dir/Contents/Resources/$icon"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$plist")" = APPL
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" = 26.0
codesign --verify --deep --strict --verbose=2 "$app_dir"
echo "Verified $app_dir"
