#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
release_tag="${1:-}"
release_version="$(python3 scripts/release_metadata.py version --tag "$release_tag")"
export AUDIFERN_BUILD_ARCH="${AUDIFERN_BUILD_ARCH:-universal}"
architecture="$AUDIFERN_BUILD_ARCH"
[[ "$architecture" != native ]] || architecture="$(uname -m)"
./scripts/build-app.sh release
output="$project_dir/build/release"
rm -rf "$output"
mkdir -p "$output"
prefix="Audifern-$release_version-macos-$architecture"
staging="$(mktemp -d "$project_dir/build/.package.XXXXXX")"
mounted=false
cleanup() {
    local result=$?
    if [[ "$mounted" == true ]]; then
        if ! hdiutil detach "$staging/mounted" -quiet; then
            echo "Unable to detach the verification image; preserving staging." >&2
            exit 1
        fi
    fi
    rm -rf "$staging"
    exit "$result"
}
trap cleanup EXIT
app="$project_dir/build/Audifern.app"
mkdir -p "$staging/image"
ditto "$app" "$staging/image/Audifern.app"
ln -s /Applications "$staging/image/Applications"
cp LICENSE "$staging/image/LICENSE.txt"
cat > "$staging/image/Install.txt" <<'INSTALL'
Drag Audifern to Applications, then open it and allow Bluetooth access.

Requires macOS 14 or later. The universal build supports Apple Silicon and Intel.
This initial public build is ad hoc signed and is not Apple-notarized.
If macOS blocks it, use the per-app Open Anyway option in Privacy & Security
after reviewing the project and download. Do not disable Gatekeeper globally.

Source, license, setup and compatibility notes:
https://github.com/sabino/audifern

Advanced UTL controls need compatible authentication material provisioned
locally by the device owner. Credentials and vendor software are not included.
INSTALL
rm -f "$output/$prefix.zip" "$output/$prefix.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$prefix.zip"
hdiutil create -quiet -volname "Audifern $release_version" -srcfolder "$staging/image" -fs HFS+ -format UDZO "$output/$prefix.dmg"
hdiutil verify -quiet "$output/$prefix.dmg"
mkdir -p "$staging/mounted" "$staging/unzipped"
mounted=true
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$staging/mounted" "$output/$prefix.dmg"
python3 scripts/release_metadata.py verify-app "$staging/mounted/Audifern.app" --architecture "$AUDIFERN_BUILD_ARCH"
[[ "$(readlink "$staging/mounted/Applications")" == /Applications ]]
hdiutil detach "$staging/mounted" -quiet
mounted=false
ditto -x -k "$output/$prefix.zip" "$staging/unzipped"
python3 scripts/release_metadata.py verify-app "$staging/unzipped/Audifern.app" --architecture "$AUDIFERN_BUILD_ARCH"
python3 scripts/release_metadata.py manifest "$app" --architecture "$AUDIFERN_BUILD_ARCH" --tag "$release_tag" > "$output/build-info.json"
(cd "$output" && shasum -a 256 "$prefix.dmg" "$prefix.zip" build-info.json > SHA256SUMS)
printf 'Verified downloads: %s\n' "$output"
