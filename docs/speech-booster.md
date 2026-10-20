# Speech Booster and linked consumer controls

These are independently authored consumer controls derived from the installed
Oticon Companion 1.8.0 (617548) SDK. Static protocol support and synthetic test
results do not establish physical acceptance or perceived effects. The earlier
EQ hardware results are in [hardware-verification.md](hardware-verification.md).

## Shipped evidence

REA member evidence `ev_50aa31cbf10d32318b881309df19197a281ed2f6f0b2c341dedfcf43a0eb75d2`
covers the consumer SoundBooster/LegacySoundBooster managers and their UTL
getter/setter in Wrapper SHA-256
`e13600d24d5f44d6f173be4d1df3822b294a7b2341c986ea03dbffe4b00dcfd8`,
MVID `0ca344f6-16d9-4f18-9cc2-80c7ab5a6137`.
`ev_f0d401303999297e7754f1ec38c2c5eb068551bba6cd1cadedf88c4d031d4011`
covers the direct-GATT mapping in LegacyRemoteControlManager SHA-256
`d5b0f7a2c3ed17bf8b4e801eedc1aaa290a19e59f02c837689dea8933bb53288`,
MVID `727bc5cb-0147-49d5-ad68-384b85758e1d`. Full evidence and reconstructed
vendor source remain ignored in `private/rea-speech-booster-evidence.json`
and `private/decompiled-managed/`.

The recovered `mcesystemcontrol` 1.1/1.2 XML contracts establish service ID
`0x02000013` and the command mapping below. Commands use the discovered runtime
handle. Each returned adjustment is exactly three signed bytes: value, minimum,
maximum. They are fixed-width scalars, not CBOR vectors.

| Consumer adjustment | Read | Write |
| --- | --- | --- |
| Noise reduction | 0 | 1 |
| Directionality | 2 | 3 |
| Target-loss compensation | 4 | 5 |
| Reset these three consumer adjustments to defaults | — | 6 |

The SDK regards Speech Booster as enabled only when all three current values
equal their reported maxima. Enabling reads the current triples, writes those
three reported maxima in one ordinary COMMAND transaction, then reads all three
again for confirmation. Disabling uses MCESystemControl opcode 6 and confirms
the resulting disabled state. This service-specific reset is distinct from
session-level device reset, fitting-state entry and firmware operations; none
of those is sent. A partial/ambiguous result clears the cached booster state.
The active program must explicitly report its `boostable` metadata flag before
the user can change the control. Unknown metadata never enables a write.

The installed SDK prefers profile templates on compatible ProfileControl 3.x
devices. Its registered profile consumer manager is version 3.0, while the
earlier real Intent 3 registry advertised ProfileControl 2.0 and
MCESystemControl 1.2. For that registry the SDK's compatible consumer path is
MCESystemControl. This implementation does not guess template identifiers for
newer compatible profile-based devices and does not synchronize ears by writing
a profile during a read-only refresh.

## Direct GATT fallback

The legacy `MakeAudible` characteristic is
`9215A295-B813-483F-9F85-B700D0B7BC75`. The SDK recognizes lengths 7, 8 and 9.
It preserves the first two bytes and any trailing byte outside its booster
fields. Supported length-7/8 records use five booster bytes; length-9 records
use six. Disabling writes `0xFF` only to those booster fields. The client uses
a write without response where exposed, followed by an actual characteristic
read. The app confirms the decoded on/off state rather than assuming an ATT
acknowledgement or requiring the defaults to remain represented as `0xFF`.
Malformed/unknown lengths cannot enable this path.

## Linking volume controls

Linking the UI changes no hearing-aid setting. A later volume or mute action:

1. Requires both current connections and locks both sets of consumer controls.
2. Reads both current microphone volume/mute values.
3. Validates both target payloads against both reported ranges before the first
   write. A step preserves the ears' existing level difference.
4. Writes one ear at a time and requires its readback before the next ear.

An aid disconnect, program/range change or failed readback stops the sequence.
A completed first-ear change is reported as a partial result if the second ear
fails; no cross-device atomicity or automatic rollback is claimed. Per-ear
controls remain unavailable while the linked request is active.

## Device identity and battery

Serial number uses standard Device Information `180A/2A25` where available.
For aids without that characteristic, an explicit consumer-feature load uses
the supported `detect_info` service's read-only `get_hiid` command (opcode 3).
Its bounded HIID decoder retains the interface version and the aid's actual
serial entry only; production serials and other fitting/identification blocks
are skipped. Both paths store the value in that individual connection's live
state, clear it on disconnect and display it in device information. Raw serials,
HIID payloads and their hex are not copied into session events. Model and
firmware retain their existing standard per-device reads.
The exact HIID entry, supported versions and formatting evidence are in
[device-identification.md](device-identification.md).

Battery telemetry is described separately in
[battery-telemetry.md](battery-telemetry.md). After an explicit consumer-feature
load, existing authenticated sessions poll at the SDK's five-minute interval;
polling never opens a replacement authentication session. Current percentage
notifications remain live. A charge/current zero pair receives bounded
five-second retries, and estimates older than two polling intervals are hidden.
Session closure and failed reads clear the telemetry estimate.
The ordinary card Refresh action refreshes these consumer features only when
its advanced channel is already authenticated; it does not initiate a new
authentication. Identification is queried only while the current aid's serial
number is unavailable.

## Validation boundary

Focused tests cover signed booster triples, version bounds, reported-maximum
selection, preservation of unrelated legacy bytes, whole-command transaction
ordering and confirming enable/disable reads with a synthetic peer. Linked
range preflight and balance preservation are tested independently; serial
allowlisting, per-program booster gating and stale battery estimates have
model tests. Real linked changes, Speech Booster effects and delivered macOS
notifications require their own runtime checks.

The coordinated local suite passed **111 Swift tests**, including validation
against the HIMSA audiogram schema. Tests use synthetic device records and a
mock notification sender; they do not operate the actual hearing aids or send
real macOS notifications. Subsequent live reads populated separate time-left
estimates and distinct HIID serial numbers on both Intent 3 aids, and read
SpeechBooster state through each aid's supported consumer path. See the
[hardware report](hardware-verification.md) for retained private evidence.
