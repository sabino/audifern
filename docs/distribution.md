# macOS downloads and releases

[Published downloads](https://github.com/sabino/audifern/releases) are built by
GitHub Actions from the version tag. The app requires macOS 14 or later.
A universal executable contains both Apple Silicon (`arm64`) and Intel
(`x86_64`) slices. There is no privileged installer or background daemon.

## Install

Download the DMG from the release, open it, and drag Audifern to Applications.
The ZIP contains the same app. Open Audifern and allow Bluetooth access.
The app includes the GPL license, third-party notices and the exact source URL.
Advanced UTL authentication material is supplied locally by the device owner;
no credential, vendor APK or fitting module is included in the download.

The initial downloads are **ad hoc signed, not Apple-notarized**. macOS can
block their first launch. After reviewing the project and download, use the
per-app **Open Anyway** option in System Settings → Privacy & Security, as
explained in [Apple's instructions](https://support.apple.com/en-us/102445).
Keep Gatekeeper enabled. Later builds can request Bluetooth authorization again
because ad hoc signing does not establish a persistent Developer ID identity.
A certificate for Apple Development or App Store distribution cannot replace
[Developer ID and notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Each release contains a DMG, application ZIP, `SHA256SUMS` and `build-info.json`.
Verify downloaded files from their containing directory:

```sh
shasum -a 256 -c SHA256SUMS
```

`build-info.json` records the source commit, version, minimum macOS, CPU slices
and signing/notarization status. Checksums detect corruption; they do not make
an ad hoc build Apple-notarized.

## Pull requests and continuous builds

CI runs Swift tests on Apple Silicon and Intel, Python regression tests,
localization auditing and workflow validation. Once those pass, it builds a
universal Release app and verifies both the mounted DMG and extracted ZIP.
Unexpected application payload files, missing resources, invalid signatures and
wrong CPU slices fail packaging. Download the `macos-universal` artifact from
a successful [Actions run](https://github.com/sabino/audifern/actions/workflows/ci.yml).
Artifacts are retained for 14 days and GitHub requires sign-in to download them.
Published release downloads do not have that sign-in requirement.

## Make a release

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in
   `Resources/Info.plist`. Add `docs/releases/VERSION.md` for release-specific
   notes; the generic template is used when that file is absent.
2. Open a pull request and wait for all CI checks, including universal packaging.
3. Merge the tested commit to `main`, then tag that commit. For example:

   ```sh
   git tag v0.6.0
   git push origin v0.6.0
   ```

The Release workflow repeats the shared CI pipeline from the tag, verifies that
the tag matches the application version and belongs to `main`, and uploads its
verified artifacts to a draft. It checks uploaded asset hashes before publishing.
Only the publish job has `contents: write`; PR code receives no release token
or signing secret. Actions are pinned to exact commits.

Prerelease tags such as `v0.7.0-beta.1` must use an application version of
`0.7.0`; they create a GitHub prerelease. A stable tag becomes the latest release.
To retry a failed run, rerun it or dispatch **Release** with its existing tag.
A published release is never replaced by this workflow. Use a new version tag
for changes, and never move a published version tag.

## Reproduce packaging locally

```sh
AUDIFERN_BUILD_ARCH=universal AUDIFERN_SIGN_IDENTITY=- ./scripts/package-release.sh
```

Outputs are under `build/release/`. Packaging mounts a temporary image without
opening Finder, validates it and detaches it. The app's regular runtime is not
launched and no hearing settings are changed. A downloaded source archive can
also be built; its source notice links to the corresponding release tag.

The public Release workflow deliberately uses ad hoc signing. Enabling notarized
releases requires a separate reviewed change and a Developer ID signing setup;
no personal certificate or key is exported into this repository or workflow.
