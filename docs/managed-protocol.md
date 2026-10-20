# Managed protocol investigation

These findings describe the installed Android artifact, not observed behavior of
the hearing aids. No hearing settings were changed for this investigation.

## Recovering the managed code

Oticon Companion `com.oticon.app` 1.8.0 (617548) contains .NET MAUI code. The
arm64 APK includes a Mono AOT companion for many assemblies and a
`libassembly-store.so` carrier. The carrier's `payload` ELF section holds an
XABA format 3 store with 477 assemblies. Its SHA-256 is
`93fd13c99e9b09d3cd028ade6c884bc96b6dcd52c2d2ed2b1fa20206176eb7f9`.

The XALZ records contain compressed PE images with intact managed metadata and
CIL method bodies. Native disassembly is therefore unnecessary for the control
paths examined so far. All 477 were extracted without loading target code.

```sh
python3 scripts/extract_managed_store.py \
  private/apks/split_config.arm64_v8a.apk private/managed/assemblies
```

The extractor writes an ignored manifest with per-image hashes and original
store offsets. Its format references are the upstream [.NET Android assembly
store documentation](https://github.com/dotnet/android/blob/main/Documentation/project-docs/AssemblyStores.md)
and [ELF carrier documentation](https://github.com/dotnet/android/blob/main/Documentation/project-docs/ApkSharedLibraries.md).

`Demant.MpHal.MediumService.Common.dll` is AnyCPU CIL, version 14.1.1.0,
targeting .NET 10. Its SHA-256 is
`b930997ffa54e4c9321f0165ce6cae35060a10510276cf1987f4292690eca3b6`,
and its MVID is `6ca75a9a-96af-4bd4-b5d9-74a3e9d4d3aa`.
REA identity evidence:
`ev_642344940f33c00f4658ce6cdeac2f8186859d2c26b9c80bb0d89bec1f9f8b1f`.

`Demant.MpHal.Ninjago.dll` contains the Unified Transport Layer (UTL). Its
SHA-256 is `f16dd8e10292d0c2c5c2e30c5ead787026531a9c93620ec382cc4ac2d02e17be`,
and its MVID is `e7e0264d-0df4-4155-a987-6560542bdcc0`.

## UTL service inventory

These identifiers come from the Android client and platform-neutral transport
implementation. Device discovery must establish which services the actual aids
expose; the presence of client support does not establish hardware support.

| Role | UUID |
| --- | --- |
| UTL service | `BA50125D-0806-42AB-8BF1-22E0B954A8FA` |
| Channel control | `43C8465E-BA80-451D-8098-57716B4FDBE5` |
| GATT information | `E6C02A45-A0E5-41F2-9CD1-C1FAB9EC0C3E` |
| Channel 0 client input | `855C8579-17B7-40A8-BE4F-AD574357F797` |
| Channel 1 client input | `6D6A8B8F-544E-4EF1-BE91-C60DB8E70884` |
| Channel 2 client input | `F6C47754-8BD2-4CC2-BF0B-FDEE78FA812E` |
| Channel 3 client input | `46C9AFB1-8FA2-4594-AB2E-F5576F6BC484` |
| Channel 0 server output | `5EB7FF93-EBEB-479C-85AB-526F25482545` |
| Channel 1 server output | `ED5F901B-FB08-452C-8D01-46B6C9C1BCC5` |
| Channel 2 server output | `80911332-EAD5-4DA0-9BFA-4D6286032E25` |
| Channel 3 server output | `689E73AF-BCAC-4280-920D-4710CE2FBB68` |
| DetectInfo service | `4F6CF751-176C-4DE1-A25E-D218F1901CCF` |
| DetectInfo version | `C7E127D3-0215-43E6-BC26-3F331D3747A2` |
| DetectInfo request | `19D82B8B-F66F-43DF-A843-8508E2DA564A` |
| DetectInfo response | `6C9BB68D-1E4E-4073-944F-6B06D849446D` |

The twelve-byte GATT information value contains transport major/minor,
adaptation major/minor, adaptation MTU (big-endian UInt16), free connections,
maximum channels, and four channel-status bytes. Each status byte uses its top
two bits for status (1 = open, 2 = closed), with the low two bits holding the
last-error code. The client chooses an adaptation MTU from the device's value
and the physical ATT limit, bounded to 17–244.

REA GATT-info decoder evidence:
`ev_6d7ecc7bf1b5969bee018ec04b9f526b92bce727991553510386d396f952cb22`.

## Bonding and channel authentication

The client first creates an OS Bluetooth bond, subscribes to control and the
chosen channel output, and opens an application channel. A BLE connection or
bond alone does not complete UTL authentication.

The inspected implementation includes an application-embedded 16-byte shared
secret and uses random 14-byte client challenges. Server authentication checks
the first 14 bytes of SHA-256(server challenge || client challenge || secret).
Client authentication reverses the challenge order. This path did not call
cloud authentication. Whether a given device/firmware accepts this flow remains
unverified until an intentional runtime test.

The secret and reconstructed proprietary implementation remain in ignored
private analysis files. They are not copied into this repository's source,
documentation, or test fixtures.

Control frames carry an opcode followed by a big-endian UInt32 client ID
(the official app uses its process ID). Open-channel fields are channel,
initial sequence, initial receive credits, and endpoint. Authentication fields
are a channel/key-index byte and fourteen challenge/hash bytes. The client uses
opcodes 1 (open), 2 (close), 3 (client challenge), 4 (client proof); control
notifications include 0x42 (server hash) and 0x43 (server challenge).

REA authentication evidence:
`ev_126753d15d5503706d6abd4140384ca24b8f91ddd988b175184aa7a1b0cf9f1d`
(`CreateHash` token `0x060001ea`, `ValidateServerHash` token `0x060001e9`),
and SHA-256 provider evidence:
`ev_f65e04903d508e578ec50690b9235b002c53565e89943487d90b2d97caf2e2f9`.
Tokens identify only the recorded build and MVID.

## Message framing

UTL has distinct GATT adaptation, transport, and service-message layers.

- GATT data begins with one byte: credits in the high nibble, modulo-16
  sequence number in the low nibble. A high nibble of 15 marks control PDUs.
- Transport frames begin with type/flags and a big-endian UInt16 payload
  length. Data frame type is 1; continuation is 2; final flag is 0x20. Fragmented
  messages have an additional total-length field in their first frame.
- Service messages begin with a flags byte, message identifier, service handle,
  and command code; data-only continuations omit the command code. Flags encode
  frame type at bits 7–6, request/response/event at bits 5–4, and fragment/end
  markers at bits 3–2.
- Service discovery (service 0, command 1) returns eight-byte records: big-endian
  service ID UInt32, runtime handle, major/minor, and status. A status of 0xFF
  marks an available service. Commands must use the
  discovered runtime handle, rather than treating the service ID as a handle.

REA framing evidence:
`ev_1ed41151aa4adc23c64dd2d8b3d30e26e23e42d25b1e156c10cb9970fa09c368`.
The app's XML service contracts supply operation numbers and typed arguments;
they must be interpreted with the discovered service version.

All multibyte fields above use Ninjago's big-endian `ByteBuffer`; the XABA
assembly-store container itself uses little endian. Response status separates a
three-bit class and five-bit detail: completed success is 0x40; accepted 0x41
does not mean the operation completed. Service discovery may return a partial
registration status while services initialize. The official implementation
retries partial-registration/service-unavailable results with bounded
exponential backoff for at most 15 seconds.

The first outgoing transport exchange negotiates a transport MTU, independently
of GATT adaptation MTU. Its request is control type/final, payload length 2,
identifier 1, opcode 1, and requested MTU UInt16. Response opcode 2 has MTU
UInt16 followed by status. The original client falls back to a transport MTU of
64 when negotiation fails; the current codec reports the error explicitly.

REA byte-order, service discovery, status and negotiation evidence:
`ev_58527feb5ec3769d1e6232195c310709743c9578a5e593b047f928a99d837df6`.

## Optional local codec

`Sources/CompanionCore/UTLProtocol.swift` is an independently authored, pure
codec. It has no Bluetooth operations, never starts authentication, and contains
no key. It can decode GATT info/control, manage sequence/credit accounting,
reassemble fragmented transport and service messages, decode service discovery,
and build read-only volume/program queries using runtime service handles.
Authentication-frame encoding requires an explicit fourteen-byte challenge or
proof; it does not compute a proof or load a secret.

Incoming and outgoing adaptation sequence numbers both begin at the initial
sequence in the open request and wrap modulo sixteen. Outgoing data waits for
server-granted credits. Incoming data consumes one of the client's receive
credits; credit PDUs do not. The shipped defaults grant 100 receive credits and
replenish when fewer than 50 remain. GATT control PDU 0x81 grants sending
credits; 0x83 requests discarding some, answered with opcode 2 and the actual
count discarded. A credit grant with count zero is a keepalive. Returned reply
packets remain data until an explicit transport integration sends them.

Volume service `0x0200000D`, contract versions 1.1–1.3, uses command 0 for a
signed-eight-bit current/minimum/maximum triple. Program service `0x0200000E`,
versions 2.0–2.1, uses command 0 for one unsigned-byte program ID. These are
version-bounded static mappings, not evidence of a discovered UTL service
registry on this hardware. Service responses carry status in the message code
field; they do not echo the request opcode. The codec rejects non-success and
malformed/out-of-range values.

The volume/program contracts explicitly declare status 0xD9 for a missing
transaction. A correctly encoded query may therefore still require the
appropriate runtime session/transaction state. The pure codec does not open a
fitting session or infer that state from a Bluetooth connection.

The codec deliberately rejects secure transport bodies, fragmented events,
unknown control PDUs and unknown service versions. This is a tested foundation
for future advanced controls, not a complete replacement for the SDK. The
runtime app currently uses the independently discovered legacy GATT path,
which avoids a proprietary UTL channel and its embedded secret.

Validation: all 477 extracted files passed SHA-256 and PE-signature checks; six
synthetic Python unpacker tests passed. Thirteen UTL Swift tests cover byte
order, status handling, every split of a synthetic ATT stream, both levels of
fragmentation, sequence wrap/error rollback, credit exhaustion and discard,
dynamic handles, signed volume bounds and truncated/malformed messages. The
full local Swift suite passed 24 tests at this development point.

## End-user settings boundary

The SDK also exposes `end_user_settings`, service `0x02000017`. Its scheduler
distinguishes persistent NVRAM writes from transient RAM writes and selects
`set_eus_nvram` or `set_eus_ram` based on the target location. Those payloads
contain model-specific setting values; they are not interchangeable with the
simple remote-control volume/program commands. No generic memory/settings
write interface is exposed by the prototype.

## Scope and remaining work

This is static artifact evidence plus a local unpacking/decompilation result.
It does not establish that a Mac completed UTL bonding, authentication, remote
control, or audio streaming. The legacy direct GATT service and standard LE
Audio services provide separate, potentially simpler routes for this hardware.
Prefer verified read-only GATT discovery before opening proprietary channels.
Fitting, firmware-update, memory-map, and persistent end-user-setting operations
are outside the initial companion prototype.
