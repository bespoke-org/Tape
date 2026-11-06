#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
app_dir="$project_dir/build/package/Tape.app"
dist_dir="$project_dir/build/dist"
dmg_root="$(mktemp -d "${TMPDIR:-/tmp}/tape-dmg.XXXXXX")"
trap 'rm -rf "$dmg_root"' EXIT

LINE_APP_OUTPUT="$app_dir" ./scripts/build-app.sh release --universal
./scripts/verify-app.sh "$app_dir"
lipo "$app_dir/Contents/MacOS/Tape" -verify_arch arm64 x86_64

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
mkdir -p "$dist_dir"
ditto -c -k --keepParent "$app_dir" "$dist_dir/Tape-$version.zip"
ditto "$app_dir" "$dmg_root/Tape.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create -volname Tape -srcfolder "$dmg_root" -ov -format UDZO \
    "$dist_dir/Tape-$version.dmg"

echo "Packaged $dist_dir/Tape-$version.dmg and $dist_dir/Tape-$version.zip"
