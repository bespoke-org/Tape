#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
configuration="${1:-release}"
case "$configuration" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$project_dir/build/Line.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Line" "$app_dir/Contents/MacOS/Line"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string macosx$(xcrun --sdk macosx --show-sdk-version)" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
echo "Built $app_dir"
