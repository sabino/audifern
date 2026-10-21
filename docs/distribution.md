# macOS downloads and releases

[Official releases](https://github.com/sabino/audifern/releases) from 0.6.1 are
Developer ID signed and Apple-notarized. The universal app supports Apple
Silicon and Intel on macOS 14 or later. Version 0.6.2 automates signing and
notarization in GitHub Actions.

## Install and verify

Download the DMG, open it and drag Audifern to Applications. The ZIP contains
the same app. Open Audifern and allow Bluetooth access. No privileged installer
or background daemon is installed.

The app and DMG carry Apple's stapled notarization tickets. The ZIP contains
the stapled app; ZIP files cannot themselves be stapled. Each release includes
SHA256SUMS and build-info.json:

```sh
shasum -a 256 -c SHA256SUMS
xcrun stapler validate Audifern-0.6.2-macos-universal.dmg
```

The manifest records the exact source, CPU slices, deployment target, signing
team, hardened runtime, secure timestamp and verified notarization. The app
includes the GPL license, third-party notices and exact source link. Hearing-aid
authentication is provisioned locally and is excluded from every download.

The original 0.6.0 release and continuous-build artifacts remain ad hoc signed.
After reviewing a development download, use the per-app Open Anyway option in
[Apple's installation instructions](https://support.apple.com/en-us/102445) if
macOS blocks it. Keep Gatekeeper enabled. Use an official notarized release
for the ordinary installation path.

## CI and release trust

PR builds run Swift tests on both CPU architectures, Python regression tests,
translation audits and workflow checks. They build and validate an ad hoc
universal DMG/ZIP without Apple secrets. CI artifacts are retained for 14 days.

A version tag dispatches Release on **main**, rather than letting a tag's
workflow receive Apple secrets. That trusted workflow:

1. Verifies an annotated GPG signature using the checked-in maintainer public
   key and approved fingerprint. The tag's version must match Info.plist and
   its commit must already belong to main.
2. Pins the source commit and tag object, tests and builds that exact commit,
   then verifies the resulting artifact hashes and provenance.
3. Loads Apple credentials only in the **apple-notarization** environment,
   whose deployment policy permits the **main branch only**, with no tag rule.
   The runner imports only the configured Developer ID identity into a
   temporary Keychain.
4. Signs with hardened runtime and secure timestamps, notarizes the app and
   DMG, staples their tickets and checks the extracted copies. It deletes the
   temporary Keychain and credential files before uploading four release files.
5. Uses a fresh Mac runner without Apple credentials to verify both CPU slices,
   signatures, tickets, Gatekeeper, source notices and hashes. Only then can a
   separate job create a draft and publish it after checking remote asset digests.

PRs and tags cannot access the signing environment. Actions are pinned to
specific commits. The signing job has a read-only GitHub token; only publication
gets contents: write. Tag dispatch has actions: write solely to dispatch main.
Published releases are never replaced. Tag changes detected during a run fail
the release; never move a published tag.

Signing and independent verification use tooling from the trusted main workflow, while
the app, version, packaging inputs and source notices stay pinned to the signed
tag. Ticket attachment and validation make up to four attempts for service-response error 68
or request timeouts, with bounded delays. Invalid or revoked tickets fail immediately;
all signature, ticket and Gatekeeper checks remain required. A failure never
publishes a release, and credentials are cleaned even when Apple services fail.

The repository stays public. Reading, cloning or forking it does not reveal
GitHub environment secrets. Fork PRs run only the checks and ad hoc packaging;
approving such a CI run does not grant it Apple credentials.

GitHub rulesets restrict main updates and version-tag creation to **sabino**.
Separate rulesets, with no bypass, require signed main commits, all four checks
from GitHub Actions, and prevent main force-pushes/deletion and version-tag
updates/deletion. This permits fast-forward merges that preserve the
maintainer's original GPG signatures. Changes should still be reviewed in PRs.
Repository settings also enforce full commit SHA pinning and an allowlist of
the exact checkout, download-artifact and upload-artifact Actions in use.
Updating an Action requires reviewing its new commit and updating this
allowlist and the credential-setup validator together. Secret scanning and
push protection are enabled. Release runs require no separate manual approval.

This is a standard hosted CI signing model, with a real trust cost: a compromised
trusted main workflow or runner could misuse or expose the Developer ID private
key. Encryption and cleanup reduce exposure; they do not make such code harmless.
Restrict repository administration and main changes to trusted maintainers.
App Store Connect Team API keys have team-wide reach according to their role,
not access restricted to Audifern. Use a dedicated **Developer-role Team key**
and revoke it if compromised. No personal Apple login password is needed.

## One-time maintainer setup

Use the Developer ID Application identity created for Audifern; do not export
all identities or reuse an Apple Distribution certificate. The public SHA-1
selector is shown by:

```sh
security find-identity -v -p codesigning
```

Create the GitHub environment apple-notarization with custom deployment policies
and exactly one policy: type **branch**, name **main**. Leave tags disallowed.
Do not put Apple credentials in repository-wide secrets.

In [App Store Connect → Users and Access → Integrations](https://appstoreconnect.apple.com/access/integrations/api),
create a **Team API key**, name it Audifern CI Notary, assign Developer access,
and download the private .p8 file once. Record its key ID and issuer UUID
locally. Never paste the private key into an issue, PR or chat.

After reviewing and authorizing the credential transfer, run:

```sh
python3 scripts/configure-ci-signing.py \
  --identity YOUR_DEVELOPER_ID_SHA1 --team YOUR_TEAM_ID \
  --key /private/path/AuthKey_KEYID.p8 --key-id YOUR_KEY_ID \
  --issuer YOUR_ISSUER_UUID --upload-credentials
```

The tool refuses a broad environment policy or weakened repository rules,
checks the signed-in GitHub account, validates the API login, and
exports **only the selected Developer ID identity**, with a random PKCS#12
password. macOS may ask for Keychain export authorization. It uploads values
through stdin to gh, which encrypts environment secrets, and removes temporary
exports. It never requests the Mac login password or logs credential values.
The private .p8 download remains at your chosen local path.

Environment secrets:

| Name | Value |
| --- | --- |
| AUDIFERN_CERTIFICATE_P12 | Base64 of that one password-protected PKCS#12 identity |
| AUDIFERN_CERTIFICATE_PASSWORD | Random password for that export |
| AUDIFERN_NOTARY_KEY | Dedicated Team API private key |
| AUDIFERN_NOTARY_KEY_ID | API key ID |
| AUDIFERN_NOTARY_ISSUER | Team issuer UUID |

Public repository variables AUDIFERN_SIGN_IDENTITY and AUDIFERN_TEAM_ID pin the
expected certificate fingerprint and signing team. Neither is a private key.
The user's GPG private key stays local: CI verifies signatures using only the
public key in .github/release-signing-key.asc.

See [GitHub's signing guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
and [Apple's API key guidance](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api).

## Make a release

1. Update CFBundleShortVersionString and increment CFBundleVersion in
   Resources/Info.plist; add docs/releases/VERSION.md.
2. Open a PR, pass every CI check and merge to main while preserving signatures.
3. Create a maintainer-signed tag on that tested commit:

   ```sh
   git tag -s v0.6.2 -m "Audifern 0.6.2"
   git push origin v0.6.2
   ```

The tag dispatches trusted main automatically. No local notarization or draft
upload is needed. Follow the [Release workflow](https://github.com/sabino/audifern/actions/workflows/release.yml).
A prerelease tag such as v0.7.0-beta.1 requires app version 0.7.0 and publishes
a GitHub prerelease. A stable tag becomes the latest release.

To retry an unpublished release or test credentials without publishing:

```sh
gh workflow run release.yml --ref main -f tag=v0.6.2 -f publish=true
gh workflow run release.yml --ref main -f tag=v0.6.1 -f publish=false
```

The second command signs, notarizes and uploads verified Actions artifacts;
it never replaces the published release. A new hosted runner does not reuse
a previous runner's private notarization state. Wait for a pending run before
retrying to avoid duplicate submissions.

## Local fallback and development packaging

Local notarization still works with a Keychain profile:

```sh
xcrun notarytool store-credentials audifern-notary \
  --apple-id YOUR_APPLE_ACCOUNT --team-id YOUR_TEAM_ID
AUDIFERN_BUILD_ARCH=universal ./scripts/build-app.sh release
python3 scripts/notarize-release.py --tag v0.6.2 \
  --identity YOUR_DEVELOPER_ID_SHA1 --profile audifern-notary
```

Enter an app-specific password at the secure prompt, never in a shell argument.
For a local timeout, rerun the helper to resume unchanged submission IDs.
Logs and state stay under ignored build/notarization. Use --rebuild-packages
only after an intentional packaging change.

For ad hoc development downloads without any Apple credentials:

```sh
AUDIFERN_BUILD_ARCH=universal AUDIFERN_SIGN_IDENTITY=- ./scripts/package-release.sh
```

Outputs are under build/release. Packaging mounts temporary images without
opening Finder, verifies and detaches them. It never launches the app or opens
a hearing-aid connection.
