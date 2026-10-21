# macOS downloads and releases

[Official releases](https://github.com/sabino/audifern/releases) from 0.6.1 are
signed with Developer ID Application and notarized by Apple. The universal app
supports Apple Silicon and Intel on macOS 14 or later. No privileged installer
or background daemon is installed.

## Install and verify

Download the DMG, open it and drag Audifern to Applications. The ZIP contains
the same app. Open Audifern and allow Bluetooth access.

Both the app and DMG carry Apple's stapled notarization tickets. The ZIP
contains the stapled app; ZIP files cannot themselves be stapled. Developer ID
signing and notarization are separate from the maintainer's GPG signatures on
Git commits and version tags.

Each release includes the DMG, ZIP, SHA256SUMS and build-info.json. From their
containing directory:

```sh
shasum -a 256 -c SHA256SUMS
xcrun stapler validate Audifern-0.6.1-macos-universal.dmg
```

The manifest records the exact source commit, CPU slices, deployment target,
signing team, hardened runtime, secure timestamp and verified notarization.
The app includes the GPL license, third-party notices and exact source link.
Advanced UTL authentication is supplied locally by the owner and is excluded.

The original **0.6.0** release and continuous-build artifacts remain ad hoc
signed. macOS may block their initial launch; after reviewing the download,
use the per-app **Open Anyway** option described in
[Apple's instructions](https://support.apple.com/en-us/102445). Keep Gatekeeper
enabled. Use a notarized release for the ordinary installation path.

## Pull requests and continuous builds

CI runs Swift tests on Apple Silicon and Intel, Python regression tests,
localization auditing and workflow validation. It then builds an ad hoc signed
universal Release app and verifies its mounted DMG and extracted ZIP.
Unexpected payload files, missing resources, invalid signatures and wrong
CPU slices fail packaging. PRs receive no release token or Apple credentials.

Download the macos-universal artifact from a successful
[CI run](https://github.com/sabino/audifern/actions/workflows/ci.yml).
Artifacts are retained for 14 days and require GitHub sign-in. Public release
downloads do not require sign-in. CI artifacts are development snapshots,
separate from notarized official downloads.

## One-time maintainer setup

Use a paid Apple Developer team and create a **Developer ID Application**
certificate in Xcode's Apple Accounts settings. Apple Development and Apple
Distribution certificates cannot replace it for downloads outside the store.
Find its SHA-1 signing fingerprint:

```sh
security find-identity -v -p codesigning
```

Store notarization credentials in the local Keychain. The following command
prompts securely for an app-specific password; do not put it in a shell
argument, source file or chat:

```sh
xcrun notarytool store-credentials audifern-notary \
  --apple-id YOUR_APPLE_ACCOUNT --team-id YOUR_TEAM_ID
```

Alternatively, the helper accepts a locally stored notarization API key through
AUDIFERN_NOTARY_KEY_PATH and AUDIFERN_NOTARY_KEY_ID. Set AUDIFERN_NOTARY_ISSUER
for a team API key and omit it for an individual API key. Do not combine API
credentials with a Keychain profile. Do not export private credentials into
the repository or GitHub Actions.

Configure the repository Actions **variable** AUDIFERN_TEAM_ID with the expected
public ten-character signing team ID. This identifier is public in every
signed app; it is not a private key or secret. Release verification rejects
downloads signed by another team.

See Apple's
[Developer ID certificate guide](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
and [notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Make a release

1. Update CFBundleShortVersionString and increment CFBundleVersion in
   Resources/Info.plist. Add docs/releases/VERSION.md.
2. Open a PR, pass every CI check and merge to main, preserving verified Git
   signatures. Work from a clean checkout of the tested commit.
3. Build and notarize locally. Replace the fingerprint below with the
   Developer ID Application identity from the one-time setup:

   ```sh
   AUDIFERN_BUILD_ARCH=universal ./scripts/build-app.sh release
   python3 scripts/notarize-release.py --tag v0.6.1 \
     --identity YOUR_DEVELOPER_ID_SHA1 --profile audifern-notary
   ```

   The helper signs with hardened runtime and secure timestamps, submits the
   app to Apple, waits for acceptance, staples the app, packages it, signs and
   notarizes the DMG, staples it, then verifies both extracted copies and
   Gatekeeper acceptance. No hearing-aid connection is opened. Failed or
   pending submissions cannot be published as accepted downloads.

   Apple can queue a submission for some time. Rerun the same command after a
   timeout: unchanged uploads retain their submission ID instead of submitting
   duplicates. Private request logs and resumable state stay under ignored
   build/notarization. Existing packages must match the checkout and checksums;
   use --rebuild-packages only after an intentional packaging change.
4. Sign and push the version tag, then stage the verified downloads in a draft:

   ```sh
   git tag -s v0.6.1 -m "Audifern 0.6.1"
   git push origin v0.6.1
   gh release create v0.6.1 --verify-tag --draft --title "Audifern 0.6.1" \
     --notes-file docs/releases/0.6.1.md
   gh release upload v0.6.1 build/release/*.dmg build/release/*.zip \
     build/release/SHA256SUMS build/release/build-info.json
   gh workflow run release.yml --ref main -f tag=v0.6.1
   ```

The tag starts the shared CI pipeline. Without a complete notarized draft, it
checks the build and reports that preparation is needed, leaving publication
pending. Dispatch Release after staging the assets. The workflow reruns the
tests from the tag, confirms it belongs to main, downloads the draft on a fresh
Mac runner and independently checks Developer ID, the expected signing team,
both architecture slices, source provenance, checksums, stapled tickets and
Gatekeeper acceptance. Only then does the publish job write release assets.
It rechecks uploaded digests using the release ID before publishing. GitHub
requires push-level token access to read draft releases, so draft discovery
and verification also receive contents: write. Those jobs run only in the
tag/manual Release workflow; PR builds keep read-only permissions.

This design keeps the Apple private key and notarization login in the local
Keychain. GitHub runs verification and publication; creating a new notarized
build still requires the maintainer's signing Mac.

Prerelease tags such as v0.7.0-beta.1 require application version 0.7.0 and
become GitHub prereleases. A stable tag becomes the latest release.
To retry, dispatch Release from main with the existing tag. A published release
is never overwritten and a published version tag must never be moved.

## Reproduce packaging locally

```sh
AUDIFERN_BUILD_ARCH=universal AUDIFERN_SIGN_IDENTITY=- ./scripts/package-release.sh
```

This produces ad hoc development downloads under build/release, without Apple
credentials. Packaging mounts a temporary image without opening Finder and
detaches it after verification. The app is never launched by these scripts.
A downloaded source archive can also be built; its source notice links to the
corresponding release tag.
