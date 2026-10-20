# Existing program data and new fitted programs

The pulled Oticon Companion 1.8.0 (617548) contains three different concepts:
existing hearing-aid programs, consumer sound profiles/settings, and full fitting
data. The name **Geral**, program ID and user equalizers identify or adjust an
existing program. They do not describe its complete audiological prescription.

This investigation used the owned APKs, statically inspected managed SDK and
decoded configuration resources. It did not send Bluetooth commands, activate a
different session, change hearing settings, execute a target assembly, or attempt
to create a fitted program.

## Findings

| Question | Finding | Boundary |
| --- | --- | --- |
| Can we export data about Geral? | Yes: active ID, name, category, program flags and supported consumer volume/EQ controls have recovered read contracts. | The resulting export is a consumer-controls snapshot, not a complete fitting backup. |
| Can we save a differently named local preset? | Yes. The existing local `SoundPreset` stores volume and EQ for the existing program. | Saving does not allocate a hearing-aid program slot. Applying is a separate user action that adjusts controls. |
| Does the consumer program service add programs? | No creation operation appears in the recovered ProgramControl 2.0/2.1 contracts. | This is a negative within these contracts, not proof that all manufacturer interfaces lack creation. |
| Does `IFittingManager.GetProgramAsync` export the program configuration? | No. Its processor returns the current program name. `SetProgramAsync` changes the selected program. | The API names alone do not imply export/import or cloning. |
| Is fuller fitting readback represented in the SDK? | Yes: `GetDeviceDataAsync` reconstructs a `DeviceData` object; versioned HIID also defines a fitting-data entry. | Neither its availability on these aids nor complete decoding of their fitted program state was demonstrated in this pass. |
| Can we create a new fitted program now? | A verified creation/slot-allocation workflow has not been recovered. | Persistent fitting requires model-specific transformations, compatible data and further protocol work. No guessed slot writes are implemented. |

## Ordinary consumer program reads

UTL service `program_control`, ID `0x0200000E`, recovered versions 2.0 and 2.1:

| Opcode/event | Name | Input/output |
| --- | --- | --- |
| Opcode 0 | `get_active_program` | No input; one fixed-width UInt8 program ID. |
| Opcode 1 | `set_active_program` | One UInt8 ID selecting an existing program. This is not used by the snapshot getter. |
| Opcode 2 | `get_program_info` | No input; raw CBOR value containing program metadata. |
| Event 0 | `active_program_changed` | One UInt8 ID. |
| Event 1 | `program_info_changed` | No fields; invalidate and reread metadata. |

The shipped `GetProgramsUtlCommand` creates a normal MfD operation package on an
activated UTL aid. It reads `info` as a dictionary, takes the **first root-map
value**, then enumerates program-entry dictionaries. The outer map key is not
hardcoded in that wrapper. The inner keys are:

| Key | SDK type | Meaning retained in the export |
| --- | --- | --- |
| `program_id` | UInt32, used as an ID | Unique ID representable as UInt8. |
| `name` | String | Device program name, including a name such as Geral. |
| `category` | UInt32 | Raw category; preserve it without inferring a prescription. |
| `boostable` | Boolean | Reported program capability. |
| `tinnitus` | Boolean | Reported tinnitus-program flag; not inferred from a volume range. |
| `mic` | Optional Boolean | Optional microphone flag; absence remains unknown. |

`getDataUInt` is fixed-width wire data, while `getDataCBORBinary` decodes the
remaining CBOR value. These carriers must not be interchanged. Normal consumer
COMMAND wrapping is already established in
[device-research.md](device-research.md); this getter uses the same application
channel and does not enter an exclusive or update session.

`OticonConsumerPrograms` implements only those two getters, advertised-version
checks and a bounded parser. It preserves root-map wire order, requires strict
field types and unique IDs, rejects duplicate keys/trailing data, and skips
unknown values without retaining them. Bounds include 65,535 payload bytes,
256 program entries, 32 fields per map, 12 nested unknown-container levels and
8,192 parsed items. These are parser limits, not claims about aid capacity.

The legacy GATT program-information cursor is documented in
[advanced-controls.md](advanced-controls.md). Moving that metadata cursor is
different from selecting the active program, but still involves a wire write.
The snapshot controller prefers UTL metadata; its legacy fallback queries only
the current ID and releases the cursor with `0xff`, including after query errors.

## Consumer snapshot format and freshness

`ConsumerProgramSnapshot` is typed JSON with `schemaVersion: 1`,
`scope: "consumer-controls"`, `clinicalFittingIncluded: false`, a capture time,
and one unique left/right entry per captured aid. Each entry contains program
metadata, optional model label, and optional main/streaming/tinnitus volume and
microphone/streaming EQ and optional fresh SpeechBooster state. Volume levels and ranges are signed consumer steps,
not presumed dB. EQ retains eight signed raw steps, its actual step size in dB,
minimum/maximum steps and whether those ranges came from the device.

Unavailable controls are absent rather than zero-filled. There are no serial,
peripheral UUID, HIID, authentication, account or audiogram fields. This format
has no fitting importer and cannot be passed to the manufacturer's fitting
restore API. A local preset and an exported snapshot remain separate operations.

The controller collects fresh values on explicit request, rather than labeling
old displayed values as a new read. It locks current control actions, reads each
aid's active ID before and after the controls, and rereads both IDs after all
queries. Final connection, side and current-ID checks precede publication. A
changed ID/connection rejects the capture. These are sequential consumer reads,
not an atomic DSP snapshot. Failed optional reads remain unavailable and do not
reuse previous cached values. No export selects a different listening program
or turns on tinnitus therapy. Without a local advanced key, useful legacy
metadata/volume can still be read, with EQ omitted and the limitation reported.

## Broader fitting readback and creation boundary

`IFittingManager.GetDeviceDataAsync` accepts a HIPC hardware configuration and
optional end-user-setting scopes. For full retrieval, it requires the aid's
fitting state to be `Completed`. It issues `GetFittingSystemDataChipCommand`,
reconstructs device data through the ProdRegs transformation engine, and then
populates the SDK's chip cache. The `ApplyToCache` branch does not persist fitted
gains; it establishes cache state and may read supporting variables.

The command is supported by `ExclusiveState` and `DeviceUpdateState`, and is
absent from `InteractiveState`. `SessionType.ReadOnly` maps to Interactive, not
Exclusive. Consequently the SDK's full `GetDeviceDataAsync` workflow is not a
drop-in consumer getter. This does **not** establish that every fitting byte is
inaccessible to an interactive session:

- `ReadHiidChipCommand` is supported in Interactive and performs typed reads.
  `GetHiidDataAsync` uses that route for named HIID properties.
- HIID 4.6 defines DIET entry `1009`, `fitting_system_data`, containing version,
  size, checksum, eight reserved bytes and a maximum 4,000-byte fitting-data
  vector. The corresponding memory map places the vector at offset 16.
- Whether these aids return entry 1009 through their ordinary `get_hiid`, what
  it actually contains, and how to reconstruct their full fitting remain
  unverified. The current identification parser deliberately skips this data.

`GetFittingSystemDataChipCommandProcessor` also queries
`end_user_settings.get_eus_scope_info` and reads advertised scopes. Recovered
EndUserSettings 1.1, service `0x02000017`, has read opcodes 0 (scope metadata), 1
(field metadata), and 2 (`get_eus_nvram`: UInt8 scope plus UInt8 ID, returning
CBOR). Scope enumerations are global=0, situation=1 and profile=2. These names
are not proof that a scope is the Geral program. Device-returned counts and
metadata must define any subsequent read; no arbitrary scope IDs are probed.

The fitting `DeviceData` model contains FittingId, HIPC configuration, HIID
selection, ProdRegs, business data and optional end-user settings. Companion's
separate fitting-backup component serializes this using .NET DataContract XML.
It is broader than the consumer snapshot and may contain sensitive fitting or
identity data. Its restore calls `SetDeviceDataAsync`.

`SetDeviceDataAsync` produces `HIConfigurationChipCommand`. That processor can
write audible RAM settings and persist NVRAM, fitting-system data and end-user
settings; persistence options explicitly include audible and background
persist. This is a fitting operation. Recovering that setter does not supply a
correct new-program prescription or prove that adding an entry to a dictionary
allocates a valid program slot.

The separate `ProfileControl` service `0x0200001B` (recovered 1.0/1.1/2.0/3.0)
lists available profiles, selects one, stores/resets trimmers in a profile and
reads/sets the default profile. Its metadata describes situations and existing
profile IDs with category/template labels. No explicit create/add/clone
operation appears in those contracts. `store_trimmers_in_profile` must not be
treated as permission to allocate an unadvertised ID.

A broader search of the 872 decoded configuration documents and selected SDK
sources did not recover a consumer add/create/clone/remove-program contract.
Remaining work includes the compatible fitting model, actual fitted data,
program capacity/slot allocation, DSP-state schema and clinically meaningful
transformations. Noah itself supplies hosting/data exchange rather than the
Oticon fitting algorithm; see [noah-investigation.md](noah-investigation.md).

## Original Companion languages

The original APK declares **33 locales** in its compiled
`res/xml/locales_config.xml`:

`bg`, `cs`, `da`, `de`, `el`, `en-GB`, `en-US`, `es`, `et`, `fi`, `fr`, `hr`,
`hu`, `is`, `it`, `ja`, `ko`, `lt`, `lv`, `nb`, `nl`, `pl`, `pt-BR`, `pt-PT`,
`ro`, `ru`, `sk`, `sl`, `sv`, `tr`, `uk`, `zh-Hans`, `zh-Hant`.

There are 33 matching app-UI satellite assemblies, including fallback cultures
`en`, `pt` and `zh`. Other framework-only satellite languages are not counted
as app languages, and the language split APKs installed on this phone are not
the full locale inventory. This establishes language availability declarations,
not completeness or quality of every translated string. Aapt2 36.0.0 decoded
the compiled XML; exact tool/APK/resource hashes remain in the ignored locale
inventory.

## Evidence and verification

Source APK SHA-256:
`acc8f305dab947806e997c989c6759e00b2d6bbf49589fe1efe43a69b722c767`.

| Assembly | SHA-256 / MVID |
| --- | --- |
| FittingManager | `341180274d1e6de979f5869f8abf1069eef5041faeeba377914f4fc4ba9da43c` / `a20b6a97-94f1-41ef-83e6-4eaf3f4006b7` |
| FittingManagerInterface | `302794b3890973d9e46f16da4646faf775389b0a15ea32a18167f2a02948d5d7` / `f4f9d8c6-1919-44d3-bc1c-1d3ddaeb424f` |
| HearingInstrumentContracts | `440750737524515efa0d759120583561f8c83a151b1c33cb962fc1fd6278ceea` / `e005cc01-39a0-495d-98f0-8a45c6affa27` |
| Hal.Session.Contracts | `b527a863ca811560bc9a840d368a2025eca66b067929a48c14529479de16aefc` / `07cddf4c-6bed-42b1-8c2f-4ce5b5bd7896` |
| Hal.Wrapper | `e13600d24d5f44d6f173be4d1df3822b294a7b2341c986ea03dbffe4b00dcfd8` / `0ca344f6-16d9-4f18-9cc2-80c7ab5a6137` |
| ChipService | `21cd01da616403f3f843dc4b35fd49957180c4f072728d23c6fe9d9018a1fae3` / `e07387c0-da1f-4d24-9fe2-37ff70fa3eff` |

| REA evidence | Scope |
| --- | --- |
| `ev_35127b785b2a2aeed1c34566fc58b79e6a276aa0e3e68c3d3aa1bd03c935bead` | ProgramControl service names and exact metadata keys. |
| `ev_26be070d4693cc5f40469bc0937262a8c29f38baa4113a2849eb0181edc7405d` | Consumer program reader and metadata conversion. |
| `ev_f7c4d7653cdbc8cd0e2167589a7771ac6c37b60c9880c28d18393fbc09916adf` | Fitting interface and retrieval options. |
| `ev_4d1bc9dd47149a86430fd11666db537ee94ee4563ad16701bc89bf0295807ffb` | Fitting manager APIs and fitting-data command construction. |
| `ev_4b69cf4c8ff0826b3a6f09957477489e7f9cff543aac98d7df55f69f3c51c8fa` | Fitting manager async CIL, full read/cache flow and restore entry point. |
| `ev_04930f26518f12a9fbd58092975b366ba3613c8cfd36b08db27db3c6d6d1ecca` | `DeviceData` typed fields. |
| `ev_6d2b0709a21a330f89f528cf57ff7e1f78a3310a1c4379cc49395fe7292860b2` | Fitting backup/repository serializer. |
| `ev_61259bd52d4760a7db18965403ff9c96b1d506470354e6fbb44ef076e9b43752` | Supported controller commands, ReadOnly session mapping and cache branch. |
| `ev_276bf6358b7c0f7df4093dbfcf0cf7ca6eda8701fdc8006f932c391b326f4a89` | Fitting read/EUS async implementation. |
| `ev_db64eb63b920d8c268704d0ccf379653d5a5d9be87ff592705570f8936cec1b1` | Interactive typed HIID read processor. |
| `ev_98cb4124a078c438cd1dee94020631940fd9be0d6bdeab93ee84a4e5a2460e38` | Current-program name processor, selection and configuration setter. |
| `ev_ec22614265b0d88c0f7df3c43e26cefcef7fab7ce018881d16d2c6413c31f673` | Existing ProfileControl metadata parser. |

Build-local fitting-manager tokens: `GetDeviceDataAsync` `0x0600001d`, its
`MoveNext` `0x06000092`; `SetDeviceDataAsync` `0x0600001c`, its `MoveNext`
`0x0600009e`; `GetProgramAsync` `0x06000027`; `SetProgramAsync` `0x06000028`.
They require the matching SHA-256 and MVID above.

The ignored `private/rea-program-data-evidence.json` retains the REA records;
`private/program-data/provenance.json` retains exact XML hashes and
`private/program-data/locale-inventory.json` the compiled locale provenance.
The two principal ProgramControl XML SHA-256 values are
`85e4fa2cc1414d5990aaf057abb0d8c05da052dea4cd255ef6d21f4fd16179f5`
(2.0) and
`4d59b36fca9a76047776e82256ffcc09ecb96689134aed4af633c5df1e02531e`
(2.1). No proprietary reconstruction or raw user fitting data is published in
this report.

Focused synthetic tests cover supported versions, metadata types, map order,
duplicate IDs/keys, all truncation points, parser bounds, explicit JSON scope
and range/privacy validation. Build and hardware verification are performed by
the parent workflow; static recovery alone does not establish runtime support
for program metadata on a particular aid.

## Native verification in 0.6.0

Fresh snapshots were read successfully from the tested Intent 3 left and right
aids individually. Both reported Geral and supplied current consumer volume and
both EQ sources. The UTL metadata operation was unavailable in these attempts;
the legacy metadata fallback completed and released its selector. This confirms
the consumer read path, rather than establishing access to full fitted-program
bytes or clinical program creation. Two simultaneous live connections were not
stable in this run; see [hardware verification](hardware-verification.md).
