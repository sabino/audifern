#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2;; esac

cd "$project_dir"
swift build -c "$configuration" --jobs "${OPEN_COMPANION_BUILD_JOBS:-2}"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$project_dir/build/Open Companion.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/OpenCompanion" "$app_dir/Contents/MacOS/OpenCompanion"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
chmod +x "$app_dir/Contents/MacOS/OpenCompanion"
if [[ -f "$project_dir/scripts/make-icon.swift" ]]; then
    if swift "$project_dir/scripts/make-icon.swift" "$project_dir/build/OpenCompanion.iconset"; then
        iconutil -c icns "$project_dir/build/OpenCompanion.iconset" -o "$app_dir/Contents/Resources/OpenCompanion.icns"
    else
        echo "Icon rendering failed; continuing with the application build." >&2
    fi
fi
codesign --force --sign - --identifier org.audifern.app "$app_dir"
codesign --verify --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
