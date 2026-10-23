# Privacy in Audifern

Audifern controls hearing aids directly over local Bluetooth. It has no account,
analytics SDK, cloud sync or automatic diagnostic-upload service. Opening an
external help or donation link uses your browser and the linked site's privacy
policy. The About screen does not contact a payment provider until you open its
link. Its QR codes are generated locally.

Contributions are voluntary. The current app does not register a donor, match a
payment to an installation, or send a Mac/hearing-aid identifier to a payment
provider. Copying a receiving address uses the local clipboard. Cryptocurrency
addresses in the contribution catalog are public receiving destinations supplied
by the maintainer. Payment providers and public blockchains have their own data
visibility; the app cannot make a payment anonymous.

## Information the app uses

Optional connection automation stores your chosen hearing aids' Mac-local
peripheral identifiers and sides, a signal threshold and an optional audio
output identifier in local app preferences. These identifiers stay on this Mac;
there is no phone/cloud coordination service or donation association. Signal
measurements are used locally for reconnection. See [connection controls](docs/connections.md).

The app reads nearby/connected device information, available consumer controls,
battery state and the values needed to confirm a requested change. Model,
software, firmware, program names and optional serial fields can be returned by
the devices. Identifiers are hidden by default in the interface; revealing them
does not make them appropriate to include in a public screenshot.

Presets and audiograms are saved locally. Exams can include thresholds, dates,
names and notes you enter, so treat them as private health information. Exam
values are not sent to the aids, converted into fitting gains or uploaded.

## Local storage

Saved data uses `~/Library/Application Support/Audifern/`:

| File | Purpose |
| --- | --- |
| `sound-presets.json` | Named consumer sound adjustments and optional exam references. |
| `audiograms.json` | Exams explicitly saved in the editor. |
| `battery-alerts.json` | Notification preferences and per-device milestone history. |
| `utl-auth.json` | Separately provisioned authentication material for advanced UTL controls. |

Appearance, language and interface preferences use macOS user preferences.
Sensitive saved files use owner-only file permissions and private directories.
They are not encrypted by the application. An existing unreadable library is
preserved rather than silently overwritten.

The optional credential remains outside the application bundle and source
repository. It is not printed or included in session authentication logs.
Do not copy it into an issue, a screenshot, a Git commit or a distributable app.

Demo mode uses synthetic devices and isolated app data. It does not open a
Bluetooth connection or read the regular audiogram library.

## Notifications and background behavior

Battery alerts are local macOS notifications. Permission is requested when you
enable alerts. Notifications may be visible on your display or lock screen
according to macOS settings. Closing the main window keeps existing Bluetooth
connections and monitoring running in the menu bar; quitting stops them.

## Application updates

Opening Updates or choosing Check for Updates fetches public release information
from GitHub. Direct-download installations can optionally check automatically
using Sparkle. Downloads and update checks contact GitHub, which receives normal
network metadata such as the IP address and request headers. No hearing-aid
identifiers, audiograms, credentials or diagnostic logs are sent. Sparkle's
optional system-profile reporting is disabled.

The app reads local package-manager receipts to identify Malt/Homebrew installs;
it does not run their upgrade commands. Managed installations keep their own
update method. Update history requests use an ephemeral session without cookies
or a persistent URL cache. See [app updates](docs/app-updates.md).

## Exports and diagnostics

JSON/XML exam exports contain the exam you choose to export. Consumer-program
snapshots contain program names and current consumer settings; they are not a
complete fitting backup. Save and share these files deliberately.

Developer views and explicitly requested probe files can include device IDs,
characteristic values and local protocol details. Probe files are created only
at the requested new path, with owner-only permissions. Neither diagnostic
output nor a screenshot is guaranteed anonymous simply because an identifier
was hidden in another view. Review every export before sharing it.

The repository's ignored `private/`, `build/` and `.build/` directories are local
development material, not release content. They may contain identifiers,
captures, acquired third-party binaries and signing metadata. Public artwork
and screenshots should come from synthetic demo data.

## Removing data

Use the editor to remove individual saved exams and the presets controls to
remove individual presets. To remove all saved files, quit Audifern first,
then remove its Application Support directory deliberately. This also removes
the locally provisioned advanced credential. Remove exported files separately
where you saved them; deleting the app does not delete those exports.

For a suspected data exposure, follow [SECURITY.md](SECURITY.md). Release
preparation also checks source history using the
[public-source audit procedure](docs/public-release-audit.md).
