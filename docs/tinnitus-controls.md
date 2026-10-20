# Fitted tinnitus sound and streaming volume

The shipped Companion SDK directly supports separate microphone, streaming and
tinnitus volume/mute controls. An exposed tinnitus **range** does not show that
tinnitus sound generation is fitted or enabled in the current program. The
official app uses the active program's tinnitus flag to make that source
available.

This pass recovered consumer controls from Companion 1.8.0 (617548). It did not
send Bluetooth commands, change hearing settings, activate an unfitted therapy,
or run a target application. The app UI and backend implementation are separate
from this static research.

## Exact GATT mapping

The service is `56772EAF-2153-4F74-ACF3-4368D99FBF5A`.

| Control | Characteristic | Reported range |
| --- | --- | --- |
| Tinnitus volume/mute | `E5892EBE-97D0-4F97-8F8E-CB85D16A4CC1` | Signed bytes 4/5 of VolumeRanges |
| Streaming volume/mute | `50632720-4C0F-4BC4-960A-2404BDFDFBCA` | Signed bytes 2/3 of VolumeRanges |
| Microphone volume/mute | `1454E9D6-F658-4190-8589-22AA9E3021EB` | Signed bytes 0/1 of VolumeRanges |
| VolumeRanges | `58BBCCC5-5A57-4E00-98D5-18C6A0408DFD` | At least six bytes; pairs are minimum/maximum |

`WdhHiServiceClient` maps each source to its characteristic, and uses the same
`VolumeCommandData` for all three. The setter writes exactly two bytes:

```text
byte 0 = signed Int8 volume step, encoded as its byte bit pattern
byte 1 = 0 when muted, 1 when unmuted
```

Writes use response acknowledgement by default. Reads use the same two-field
layout; the SDK treats a zero second byte as muted. Open Companion's existing
strict volume decoder accepts only the established 0/1 flag values. Notification
callbacks decode the same characteristic data and retain its volume source.
No UTL operation ID or transaction wrapper belongs inside this direct GATT
payload.

There is no separate therapy-enable flag in this volume payload. Changing volume
must preserve the latest confirmed mute value, and changing mute must preserve
the latest confirmed volume. The official `GattVolumeDispatcherStrategy`
supplies the unchanged field from its current source state, and `VolumeManager`
bounds requests to the source's reported range. Refresh/readback and serialized
updates avoid treating an old paired value or accepted write as current state.

Values are reported device steps. This recovery does not establish a calibrated
sound-pressure level or a universal dB-per-step conversion.

## Program eligibility

Legacy program metadata is category, UTF-8 name length/name, then flags. Bit 0
of the flag byte after the name means `Tinnitus`; bit 1 means `Boostable`.
`GetProgramsGattCommand` maps that bit to `HearingAidProgram.IsTinnitus`.

The official `VolumeSourcesMonitor.GenerateAvailableSources` returns
`[Tinnitus, Main]` only when the selected program is tinnitus-enabled.
`VolumeSourceTracker.GetVolumeSourceForProgram` uses that same condition. Thus:

- Gate tinnitus writes on a current, matching active program with tinnitus=true,
  a valid reported tinnitus range, readable/writable characteristic properties,
  and a current paired volume/mute state.
- A missing/unknown program, an ordinary program, or a range alone must not
  authorize tinnitus volume/unmute writes.
- Do not switch programs, change modulation, initialize a sound generator or
  restore saved therapy settings automatically to make a control available.
- Keep ordinary disconnected/busy/program-changing protections. The official
  slider state also accounts for connection readiness, charging and program
  desynchronization.

The first two gates follow the actual source selection; requiring fresh state,
characteristic properties and no pending change is Open Companion's explicit
implementation guard. The UI should make fitted tinnitus sound distinct from
microphone/streaming gain and explain that its allowed level/duration comes from
the user's hearing-care setup. It must not promise to create or clinically fit
a tinnitus program.

## Streaming overall volume

This separate source uses the same payload but its own characteristic/range.
It is not the streaming equalizer and is not standard Bluetooth VCS or the
phone/Mac media-volume control.

The official program-category mapping recognizes these raw legacy categories:

| Raw category | SDK category |
| --- | --- |
| 10, 201 | Television streamer |
| 11, 255 | Generic streamer |

Only those mapped categories make `HearingAidProgram.SupportsStreaming()` true.
Raw category 6 (`Television`), 8 (`MixingStreamers`) and 9 (`TelecoilStreamer`)
default to General in that mapper; their names do not establish source support.
Tinnitus takes precedence over streaming in the official source selector.

The source-availability check does not require audio to be playing already.
`VolumeSliderStateMonitor` temporarily marks the streaming slider Loading when
the streaming state reports loading, in addition to its connection/data-ready
checks. Any stricter active-stream requirement would be an app policy rather
than a recovered wire requirement.

## Other recovered tinnitus controls, kept separate

The SDK has a modulation control and an eight-band tinnitus attenuation control,
but neither is needed to expose fitted tinnitus volume/mute.

- Modulation uses the first two bytes of
  `9215A295-B813-483F-9F85-B700D0B7BC75`, a shared characteristic also used by
  legacy Speech Booster fields. The official setter reads the full current
  value, changes only those two bytes and preserves the rest. Its UI requires
  both a tinnitus program and changeable modulation; Ocean is treated as
  non-changeable by this path. Exposing arbitrary modulation choices from a
  volume range would skip those checks.
- Tinnitus attenuation is the first eight bytes of
  `60415E72-C345-417A-BB2B-BBBA95B2C9A3`, before streaming gains. The legacy
  helper checks support by length and preserves the remaining bytes. This pass
  has not established usable per-band limits/units or a clinical fitting rule,
  so the volume feature does not expose those raw bytes as an advanced treatment
  editor. Existing streaming EQ must continue preserving them.

## Evidence and validation boundary

| Assembly | SHA-256 / MVID |
| --- | --- |
| LegacyRemoteControlManager | `d5b0f7a2c3ed17bf8b4e801eedc1aaa290a19e59f02c837689dea8933bb53288` / `727bc5cb-0147-49d5-ad68-384b85758e1d` |
| Hal.Wrapper | `e13600d24d5f44d6f173be4d1df3822b294a7b2341c986ea03dbffe4b00dcfd8` / `0ca344f6-16d9-4f18-9cc2-80c7ab5a6137` |
| RemoteControl.Core | `f79ea02f7f221163248f671afb99ea87fefb51373dec41e4f45bf65d7374a611` / `c082658b-4f6a-4226-880c-2f9fc8dc0540` |

| REA evidence | Scope |
| --- | --- |
| `ev_f297b86ab7ca7a82dbcf0e21ca9f0276c26563f92f833bef0f272933cc9005bc` | Legacy characteristic selection, volume/range/program codecs, additional tinnitus helpers |
| `ev_132802ad0028f66af50400c9f0d25acf0dadb6e9903c28ab0f9c17727f1fe1aa` | Exact legacy method bodies and build-local tokens |
| `ev_83467b4bdc409a8bde22579c099735f2dc3a6eae9adbbbf660c8cc5a413a118f` | Consumer volume readers/setter and legacy program-category mapping |
| `ev_388df9253c46cb9a6e1cbcf546f95a97c3111b0d2fe915ae9d964a13eeadf2d0` | Exact program-category mapping CIL |
| `ev_65f9513247728bf3eab39435eb32191d466d4c7eb04e9f5139ed1188ccc72856` | Official source eligibility, paired field preservation and loading guards |
| `ev_ecfa7f615cefe511607fc9c9d2970df966e6e4e32665e7420d7d0a6759aedc63` | UI gate/dispatcher CIL method bodies |

Build-local legacy tokens: volume setter `0x06000100`, encode `0x06000125`,
decode `0x06000126`, program flags `0x06000127`, ranges `0x06000128`.
RemoteControl.Core tokens: source gate `0x06000094`, paired dispatcher
`0x0600009b`, streaming-loading guard `0x06000449`, available sources
`0x06000462`. These tokens require the assembly hashes/MVIDs above.

Full evidence remains ignored in `private/rea-tinnitus-evidence.json` (61
records), with proprietary binaries/reconstruction under `private/`. Static
setter recovery does not prove that a particular aid accepts a write or has a
tinnitus program fitted. Parent-coordinated codec/backend tests and eventual
explicit user hearing checks are separate from this research pass.

## Open Companion implementation

The app retains the per-program tinnitus flag and the four verified streaming
categories. Missing flags fail closed. Current tinnitus eligibility takes
precedence over streaming eligibility even if both appear in cached data.
The two source characteristics are permitted for reads/notifications only in
the recovered legacy remote-control service. Merely receiving their values or
exposing a range never enables an unfitted source.

Each explicit level/mute action may target one aid or two independently linked
aids. It locks the selected aids' consumer controls, reads their current active
program, reported ranges and source volume/mute pairs, then preflights every
target before the first write. A level step preserves each ear's mute and level
offset; mute preserves each ear's gain. Before each write the app reads those
fields again and stops if any changed. Each write requires exact readback
before the next ear can be changed. A later-ear failure reports how many ears
confirmed; no atomicity or automatic rollback is claimed. Unconfirmed source
values become unavailable until another actual read.

These source controls remain separate from normal microphone volume, saved
presets and Restore All. Neither connecting, toggling link mode, loading
metadata nor changing tabs issues a tinnitus or streaming-volume write. No
modulation, tinnitus EQ or therapy-configuration controls were added.

Synthetic tests cover untouched-field preservation, independent ear offsets,
all-target range preflight, unknown program eligibility, the exact streaming
categories (including excluded 6/8/9), tinnitus precedence, busy/disconnected
states and service-bound read/notification allowlisting. Hardware write
acceptance and audible effects require a later explicit user test.

## User-facing fitting guidance

The orange section beneath Streaming EQ distinguishes relief-sound gain from
the ordinary listening controls. It states that the program must already be
fitted for the user and that reported limits alone do not enable therapy.
[Oticon's Companion guidance](https://www.oticon.com/support/oticon-app/help-with-the-oticon-app/how-to-use-tinnitus-soundsupport-program)
requires professional activation during fitting. The
[Intent instructions for use](https://www.oticon.com/-/media/oticon-us/main/download-center/intent/276032-intent-ifu-24-2.pdf?la=en)
describe clinician-set level and daily-use limits. The app does not infer those
limits from a gain range or offer an unfitted therapy-enable switch.
