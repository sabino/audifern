# Technical and device reference

These documents explain the implementation and its evidence. For everyday
setup and controls, use the [user guide](user-guide.md) or in-app Help.

## Sound controls

- [Direct BLE controls](legacy-protocol.md) and [UTL transport and authentication](managed-protocol.md).
- [Consumer EQ and presets](advanced-controls.md), [SpeechBooster](speech-booster.md) and [source/tinnitus controls](tinnitus-controls.md).
- [Program data and fitting boundaries](program-data.md).
- [Battery telemetry](battery-telemetry.md) and [battery alerts](battery-alerts.md).
- [Identification](device-identification.md), [device metadata](device-metadata.md) and [firmware investigation](device-research.md).

## Records and fitting research

- [Audiogram records and export](audiogram.md).
- [Local fitting plans and backups](fitting-backups.md).
- [Noah investigation](noah-investigation.md) and [Genie feature map](genie-feature-map.md).
- [Saved acoustics](saved-acoustics.md), [preferences](saved-preferences.md) and [controls](saved-control-wire-evidence.md).

## Verification and distribution

- [Hardware verification](hardware-verification.md) distinguishes audible
  confirmation, device readback, synthetic tests and remaining gaps.
- [Quick-access validation](quick-access-validation.md) records menu-bar,
  widget, Control Center and Help checks.
- [Public-source audit](public-release-audit.md), [privacy](../PRIVACY.md),
  [security](../SECURITY.md) and [third-party notices](../THIRD_PARTY_NOTICES.md).
- [Release signing and notarization](distribution.md).

Clinical fitting writes, audiogram-to-gain conversion, firmware installation
and complete fitting restore are not implemented. Consumer presets and readable
checkpoints do not replace a clinical fitting or a verified restore mechanism.
