#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2;; esac
architecture="${AUDIFERN_BUILD_ARCH:-native}"
architecture_args=()
case "$architecture" in
    native) ;;
    arm64|x86_64) architecture_args=(--arch "$architecture");;
    universal) architecture_args=(--arch arm64 --arch x86_64);;
    *) echo "AUDIFERN_BUILD_ARCH must be native, arm64, x86_64 or universal." >&2; exit 2;;
esac

cd "$project_dir"
swift build -c "$configuration" --jobs "${AUDIFERN_BUILD_JOBS:-${OPEN_COMPANION_BUILD_JOBS:-2}}" ${architecture_args[@]+"${architecture_args[@]}"}
binary_dir="$(swift build -c "$configuration" ${architecture_args[@]+"${architecture_args[@]}"} --show-bin-path)"
mkdir -p "$project_dir/build"
staging="$(mktemp -d "$project_dir/build/.app.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app_dir="$staging/Audifern.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Audifern" "$app_dir/Contents/MacOS/Audifern"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
chmod +x "$app_dir/Contents/MacOS/Audifern"
if [[ "$configuration" == release ]]; then strip -S -x "$app_dir/Contents/MacOS/Audifern"; fi
swift "$project_dir/scripts/make-icon.swift" "$staging/Audifern.iconset" "$project_dir/Sources/Audifern/Resources/BrandMark.png"
iconutil -c icns "$staging/Audifern.iconset" -o "$app_dir/Contents/Resources/Audifern.icns"
for resource_bundle in "$binary_dir"/Audifern_*.bundle; do
    [[ -d "$resource_bundle" ]] || continue
    ditto "$resource_bundle" "$app_dir/Contents/Resources/$(basename "$resource_bundle")"
done
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
python3 scripts/release_metadata.py source-notice > "$app_dir/Contents/Resources/SOURCE.txt"
codesign --force --sign "${AUDIFERN_SIGN_IDENTITY:-${OPEN_COMPANION_SIGN_IDENTITY:--}}" --identifier org.audifern.app "$app_dir"
codesign --verify --strict "$app_dir"
python3 scripts/release_metadata.py verify-app "$app_dir" --architecture "$architecture"
rm -rf "$project_dir/build/Audifern.app"
mv "$app_dir" "$project_dir/build/Audifern.app"
printf 'Built %s\n' "$project_dir/build/Audifern.app"
