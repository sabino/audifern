#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
release_tag="${1:-}"
release_version="$(python3 scripts/release_metadata.py version --tag "$release_tag")"
export AUDIFERN_BUILD_ARCH="${AUDIFERN_BUILD_ARCH:-universal}"
architecture="$AUDIFERN_BUILD_ARCH"
[[ "$architecture" != native ]] || architecture="$(uname -m)"
if [[ -n "${AUDIFERN_PACKAGE_APP:-}" ]]; then
    app="$AUDIFERN_PACKAGE_APP"
    python3 scripts/release_metadata.py verify-app "$app" --architecture "$AUDIFERN_BUILD_ARCH"
else
    ./scripts/build-app.sh release
    app="$project_dir/build/Audifern.app"
fi
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
mkdir -p "$staging/image"
ditto "$app" "$staging/image/Audifern.app"
ln -s /Applications "$staging/image/Applications"
cp LICENSE "$staging/image/LICENSE.txt"
cat > "$staging/image/Install.txt" <<'INSTALL'
Drag Audifern to Applications, then open it and allow Bluetooth access.

Requires macOS 14 or later. The universal build supports Apple Silicon and Intel.
Source, license, setup and compatibility notes:
https://github.com/sabino/audifern

Advanced UTL controls need compatible authentication material provisioned
locally by the device owner. Credentials and vendor software are not included.
INSTALL
manifest_options=()
if [[ "${AUDIFERN_PACKAGE_NOTARIZED:-0}" == 1 ]]; then
    python3 scripts/release_metadata.py manifest "$app" --architecture "$AUDIFERN_BUILD_ARCH" --notarized > /dev/null
    manifest_options=(--notarized)
    printf '\nSigned with Developer ID and notarized by Apple.\n' >> "$staging/image/Install.txt"
else
    printf '\nThis build is ad hoc signed and is not Apple-notarized.\nIf macOS blocks it, review the project and use the per-app Open Anyway\noption in Privacy & Security. Keep Gatekeeper enabled.\n' >> "$staging/image/Install.txt"
fi
rm -f "$output/$prefix.zip" "$output/$prefix.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$prefix.zip"
hdiutil create -quiet -volname "Audifern $release_version" -srcfolder "$staging/image" -fs HFS+ -format UDZO "$output/$prefix.dmg"
if [[ "${AUDIFERN_PACKAGE_NOTARIZED:-0}" == 1 ]]; then
    [[ -n "${AUDIFERN_SIGN_IDENTITY:-}" && "$AUDIFERN_SIGN_IDENTITY" != - ]]
    codesign --force --timestamp --sign "$AUDIFERN_SIGN_IDENTITY" "$output/$prefix.dmg"
fi
hdiutil verify -quiet "$output/$prefix.dmg"
mkdir -p "$staging/mounted" "$staging/unzipped"
mounted=true
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$staging/mounted" "$output/$prefix.dmg"
python3 scripts/release_metadata.py verify-app "$staging/mounted/Audifern.app" --architecture "$AUDIFERN_BUILD_ARCH"
if [[ "${AUDIFERN_PACKAGE_NOTARIZED:-0}" == 1 ]]; then
    python3 scripts/release_metadata.py manifest "$staging/mounted/Audifern.app" --notarized > /dev/null
fi
[[ "$(readlink "$staging/mounted/Applications")" == /Applications ]]
hdiutil detach "$staging/mounted" -quiet
mounted=false
ditto -x -k "$output/$prefix.zip" "$staging/unzipped"
python3 scripts/release_metadata.py verify-app "$staging/unzipped/Audifern.app" --architecture "$AUDIFERN_BUILD_ARCH"
if [[ "${AUDIFERN_PACKAGE_NOTARIZED:-0}" == 1 ]]; then
    python3 scripts/release_metadata.py manifest "$staging/unzipped/Audifern.app" --notarized > /dev/null
fi
python3 scripts/release_metadata.py manifest "$app" --architecture "$AUDIFERN_BUILD_ARCH" --tag "$release_tag" ${manifest_options[@]+"${manifest_options[@]}"} > "$output/build-info.json"
(cd "$output" && shasum -a 256 "$prefix.dmg" "$prefix.zip" build-info.json > SHA256SUMS)
printf 'Verified downloads: %s\n' "$output"
