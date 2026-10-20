# Software, hardware and read-only device details

Software and firmware revisions are separate reported fields. Open Companion
does not copy the firmware value into an empty software field. A missing value
remains unavailable until the relevant read succeeds.

## Verified sources and names

| Displayed detail | Standard Device Information | HIID fallback or additional data |
| --- | --- | --- |
| Software revision | `180A/2A28` | Entry 2019, 18-byte string at offset 0 |
| Hardware revision | `180A/2A27` | Entry 2009, 18-byte string at offset 36 |
| Firmware revision | `180A/2A26` | Entry 2007, 18-byte string at offset 0 |
| Manufacturer | `180A/2A29` | Entry 2009, 18-byte string at offset 0 |
| Model | `180A/2A24` | Entry 2009, 18-byte string at offset 18 |
| Runtime memory-map version | — | Entry 1012, three individual version bytes |
| Release-package version | — | Entry 1012, three individual version bytes |
| Primary application version | — | Entry 2020, three bytes at offset 0 |
| Maintenance application version | — | Entry 2020, three bytes at offset 3 |

The installed SDK's `ReadSoftwareRevisionStringAndAppStateValidationHandler`
explicitly reads `2A28` and UTF-8 decodes it as `SoftwareRevisionString`.
The standard software and hardware characteristics were already on this
project's read allowlist, but their results were previously absent from the
per-aid display model. Their values now remain separate from `firmware`.
The model identifies whether a software/hardware value came from DIS or HIID.

HIID comes from the existing read-only `detect_info.get_hiid` operation,
service `0x02000004` versions 1.0–1.2, opcode 3. The envelope and serial handling
are described in [device-identification.md](device-identification.md). No new
NVRAM read, fitting session or firmware-transfer operation is required.

The six supported HIID layouts are 3.4, 3.5, 3.7, 4.3, 4.5 and 4.6. In the
supported **3.x** layouts, entry 1012 has default-production settings at offset
0, runtime memory-map version at offset **3**, and release-package version at
offset **6**. Supported **4.x** layouts removed that first triple: runtime is
at **0** and release is at **3**. Treating these layouts alike would mislabel
the versions. The other entries in the table have the same verified offsets
across those six layouts.

The shipped `WirelessNameStringReader` uses `opString_VectorInt`: it reads at
most the mapped 18 bytes and stops at NUL. `TripleVersionReader` maps its three
individual bytes to a `Version`; this is not a packed integer or UTF-8 string.
Open Companion additionally rejects invalid UTF-8/control characters. Absent
entries remain nil; a truncated optional slot invalidates that field and
reports its label while leaving other valid metadata available.

`detect_info.get_version` (opcode 1) is **not** used as the software revision.
The inspected `UtlDetectionProtocol.VerifyVersionAsync` reads its first
major/minor pair to validate the detection-service protocol version. Its
presence does not establish the hearing aid's user-facing software version.

## Additional bounded reads

The explicit **Read device details** action reads metadata independently of EQ.
It uses the current owned consumer session or opens one free channel through
the already verified nonexclusive consumer lifecycle. Each request uses an
ordinary COMMAND transaction and waits for its response/transaction completion.
The action shares existing per-aid/group busy gates; reads never change volume,
program, EQ, fitting or firmware state.

| Read | Discovered service/version | Operation | Result |
| --- | --- | --- | --- |
| Identity and versions | `02000004`, 1.0/1.1/1.2 | `get_hiid`, 3 | Bounded CBOR map; only allowlisted metadata retained |
| Battery health | `01000007`, 1.0/1.1/2.0 | `getInfoSlow`, 1 | Four BE32 fields: lifespan, threshold, slow current draw and full-charge capacity |
| Crash-dump counters | `0200000C`, 1.0 | `info`, 0 | Two BE16 fields: last dump counter and stored crash-dump count |

Battery health fields do not provide remaining runtime. Their absolute units
have not been established; they must not be relabelled as hours or mAh. The
existing charge/current estimate is documented in
[battery-telemetry.md](battery-telemetry.md).

Crash-dump counters are counts, not byte sizes. The official consumer
`GetCoreDumpIdsCommand` reads `core_dump.info` from activated UTL aids using an
ordinary MfD package: Shared resolves to Interactive, and the transactional
operation is wrapped in COMMAND. Open Companion reads opcode 0 only. It does
not retrieve dump IDs/content, clear dumps, read flash or change device modes.

The UI can inspect the current advertised service ID/version/availability list.
Advertisement alone does not mean Open Companion implements or may call every
service. This list is cleared when its channel is invalidated or disconnected.
Metadata requests report per-field failures and keep unavailable values absent.
They do not start periodic health, diagnostic or identification polling.

## Shipped-artifact provenance

Analysis uses the locally pulled Companion 1.8.0 (617548) assemblies and decoded
resources. REA inspection is static and does not execute those assemblies.

| Artifact | SHA-256 / MVID |
| --- | --- |
| HIConnectionManager | `ea66a053e8224f8bf09a4996903c35eba90f3e03297858073ae208f25968818a` / `5d13a389-7f42-4722-8532-aea6f8373fdf` |
| Ninjago | `f16dd8e10292d0c2c5c2e30c5ead787026531a9c93620ec382cc4ac2d02e17be` / `e7e0264d-0df4-4155-a987-6560542bdcc0` |
| MetaxRuntimeModel | `c38188c38606d15eda95fd2752f055825d4c5f12e2bdf41b6ab8e7624bb922f5` / `1fcde86f-b9ea-44f2-a2d4-c8d34e654504` |

| REA evidence | Scope |
| --- | --- |
| `ev_8defc901b350b539d0640cd930cbbc4244e388a4454420d74ece1ebac1d0fec8` | Actual async software-revision read path, including DIS UUID strings |
| `ev_1efb1737e67711ea786325322ca93f2aa64c7759f3ee101baba0c8a57aca8259` | Async detection-map decoder, HIID envelope and version handling |
| `ev_e0be821f309556314f9528a492178cfeabbaed48e072b885b0aa740ad5277080` | UdaContext string/version conversion CIL |

The complete evidence stays ignored in `private/rea-device-metadata-evidence.json`.
Layout comparisons and resource hashes are in
`private/metadata-resource-evidence.json`; the six memory maps are
`318-HiidMemoryMap-3.4.xml`, `339-HiidMemoryMap-3.5.xml`,
`360-HiidMemoryMap-3.7.xml`, `381-HiidMemoryMap-4.3.xml`,
`404-HiidMemoryMap-4.5.xml` and `427-HiidMemoryMap-4.6.xml` under the ignored
decoded-resource directory. The matching interfaces/mappings and
`434-HiidReaders.6-4.6.xml` / `435-HiidReaders.7-4.6.xml` establish the field
names and conversion functions. The core-dump contract is resource
`465-UtlServiceContracts.core_dump-1.0.xml`; its consumer-session provenance is
covered by [device-research.md](device-research.md).

## Verification boundary

Synthetic tests cover version-specific offsets, separated software/firmware
fields, NUL termination, malformed optional slots, DIS namespace isolation,
fallback precedence, per-aid state, disconnect clearing, diagnostic version/
length checks and exact consumer transaction ordering for these read opcodes.
No real identifiers or telemetry values are fixtures. The coordinating agent
owns the full Swift build/test run and later live reads. Until those reads are
recorded, newly exposed hardware/software strings, health and crash-dump counts
remain statically recovered capabilities covered by synthetic fixtures, not
claims of physical-device verification.
