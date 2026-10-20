#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2;; esac

cd "$project_dir"
swift build -c "$configuration" --jobs "${AUDIFERN_BUILD_JOBS:-${OPEN_COMPANION_BUILD_JOBS:-2}}"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$project_dir/build/Audifern.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Audifern" "$app_dir/Contents/MacOS/Audifern"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
chmod +x "$app_dir/Contents/MacOS/Audifern"
if [[ -f "$project_dir/scripts/make-icon.swift" ]]; then
    if swift "$project_dir/scripts/make-icon.swift" "$project_dir/build/Audifern.iconset" "$project_dir/Sources/Audifern/Resources/BrandMark.png"; then
        iconutil -c icns "$project_dir/build/Audifern.iconset" -o "$app_dir/Contents/Resources/Audifern.icns"
    else
        echo "Icon rendering failed; continuing with the application build." >&2
    fi
fi
for resource_bundle in "$binary_dir"/Audifern_*.bundle; do
    [[ -d "$resource_bundle" ]] || continue
    ditto "$resource_bundle" "$app_dir/Contents/Resources/$(basename "$resource_bundle")"
done
codesign --force --sign "${AUDIFERN_SIGN_IDENTITY:-${OPEN_COMPANION_SIGN_IDENTITY:--}}" --identifier org.audifern.app "$app_dir"
codesign --verify --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
