# Battery percentage and estimated time left

The shipped Companion client receives remaining charge and average current draw,
then calculates its time-left display. It does **not** receive a raw hours/minutes
field in the recovered battery contracts. Audifern calls the result
**Estimated time left**, and uses reported telemetry rather than multiplying the
percentage by an assumed battery life.

## Shipped-artifact evidence

The analysis is static and execution-free, using the locally pulled Android
Companion 1.8.0 (617548) assemblies and decoded service contracts. The binaries,
decoded proprietary resources, and REA bundle remain ignored under `private/`.

| Artifact | Identity |
| --- | --- |
| `Demant.OneApp.Lib.Hal.Wrapper.dll` | SHA-256 `e13600d24d5f44d6f173be4d1df3822b294a7b2341c986ea03dbffe4b00dcfd8`; MVID `0ca344f6-16d9-4f18-9cc2-80c7ab5a6137` |
| `Demant.MpHal.MetaxRuntimeModel.dll` | SHA-256 `c38188c38606d15eda95fd2752f055825d4c5f12e2bdf41b6ab8e7624bb922f5`; MVID `1fcde86f-b9ea-44f2-a2d4-c8d34e654504` |
| `462-UtlServiceContracts.battery-1.0.xml` | SHA-256 `00ec520dfe4df9a9f6b1f2bf13780ecfeaa82da2af7c5371ffc820629d775b16` |
| `463-UtlServiceContracts.battery-1.1.xml` | SHA-256 `701e4c3fbcb6f2c1aad125d1b09bd98d9f3d218b726ffe6b1dc04c089392c53b` |
| `464-UtlServiceContracts.battery-2.0.xml` | SHA-256 `0c16d34d14d9f9cf23b37b074a58c1b17a03470ce6fbeaf2b9098c38d7f729e9` |

The extraction provenance for the XML is described in
[resource-findings.md](resource-findings.md). The battery-specific REA bundle is
`private/rea-battery-evidence.json` (including the actual scalar/bit decoder;
no target execution).

| Evidence | Scope |
| --- | --- |
| `ev_4b406a60d767aae89c634c0543764736d34023b7bf04edd59c2579b41accec54` | Wrapper assembly identity |
| `ev_1a6a9d3c94d8182f9b506528879e9095486e87173feb91a871814762528af615` | Five selected battery manager/tracker/reader/event-handler types, 58 methods |
| `ev_700306fbad370d9165476a96e6116b2612d257fbfdadb1827fd963d55ee4d56a` | Selected method bodies and build-local tokens |
| `ev_1e216723cdcc1095a2028ffad1df2fe85734283a44406c665d4e89ba605ed55c` | Battery method call edges |
| `ev_9ccee1f32e4f3948c00f39c19473e58c085c061a6141cea4367837422862ba5d` | Compiler-generated lambda CIL, including the charge/current division |
| `ev_0ee141a17fc9b924385eae1774653401688cce4696e9d5bb60d9d9fde2356f99` | Exact `System.TimeSpan.FromHours(double)` member reference |
| `ev_a6688cc853735984ec411620b6d6cc4716469b1a0871f8772e14db2687f1fe61` | Metax decoder assembly identity |
| `ev_fe0f61b7b1408dcaf517b96f80e2d0db98b386a01a824d0c3198cc220ec9ae9c` | Exact `DecoderBase` / `Decoder` member selection |
| `ev_6da1a44f52f630a677884e5a5a617bcdd574e0c0671302471bda3bdd1819832c` | Fixed-width integer and MSB bit-reader CIL |
| `ev_2fff8ac826bb6c0bea619920c89a76c9c3d65faecdc462b99ff8d8883d08ff1b` | Decoder/DecoderBase CIL recheck: returns selected outputs without requiring payload exhaustion |

Relevant wrapper tokens are `BatteryTimeTracker.IsSupported` `0x060005fb`,
`DelayRawBatteryTimeCheck` `0x060005fd`, `TrackRemainingTime` `0x060005fe`,
`IsProperRawData` `0x06000600`, and the calculation lambdas `0x060010ff` /
`0x06001100`. Tokens identify only the assembly hash/MVID above. In particular,
the first lambda has a CIL division and the second calls `TimeSpan.FromHours`;
this confirms the units of the calculated ratio without assuming the absolute
units of either raw field.

## Read-only contract

The UTL service ID is `0x01000007`. Its handle must come from the current service
directory. Supported recovered versions are exactly 1.0, 1.1, and 2.0; unknown
versions are rejected. These requests have no input fields and use success
status `0x40`. Normal consumer command-session and transport framing still apply.

`getInfoFast` (opcode 2) consumes **13 bytes**: three fixed-width, big-endian
32-bit integers, followed by a byte containing MSB-first Boolean bits. These
scalar `getDataUInt` / `getDataInt` / `getDataBoolean` actions are **not CBOR**;
the equalizer's `getDataVector` has a different carrier.

| Order | Field | Wire type | Availability |
| --- | --- | --- | --- |
| 1 | `level` | BE UInt32, bytes 0–3 | All versions; percentage only when 0–100 |
| 2 | `remaining_charge` | BE Int32, bytes 4–7 | All versions |
| 3 | `fast_avg_current_draw` | BE UInt32, bytes 8–11 | All versions |
| 4 | `battery_low` | Byte 12, mask `0x80` | All versions |
| 5 | `is_discharging` | Byte 12, mask `0x40` | All versions; charging is its inverse |
| 6 | `charging_done` | Byte 12, mask `0x20` | Version 2.0 only |

The remaining low bits of the flags byte are ignored, as they are not consumed
by the recovered contracts; version 1.x also ignores `0x20`. The codec does not
invent a zero-only rule for unspecified padding bits. The decoder implementation
confirms this carrier through `GetUInt32` `0x0600098e` (shifts by 24/16/8),
`GetUIntFromBits` `0x06000992` (MSB first), `GetDataUInt` `0x06000981`, and
`GetDataInt` `0x06000980`. These tokens belong to the Metax assembly above.

A live Battery **2.0** response was **16 bytes**, including a nonzero three-byte
tail after the defined fields. The shipped `Decoder.Decode` `0x0600097f` stops
after its schema steps and returns the output dictionary; it does not require
all payload bytes to have been consumed. `GetDataBoolean` still reads successive
MSB-first bits in byte 12, not additional 32-bit Boolean fields. The meaning of
bytes 13–15 has not been established, so they are ignored rather than labelled
as zero padding or interpreted as telemetry. Audifern narrowly accepts
13-byte packets for all three supported versions and this observed 16-byte
shape for version 2.0 only. Other lengths and unknown versions remain rejected.
The source capture stays ignored at
`private/gui-030-left-telemetry-events-ax.txt`; committed fixtures substitute
synthetic charge/current/percentage/tail values while preserving its shape.
The decoder recheck is exported in `private/rea-battery-tail-evidence.json`.

`getInfoSlow` (opcode 1) returns **16 bytes**, four sequential big-endian values:
`lifespan` UInt32,
`lifespan_threshold` UInt32, `slow_avg_current_draw` UInt32, and
`full_charge_capacity` Int32. These are health/capacity fields, **not a remaining
runtime**. Their absolute units have not been established.

UTL events `changedBatteryState` (1) and `changedCurrentDraw` (2) carry the same
versioned fields as `getInfoFast`. The shipped callback processor handles both;
the pure codec checks the current dynamic handle and exact event code before
decoding. A malformed event cannot be interpreted as a different service.

The older vendor BatteryInfo characteristic
`D5D0AFFB-35B8-4FDC-A50B-F777C90293B8` in service
`56772EAF-2153-4F74-ACF3-4368D99FBF5A` contains exactly three bytes:
level/lifespan/threshold. The shipped GATT client falls back to standard
Battery Level `180F/2A19` when the vendor level is 255 or unavailable. Neither
GATT form supplies charge/current telemetry, so neither supplies time left.

## Calculation, validity, and settling

The shipped `BatteryTimeTracker` calculates:

```text
estimated seconds = remaining_charge / fast_avg_current_draw × 3600
```

It requires both values and positive current draw. Its advertised support check
also requires a rechargeable aid using UTL, and its stream returns no duration
when the aid is not activated. Absolute charge/current units are not specified
by the recovered contracts; do not relabel them as mAh/mA or µAh/µA without
further evidence. The runtime interpretation of their ratio is established by
the shipped implementation.

Audifern adds conservative display guards: no negative charge, no draw
outside the shipped signed Int32 representation, and no estimate while explicitly
charging or charge-complete. These last charging guards are our behavior, not a
claim about `BatteryTimeTracker`. Zero charge with positive draw means zero time;
zero draw means unavailable. Percentage is independently range-checked.

The shipped manager recognizes charge=0 **and** current=0 as corrupted telemetry
and retries after five seconds, with a 12-item bound. There is no established
special negative-charge or UInt32-max sentinel in the inspected code/contracts;
the codec retains raw values but does not manufacture a duration from them.
The actual Metax `getDataUInt` casts to signed Int32 for an `Int` output slot;
therefore a raw current above Int32-max fails the shipped positive-current
eligibility check. The Swift codec retains the unsigned raw value for inspection
but suppresses its estimate as well.

The shipped settling rule reads the aid's actual identification `PairingTimer`:
when positive, it waits that many seconds plus 60 seconds for battery 1.x, or
300 seconds for battery 2.0. A missing or zero timer results in zero delay.
This is **not** evidence for an unconditional 60/300-second delay after every
connection. `settlingDelaySeconds` exposes that rule without inventing a timer
from connection age; its Double arithmetic also avoids overflow at UInt32-max.

The shipped client polls every five minutes while an eligible aid is activated,
in addition to processing battery events. Disconnect must clear the live
telemetry/estimate. A displayed estimate is a timestamped telemetry result, not
a countdown guaranteed to track changing streaming load between updates.

## Implementation and validation boundary

`Sources/CompanionCore/OticonBattery.swift` is a pure, read-only decoder. It does
not issue Bluetooth requests, poll, notify the user, or change hearing settings.
Its eight tests cover all supported versions, actual charge/current arithmetic,
charging/invalid data, the minimal and observed version-bounded packet shapes,
all 256 flag bytes, legacy health fields,
dynamic event handles, and the settling rule. Build/test execution is delegated
to the coordinating app work so independent agents do not race the shared build.
The coordinated Swift suite passed 111 tests. Subsequent actual reads decoded
both Intent 3 aids' telemetry and populated independent estimates in the native
dashboard. Static recovery and synthetic tests are distinguished from those
runtime observations in [hardware verification](hardware-verification.md).
