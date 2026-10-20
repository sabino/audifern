# Packaged configuration and platform feasibility

Inspected on 2026-10-20. This report separates installed-app resources, passive Android state, published specifications, and implementation hypotheses. Raw artifacts, extracted resources, keys, private device metadata, and decompiler output remain under ignored `private/`.

## Findings ledger

| Question | Finding | Evidence and boundary |
| --- | --- | --- |
| Which model is currently paired? | Android Fast Pair metadata names Demant Intent 3 on both aids. | Passive `dumpsys bluetooth_manager` snapshot, `private/android-bluetooth-initial.txt`, SHA-256 `633ecd2b80632c5b7444143fc78a989c3283345b5cfc84d2cb66414e7c052150`. Cached metadata identifies a model; it does not verify firmware or every enabled feature. |
| Is Companion using BLE with both aids? | The snapshot has a live `com.oticon.app` GATT client connection to each aid. | Same passive snapshot, Registered App and GATT connection sections. The disconnected ASHA profile elsewhere in the dump does not mean Companion's GATT link is disconnected. |
| Are protocol descriptions packaged locally? | Yes: the APK contains `assets/HearingSystemConfiguration.sqlite3`, with 152 package records, 34 collections, 872 documents, and an empty Binaries table. | REA SQLite inventory `ev_1f5dc5807357cb4e4ea7acd85a9d27465979c01c2175dd9016ee2e6da3396940`; metadata sample `ev_8ea7436e428bb31c679c9ed62aa91ccdf8e30084e064d3ca83e6087aa69b74a5` covers 250 document rows. Complete counts were independently queried read-only with Python SQLite. |
| Can the packaged documents be understood? | All 872 blobs decoded into well-formed XML using the shipped configuration loader's AES-CBC/PKCS7 and gzip format. | Derived offline result, not device execution. Loader identity: `ev_045d376ce49abc65a517c6a3b055a9549906687b4322d2619c76cc4b7657d126`; selected managed members: `ev_53b3b57f8f46657a3eb9d5fa3ad4933196392dcb7ffba86b5598dbdfc2243a70`. Individual XML hashes and validation results are in `private/resources/decoded-inventory.json`. |
| Does this expose the device authorization key? | No such conclusion follows. The recovered material opens static configuration shipped with the app. | Hearing-aid pairing, link encryption, vendor sessions, and authorization remain separate questions for transport/runtime analysis. No cloud request was needed for this resource decoding. |
| Is a Mac remote-control app plausible? | Yes. Public Core Bluetooth supports GATT discovery, reads, notifications, and writes; the phone exposes standard control services, while packaged contracts describe additional vendor controls. | Feasibility inference. Each protected characteristic and proprietary session still needs verification on the Mac. |

The SQLite artifact SHA-256 is `c67fc2cc8ceca4a94e5a6ad9b431b8c05c9bba9fdf1d7c7cd5c22ef399297698`. The configuration loader assembly is `Demant.MpConfig.Core.dll` version 19.4.1.0, SHA-256 `c586475fc0189151e107166d25b90d9edb22c77c8ac2e3d4082ba15465647302`, MVID `ce2f71ef-c3f0-4619-b7a2-0d349fd1fe40`.

Relevant build-local method tokens are `Decrypter.Decrypt(byte[])` `0x060001b9`, `SqLiteDataAccessorBase.<ExecuteXElementQuery>b__25_0` `0x0600017c`, and `SqLiteDataAccessorBase.Decompress` `0x06000178`. Managed member pages are retained as `ev_347182e814a529a0937f323a1563e81599f143a1b7ac72dbee95f1c474b9ff03` and `ev_d2a4098652bc95413436e4b52024f6a3ea6ee4b274fd31a9bc2cf7827dd87c0e`. Tokens only identify this exact assembly build.

## Services visible to Android

The cached LE service list includes these UUIDs. Expand 16-bit values with Bluetooth base suffix `-0000-1000-8000-00805f9b34fb`.

| Service | UUID | Read-only starting point |
| --- | --- | --- |
| Battery | `180F` | Battery Level `2A19`, if exposed and readable |
| Volume Control | `1844` | Volume State `2B7D`; Volume Flags `2B7F` |
| Coordinated Set Identification | `1846` | Identify the two-aid set; avoid collecting its resolving key |
| Audio Stream Control | `184E` | Presence indicates an audio capability, not an established audio stream |
| Broadcast Audio Scan | `184F` | Discoverability does not prove an active Auracast reception |
| Hearing Access | `1854` | Features `2BDA`; Active Preset Index `2BDC` |
| Google ASHA Hearing Aid service | `FDF0` | An audio-profile service; this is not Demant's proprietary control transport |

The passive HAS client state reports two valid connections and features `0x10`: binaural, dynamic preset list, identical lists across the pair, no synchronized preset-change relay flag, and no writable-preset-name flag. One available preset was cached per aid. Preset names, device addresses, serials, and set identifiers are intentionally omitted.

UUID assignments come from the [Bluetooth SIG Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html). The [Volume Control Service specification](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/77401-VCS-html5/out/en/index-en.html) defines the three-byte state as volume, mute, and change counter; its characteristics require link encryption. The [Hearing Access Service specification](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/13249-HAS-html5/out/en/index-en.html) defines preset features and also requires encryption.

Android's [ASHA specification](https://source.android.com/docs/core/connect/bluetooth/asha) and [hearing-aid implementation](https://android.googlesource.com/platform/system/bt/+/android-p-preview-5/bta/hearing_aid/hearing_aid.cc) identify `FDF0` as the hearing-aid audio service. The proprietary transport UUID must be recovered from the app and confirmed separately; Android's cached service list is not an exhaustive proprietary GATT inventory.

## Vendor remote-control contracts

These are decoded UTL service IDs and opcodes, **not GATT handles, UUIDs, or complete on-air packets**. A device must advertise the supported service/version, and framing/session requirements must be satisfied before using a contract. Merely shipping a contract does not establish Intent 3 firmware support.

| Contract | Service ID / inspected version | Operations relevant to a companion |
| --- | --- | --- |
| Volume | `0x0200000D` / 1.3 | 0/1 read/set general volume; 2 capabilities; 3/4 read/set streaming volume; 5/6 read/set general mute; 7/8 read/set streaming mute; 9/10 read/set persistence |
| Program | `0x0200000E` / 2.1 | 0 read active program; 1 set it; 2 program information |
| Battery | `0x01000007` / 2.0 | 1 slow battery information; 2 current battery information; battery-state/current-draw events |
| Identification | `0x02000004` / 1.2 | 0 detection data; 1 version; 2 SSM information; 3 HIID; 4 app state |
| Equalizer | `0x02000010` / 2.0 | Separate streaming and microphone equalizer reads/settings/events |
| Audio controls | `0x0200001C` / 2.0 | Read/set CBOR configuration and configuration-change event |
| Session | `0x02000009` / 1.1 | Session open/close, access semaphore, transaction handling; also programming/reset operations outside the prototype scope |

Volume values and device-reported min/max are signed eight-bit fields. Program IDs are unsigned eight-bit fields. Information payloads include CBOR. The separation of general and streaming volume suggests that the general controls represent microphone volume, but that semantic mapping should be confirmed in the app's higher-level implementation. Notification/event contracts provide a path to update the Mac UI when physical aid controls or the phone change settings. Each side can be addressed by its own connection, but binaural synchronization behavior requires live verification.

Selected decoded document hashes:

- Volume document 527: `ab5fabd0763d90ffa100d3f2d4002a9e40ad931e60a134a875a6900c33e748a6`.
- Program document 506: `4d59b36fca9a76047776e82256ffcc09ecb96689134aed4af633c5df1e02531e`.
- Battery document 464: `0c16d34d14d9f9cf23b37b074a58c1b17a03470ce6fbeaf2b9098c38d7f729e9`.
- Session document 512: `748c5b44e68c0c8b61b114a12ab0f0b35f6a7c78e8cc1e6d7b7dfca8c4f9d336`.

The [Hearing Access Profile](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/12014-HAP-html5/out/en/index-en.html) explains that standard VCP volume/balance is generally independent of manufacturer-specific audiological settings. Therefore the Mac should keep standard audio volume and vendor microphone volume distinct until correlated on this hardware.

## macOS, audio, and multiple hosts

[Apple's Core Bluetooth central-role guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/PerformingCommonCentralRoleTasks/PerformingCommonCentralRoleTasks.html) documents the BLE operations needed for a native transport. It does not grant access to private hearing-device audio protocols or guarantee access to every protected GATT service.

Audio already has an OS-supported path on compatible Macs: Oticon's [Mac pairing guide](https://www.oticon.com.br/support/pairing/apple/how-to-pair-hearing-aids-with-mac) describes pairing via Accessibility → Hearing Devices and lists supported Mac generations. Apple [documents MFi controls and audio](https://support.apple.com/en-us/108780) including microphone level and presets, with exact hardware/OS requirements in its [compatibility list](https://support.apple.com/en-us/106341). These are separate from implementing Companion-specific BLE controls.

Oticon [states that Companion is unavailable on Mac](https://www.oticon.co.uk/support/troubleshooting/apple/why-can-i-not-stream-from-ios-to-hearing-aids). Its multiple-Apple-device troubleshooting acknowledges handoff and advises keeping Companion active only on the intended device. Neither that page nor the passive phone snapshot establishes how many simultaneous proprietary control sessions Intent 3 accepts, or whether Android and Mac can hold those sessions concurrently. That needs a bounded live check; no unpair/reset is justified by this static evidence.

## Remaining checks

- Confirm what macOS exposes through Core Bluetooth while its existing system hearing-device connection is active.
- Read only identified status characteristics first; distinguish discovery from encrypted read success.
- Identify the vendor transport/session/version negotiation and correlate responses with these contracts.
- Verify available features against this device's capabilities, rather than enabling everything in the multi-model resource database.
- Test user-selected, bounded controls only after readback and acknowledgements are understood. Firmware/fitting/programming/reset protocols are not required for a desktop companion.
