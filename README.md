# Audifern

<img src="branding/mark.svg" width="64" alt="Audifern logo">

**Your hearing aids, a little closer to your Mac.**

Audifern is a free, open-source macOS app for controlling compatible Oticon
hearing aids over Bluetooth. No account, cloud service or analytics.

[Download](https://github.com/sabino/audifern/releases/latest) ·
[Website](https://audifern.sabino.chatgpt.site/) ·
[User guide](docs/user-guide.md) ·
[Documentation](docs/README.md)

![Audifern Sound: hearing aids, volume, program shortcuts and equalizers in a compact window](docs/images/audifern-light.png)

*The native app with sample devices. [Dark appearance](docs/images/audifern-dark.png)
and [menu-bar controls](docs/images/audifern-menu-bar.png).*

## Install

Requires **macOS 14 or later**, on Apple Silicon or Intel.
Release downloads are Developer ID signed and Apple-notarized.

[Download the latest DMG](https://github.com/sabino/audifern/releases/latest),
open it, and drag Audifern to Applications.

Or install with **Malt**:

```sh
mt install --cask sabino/tap/audifern
```

**Homebrew**: `brew install --cask sabino/tap/audifern`.

For release notes and the correct update method, open **Settings → Updates**.

## What you can do

- Adjust volume and mute for each ear, or both together.
- Switch existing fitted programs and use supported SpeechBooster and EQ controls.
- See battery levels, estimated time left and optional battery alerts.
- Keep controls in the menu bar or desktop widgets. Control Center requires macOS 26.
- Save local sound presets and keep your audiogram records on your Mac.

Extra controls depend on your hearing aids and fitted programs. Advanced
features also need compatible authentication configured locally; credentials
are not included. See [setup and compatibility](docs/user-guide.md#connect-your-hearing-aids).

## Help and compatibility

Choose **Help → Audifern Help** inside the app, or search the Mac's Help menu
for a feature such as “battery”. The [user guide](docs/user-guide.md) covers setup,
everyday controls and common questions.

Currently tested with one pair of **Oticon Intent 3** hearing aids; other models
are unverified. Bluetooth controls and Mac audio routing are separate.
Audifern does not program clinical fittings or install firmware.

## Contribute

Found a problem or have an idea? [Open an issue](https://github.com/sabino/audifern/issues).
For code contributions, start with [Contributing](CONTRIBUTING.md).

Made by [sabino](https://github.com/sabino) ·
[Support the project](docs/contributions.md) ·
[Privacy](PRIVACY.md) · [Security](SECURITY.md) · [GPLv3](LICENSE)

Audifern is independent and is not affiliated with or endorsed by Oticon or Demant.
