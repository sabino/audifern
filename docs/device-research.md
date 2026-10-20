# Additional device information and firmware content

This pass distinguishes device metadata, configuration/debug bytes, downloaded
update packages, and a copy of the firmware actually installed in an aid. The
evidence comes from the pulled Companion 1.8.0 (617548) APKs, their managed
assemblies, and the previously decoded configuration resources. The static research
did not execute a target, issue Bluetooth commands, enter programming/update
modes, or contact Oticon update services. Subsequent bounded runtime checks are
recorded separately below and in the hardware ledger.

## Findings and remaining questions

| Question | Finding | Status and boundary |
| --- | --- | --- |
| Can the app expose more device information? | Yes. The SDK has typed firmware/software/hardware identification fields, battery health, stored-crash counters, and additional service-dependent diagnostics. | Contracts recovered; each live feature must still require its advertised service/version and normal session rules. |
| Is there a read-only crash-information query? | `core_dump.get_core_dump_info` returns a last-dump counter and number of available stored dumps. | Proven ordinary consumer command path; it returns no dump byte size or firmware image. |
| Does DFU provide installed-image download? | The three recovered DFU contracts provide update session, boot, upload, and confirmation operations. | No readback operation in these contracts; this is a bounded negative, not proof that every hardware/debug interface prevents readout. |
| Does `OperationBleFirmwareRead` prove flash dumping? | No. The inspected caller uses it to collect responses to ordinary firmware commands. | Its fields contain a response length, not a flash address. |
| Are real memory/configuration reads present? | Yes: versioned HIID/action/effect reads on UTL and raw/file NVRAM reads on the older Aurora protocol. | They do not establish a compatible complete installed-image read path on the tested Intent 3. |
| Is an Intent application firmware image shipped in the pulled APK? | No application update package was identified in the APK-member/resource inventory. Small NVRAM RAM-boot helper blobs are embedded. | Package inventory and helper classification are bounded below; opaque application code is not an absence proof. |
| Could an update package be acquired separately? | The official client discovers an update endpoint, performs an eligibility lookup, then downloads a returned URL. | Exact client/cache path recovered; endpoint credentials, caller UpdateKey semantics, URL validity and server accessibility are not established by a network test. |
| Have we pulled installed firmware from the aids? | No. | A genuine readout route, address map/length, and supported session/transport remain unresolved. |

## Recommended consumer information

A read-only check on the attached Android phone confirmed that Companion is
installed. Its private `files/UpdateDataBackup` path could not be inspected
through `run-as` because the installed app is not debuggable. No corresponding
directory was present at the checked external-storage location. This does not
prove that its private cache is empty. No root, backup or access-control bypass
was attempted; no update package was recovered from those checks.

The normal identification path is documented in
[device-identification.md](device-identification.md). Version and revision
strings should be displayed using their actual field names; an application
version, release-package version and hardware revision are different facts.
The battery health contract is described in
[battery-telemetry.md](battery-telemetry.md); its capacity/current units must not
be invented.

### Stored crash information

Service `core_dump` is `0x0200000C`, recovered version 1.0. Opcode 0 has no
inputs. The response decoder consumes four bytes:

| Offset | Field | Encoding | Suitable display label |
| --- | --- | --- | --- |
| 0–1 | `last_count` | Big-endian UInt16 | Last dump counter |
| 2–3 | `available_core_dumps` | Big-endian UInt16 | Stored crash dumps |

There is **no size field** in that response. A count of stored dumps is not a
total byte length, memory usage measurement, or a diagnosis of a current fault.

Consumer compatibility is established through the shipped implementation:

1. `GetCoreDumpIdsCommand` selects activated UTL aids with this service and calls
   `get_core_dump_info` using a normal MfD package.
2. It does not request an elevated minimum session. The package defaults to
   `Shared`, which MfD's `ActivatedState` maps to ChipService `Interactive`.
3. MfD creates an interactive HI command. Metax requires a transaction for
   `core_dump` because it is absent from the explicit transaction-exemption
   prefixes.
4. `InitializedState.InsertTransactionCommandsIfNeeded` supplies an ordinary
   `COMMAND` start/commit wrapper. There is no boot, update session, reset, or
   dump-content request in the info operation.

The contract also provides opcode 1 (position BE16 → dump ID BE16) and opcode 2
(dump ID, requested length, offset, each BE16 → raw dump bytes). The official
content collector reads chunks of 2,058 bytes until a short reply. Those are
separate operations; the information feature does not retrieve dumps. Stored
crash data should not be described as a complete firmware image.

### Additional service-dependent getters

The packaged `fwUtilityService` is `0x01000002` version 1.1. These operation
names and byte layouts are recovered, but their presence in the client does
not establish support on an aid. No queries should be sent when the current
service directory omits it.

| Opcode | Getter | Input | Decoder output |
| --- | --- | --- | --- |
| `0x0B` | `getFFSSectorCount` | None | UInt16 sector count |
| `0x0C` | `getFFSEraseCount` | UInt16 sector index | UInt16 erase count |
| `0x0D` | `getFFSWearInfo` | None | UInt32 maximum/minimum/average erase counts, UInt16 statistics sector/error counts |
| `0x0E` | `getBatteryInfoProtocol` | None | 288 bytes consumed, including batch/model/date fields, UInt16 full-discharge cycles, capacity/voltage fields and a 200-byte discharge curve |
| `0x10` | `getBatteryRemainingCharge` | None | UInt16 raw remaining charge; units unproven |
| `0x12` | `getIsInShelfMode` | None | UInt8 raw status; no Boolean mapping established here |

Scalars above are fixed-width big-endian, not CBOR. Output byte counts describe
bytes consumed by the shipped decoder, which does not require packet exhaustion.
These getters are distinct from neighboring shelf/dormant mode transitions,
RF tests, reset/clear operations and battery setters. The XML's
`activates="false"` is not itself a guarantee that an arbitrary operation is
nonmutating; classification also follows the operation and client data flow.

## Firmware update versus installed-image readout

The `dfu_server` service is `0x0200000A`, recovered versions 1.0, 1.1 and 2.0.
Their nine operations are:

| Opcode | Operation | Direction or effect |
| --- | --- | --- |
| 0 | `open_update_session` | Opens a device-update session |
| 1 | `confirm_application` | Confirms an application |
| 2 | `boot_hi` | Boots the selected application |
| 3 | `establish_dfu_session` | Establishes the DFU target/session |
| 4 | `start_dfu_package_transfer` | Sends a manifest; receives an upload chunk size |
| 5 | `send_dfu_package_chunk` | Sends package data to the aid |
| 6 | `end_dfu_package_transfer` | Ends upload; disconnects/reboots can be expected |
| 7 | `confirm_dfu` | Confirms the update |
| 8 | `close_update_session` | Closes the update session |

`ApplyDeviceUpdatePackageChipCommandProcessor` sends the supplied manifest,
splits the supplied package Data into the negotiated chunks, uploads those
chunks, then ends the transfer. It does not read an installed application back.

`ExecutionContextGeneral.OpenUpdateSession` supplies an update token, a
per-device private client token, software application ID, encoded serial and
date; it changes the tracked session type to DeviceUpdate. Initialization can
boot another application, and high-speed update mode can disable streaming and
disconnect other clients. These are not passive identification requests and
are outside the metadata feature.

The `OperationBleFirmwareRead` / `OperationBleFirmwareReadUtl` names are broader
than image extraction: the inspected Aurora `BleTransportProtocol.ExecuteAsync`
encodes ordinary command sequences into a FirmwareWrite operation, then uses
FirmwareRead to receive their result bytes. A class name or BLE read primitive
does not establish a flash-dump command.

### Memory paths that do exist

UTL service `hiid` (`0x02000006`, versions 1.0/1.1) opcode 0 reads a DIET entry.
Its request is a fixed byte `01`, then entry key, offset and length as BE16;
its decoder returns the requested number of raw bytes. The official UTL memory
scheduler wraps these reads in `READ_NVRAM` transactions and chunks blocks at
950 bytes. It also handles typed effect/action/end-user-setting locators.
Unknown memory-locator kinds are rejected. These are structured identification
and fitting/configuration accesses, not an arbitrary installed-code address map.

Older Aurora operations include `RawNvramRead` with a 24-bit address and 16-bit
length, and file-index/offset/length reads. PIF2 and SWD adapters are also present
in the broad SDK. Their existence keeps raw readout a research question; it does
not show that the user's current BLE UTL aid exposes those operations or that
its installed code is readable. No Aurora, PIF2, SWD, debug or programming-mode
probe was performed.

## Update package acquisition and cache boundary

The official WFU client obtains its endpoint from capability
`esoftwareupdateservice` version 1.0 (`WfuCapabilityDto.Dfu.Endpoint`), then
POSTs `/api/v2/UpdatePackages/GetAvailableUpdatePackage`. The response DTO
contains application versions, an update-package identifier, and a
`Blob.ContentURL`. `FirmwareUpdateService` downloads the returned URL; the ZIP
extractor finds `Primary` and `Maintenance` JSON entries and decodes package
contents. This package is an input to DFU upload, not a byte-for-byte readout of
the currently installed image.

The lookup request includes model/hardware and version information,
market/language, and a caller-supplied UpdateKey. The request builder uses a
masked serial placeholder for this lookup. Capability discovery uses the app's
configured CcsAuthorizationKey/environment. The inspected WFU lookup/download
factory itself shows no additional explicit authorization header or auth
delegating handler. UpdateKey semantics, server eligibility rules, returned URL
signing/expiry, and public accessibility remain unverified; no URL was guessed
and no request was made.

The recovered local cache path is:

```text
AppDataDirectory/UpdateDataBackup/{port}{packageId}.zip
```

An existing owner-phone cache would be a separate possible artifact source for
later authorized read-only inspection. A cached update ZIP would still need
its model, version, provenance, manifest and package encoding checked before
being called an installed firmware copy.

### What is actually packaged

The independent package pass inventoried all six pulled APK central directories
(2,485 file members) and all 477 extracted assemblies' ManifestResource tables
(127 resources, no scanner errors). No Intent 3 application update archive was
identified. The configuration SQLite contains 872 XML documents and no Binaries
rows. The XML is protocol/configuration data rather than an application image.

Four small embedded blobs were positively identified as NVRAM RAM-boot helpers:

| Resource | Bytes | SHA-256 |
| --- | --- | --- |
| ChipService `nvram_driver_ramboot.bin` | 11,750 | `bcc12ace84581f32c470ddb40e77890b8b4fb109d939b4e9b9297d345496bec3` |
| ChipService `nvram_driver_fe3_ramboot.bin` | 11,459 | `16d32128caac7b5251d9de98de8c43c6eeb7f73dc125611494a78c435599977d` |
| ChipService `nvram_driver_fe4_ramboot.bin` | 11,914 | `668da85261d54b19f1f043217d774414b13cdb68852019995ebf9cb8e2a94ab0` |
| HIConnectionManager `nvram_driver_ramboot.bin` | 10,293 | `0770582cd85ff3cb76f5c098ae5baf894bc7f75673f16abdc0906100a49dcbbe` |

`NvramDriverProvider` selects the ChipService helpers for `au2cs3`, `au2cs4`,
and `au3cs3` and pads to a four-byte alignment. This is evidence of helper code
for NVRAM workflows, not a recovered Intent primary/maintenance firmware image.
The inventory did not exhaustively classify arbitrary native constants,
field-RVA data, serialized-resource internals, ZIP signing/non-entry bytes, or
the phone's private cache. Its negative conclusion is limited accordingly.

## Evidence and limitations

Selected source identities:

| Assembly | SHA-256 / MVID |
| --- | --- |
| Ninjago | `f16dd8e10292d0c2c5c2e30c5ead787026531a9c93620ec382cc4ac2d02e17be` / `e7e0264d-0df4-4155-a987-6560542bdcc0` |
| ChipService | `21cd01da616403f3f843dc4b35fd49957180c4f072728d23c6fe9d9018a1fae3` / `e07387c0-da1f-4d24-9fe2-37ff70fa3eff` |
| Hal.Wrapper | `e13600d24d5f44d6f173be4d1df3822b294a7b2341c986ea03dbffe4b00dcfd8` / `0ca344f6-16d9-4f18-9cc2-80c7ab5a6137` |
| MfDServiceManager | `33c4a67ec39a3595221f6afe547c9569f1f78ef8617d4fa52312565e67531408` / `aa85b6d8-30e3-47f4-82a8-3e7b1eebc394` |
| MetaxRuntimeModel | `c38188c38606d15eda95fd2752f055825d4c5f12e2bdf41b6ab8e7624bb922f5` / `1fcde86f-b9ea-44f2-a2d4-c8d34e654504` |
| WFU.Core | `2bff1c9e41b220921c2df48383aa2ac53dbb40cacffa0aee2276cec8447f2f7e` / `8b2db27a-aa1a-4b4e-a021-3d024c087d0c` |
| Networking | `6fa49787646c36ffcaf48debd54fead9e1688ac0ac80827ab6beb737fbff4556` / `6305fed6-75d3-422d-bef0-815649b7479f` |

| REA evidence | Finding scope |
| --- | --- |
| `ev_ce4d8d929492196ae7cec5518da42e824a97da14d2a88ac10d5f8d8f45bc2051` | FirmwareRead wrappers, Aurora transport caller, typed UTL memory scheduler |
| `ev_a09604c7839a846b5041952c9a66003073d16058a5a133d8f2f8e4e965265070` | DFU upload/initialization processor and device-update state transition |
| `ev_f9345703fdc12d04cee210e8dd895f68a67f1e4be4ba39c06cf33e708c1427fa` | Official stored-crash info/content command wrappers |
| `ev_bb71b7a8a0269c8ba44a621bcbda6defa0c3f8a153be3a5a13e94dd3d251583b` | Consumer MfD package defaults, session mapping and interactive commands |
| `ev_1b6d1f61d72a32f64f19822c18e1ee85e5e2610c56adffb3f7d4b902aa695d7c` | Transaction classifier and explicit exemption list |
| `ev_dadf3187ef5e362feded507f86167bc6d092af8e2c25bec908142b5dd3333e7d` | Normal COMMAND transaction insertion |
| `ev_19d6c5e71a7dbd5ff05a63c23be194456315eab52205c8ea6ca0737f56bba0e4` | Earlier APK archive inventory, reused by the package pass |
| `ev_cb8469d198821138314961dc4550c00a383fc30ab538ab68412c53d5f1a6e590` | ChipService helper-resource bytes/identity |
| `ev_6d3e5feab07cb168080e7a5b299c8aa5901646eb6ccb53ab4c25b3990ef2e3f3` | NVRAM helper provider selection |
| `ev_03c113baedee10f4e1b713e91751ddac7fccca0dbf3d83d16fbb9641ea6965d9` | WFU lookup/download/archive/cache implementation members |
| `ev_2d435e2952df871c0a34f3d3dbd5e1345b0a498670e86026d1bd256c2f8d8adc` | Networking assembly identity |

The main evidence export is `private/rea-device-research-evidence.json` (50
records). The independent package worker's export is
`private/rea-firmware-inventory-evidence.json` (17 records); its detailed bounded
inventory is `private/firmware-inventory-report.json`, SHA-256
`b9e0d16baba47596c9adaae11a10edd502cff06c71e61a758721be2e11df65c6`.
These remain ignored, and contain no live-request result from this pass.

The exact XML resource SHA-256 values for the principal contracts are:

| Resource | SHA-256 |
| --- | --- |
| DFU 1.0 | `b9d9bc8662cde3f5170b05ae9cadfd6969086b901675de0d95145e15f8c15875` |
| DFU 1.1 | `8935c7845870dfe1ec83d2b6ae0beaf185b37e0cfce03d4dbaed148b46028928` |
| DFU 2.0 | `0dc567cc7ac41990b1048667568ae552fad21d638b2153438dd1378191950dba` |
| fwUtilityService 1.1 | `c1865c9a90704dbadb19a7355518f1d2eaeded25be49677c7311e5d7495a1dfd` |
| HIID 1.0 | `55f5072842c12c4454861b9771f56ae8464dcc145e7e0f6e678c12566c6aa459` |
| HIID 1.1 | `7da83dea37d022058de6d343070f57bd75f4c3b82a2fdda0aa224393cb9db589` |
| CoreDump 1.0 | `ac914c7edf10be60bb56199589fede0c5adfda1685009dd217adee15598773b4` |

Static CIL/member evidence and local ILSpy decompilation support the client
behavior above; no target assembly was loaded as executable application code.
Full proprietary resources, reconstructed sources and future firmware blobs
remain private. This report does not establish a whole-device firmware dump,
complete service coverage, undocumented command safety, or debug-interface
availability on the current aids.
