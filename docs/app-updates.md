# App updates

Open **Audifern → Check for Updates…**, or **Settings → Updates**, to check the
latest release and read its changelog. The menu-bar settings menu provides the
same destination. Release history is fetched from GitHub when requested; no
hearing-aid data, account details or identifiers are sent.

An app copied from the DMG uses Sparkle for updates. Checks are optional, and
installing an update lets you choose when to reopen Audifern. Both the update
feed and archive have Ed25519 signatures, and the app remains Developer ID signed
and notarized. Archives are verified before extraction.

Malt and Homebrew installations keep their package manager in charge. The app
shows the matching commands and does not replace the managed installation.
For Malt, refresh its pinned tap with `mt tap --refresh sabino/tap`, then run
`mt upgrade --cask audifern`. For Homebrew, use `brew upgrade --cask audifern`.
If ownership cannot be identified, the in-app installer stays disabled.

Versions before 0.9.0 need one normal DMG or package-manager upgrade to gain
the new Updates screen. App updates never install hearing-aid firmware.

## Release setup

Sparkle 2.10.0 is pinned in `Package.swift` and `Package.resolved`. Its exact
framework files, internal symlinks, resource hashes and signing-tool hashes are
recorded in `scripts/sparkle-payload.json`. The packaging checks reject extra
files, changed resources and links outside the framework. Nested updater code
is signed with the app's Developer ID and checked before notarization.

The public update key is in `Resources/Info.plist`. Keep its private seed outside
the repository. The trusted main release workflow needs
`AUDIFERN_UPDATE_PRIVATE_KEY` in the main-only `apple-notarization` environment.
PR jobs never receive it. The seed goes to Sparkle's tool through standard input,
never a command-line argument. Apple credentials are cleaned up before update
feed signing, and the update seed is removed from subprocess environments.

`scripts/sparkle_appcast.py` generates the signed feed after notarization. A
fresh Mac checks both signatures using only the embedded public key and CryptoKit,
alongside the required Apple-ticket, Gatekeeper and source-provenance checks.
The feed is included in `SHA256SUMS` and uploaded as `appcast.xml` to each immutable
release. The installed app reads the latest release's feed over HTTPS.

Before publishing the first release with a feed, update the tap verifier to
accept the additional checksummed asset. Do not move an existing release tag or
replace a published release to add updater support.
