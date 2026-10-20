# Per-aid serial number fallback

Companion's serial number comes from `HIID.SerialNumbers.serial_number`.
`HalInstrumentConverter` reads this field when constructing
`DetectedInstrumentIdentificationData`; it does not obtain the display serial
from standard Device Information `180A/2A25`. A device that omits that standard
characteristic can therefore still expose its serial through detection data.

## Proven read path and envelope

The packaged `detect_info` UTL service is `0x02000004`, versions 1.0, 1.1, and
1.2. Opcode **3**, `get_hiid`, has no inputs and returns a Binary output through
one `getDataBinary` action. The actual Metax decoder copies all remaining raw
operation-payload bytes; it adds no scalar length prefix, CBOR vector, or nested
byte-string envelope.

`DetectInfoInterceptorBase` passes that output directly to
`DetectInfoDecoder.DecodeDetectInformation`. Its opcode-3 branch treats the
deserialized **root CBOR map** as HIID. Opcode 0 is different: it returns the full
detection map and unwraps a `HIID` property before decoding. Audifern uses
opcode 3 and does not guess a wrapper or strip an arbitrary prefix.

The shipped `CborSerializer` converts integer map keys to decimal strings. It
converts CBOR byte strings into its internal hex representation, and
`HiidObjectToBytes` converts those back to bytes. Thus the relevant wire entries
are:

| CBOR key | Value | Meaning |
| --- | --- | --- |
| 1001 | Two-byte byte string | HIID interface major/minor |
| 2003 | Four-byte byte string | This aid's serial number |
| 2002 | Byte string, separate entry | Production serial, **not** the displayed aid serial |

Numeric keys and their text forms are accepted as in the SDK. Duplicate keys
after that normalization are rejected. The decoder initially retained only
version and serial. Its later metadata allowlist also retains the documented
version/model fields described in [device-metadata.md](device-metadata.md);
unknown entries remain bounded and skipped. It does not retain fitting IDs,
fitting credentials or companion IDs.

HIID interface/memory-map/reader resources prove the 2003 layout and the same
serial conversion for versions 3.4, 3.5, 3.7, 4.3, 4.5, and 4.6. Other versions
are rejected until checked. HIID 3.2 has an older reader and is intentionally
not treated as equivalent.

## Serial conversion

The reader treats all four zero bytes as no serial. Otherwise:

- If byte 0 has its high bit set, or its high nibble is zero, the low 28 bits
  form a decimal number padded to at least eight digits.
- Otherwise, the low 30 bits form six successive five-bit indices into
  `0123456789ABCEFGHIJKLMNPRSTUVWXZ`.

This is the resource's serial formatting, not ASCII decoding, a Bluetooth MAC
address, the other aid's serial, or an inferred product identifier. Test
identifiers are synthetic. Live serials and raw HIID data must not be appended
to public event logs or committed fixtures.

## Dedicated GATT alternative

The same SDK also provides a separate DetectInfo GATT transport:

| Role | UUID |
| --- | --- |
| Service | `4F6CF751-176C-4DE1-A25E-D218F1901CCF` |
| Version, two bytes major/minor | `C7E127D3-0215-43E6-BC26-3F331D3747A2` |
| Request | `19D82B8B-F66F-43DF-A843-8508E2DA564A` |
| Response notifications | `6C9BB68D-1E4E-4073-944F-6B06D849446D` |

The SDK enables response notifications, writes the one-byte operation code
(for `get_hiid`, `03`), and reassembles notifications. Their first byte uses
`0x40` for first fragment, `0x80` for last fragment, and six low bits for a
wrapping fragment index. The first fragment also contains an opcode byte that
must match the request. Only the remaining bytes are CBOR payload. Later
fragments increment the low-six-bit index modulo 64. The normal consumer UTL
session already available in Audifern avoids introducing this second
transport solely for serial lookup.

## Static evidence and validation boundary

All source evidence is from the locally pulled Companion 1.8.0 (617548), without
executing Android/Windows targets or performing new hardware operations.
Private artifacts and full evidence are ignored. Tokens below are build-local.

| Assembly | SHA-256 / MVID |
| --- | --- |
| `Demant.MpHal.Ninjago.dll` | `f16dd8e10292d0c2c5c2e30c5ead787026531a9c93620ec382cc4ac2d02e17be` / `e7e0264d-0df4-4155-a987-6560542bdcc0` |
| `Demant.MpHal.MetaxRuntimeModel.dll` | `c38188c38606d15eda95fd2752f055825d4c5f12e2bdf41b6ab8e7624bb922f5` / `1fcde86f-b9ea-44f2-a2d4-c8d34e654504` |
| `Demant.OneApp.Lib.Hal.Wrapper.dll` | `e13600d24d5f44d6f173be4d1df3822b294a7b2341c986ea03dbffe4b00dcfd8` / `0ca344f6-16d9-4f18-9cc2-80c7ab5a6137` |

| REA evidence | Scope |
| --- | --- |
| `ev_06b072c3c6c640a52145bf33de6255fdbee6e4f9715c8bc3aef31df5942a0b82` | DetectInfo decoder, GATT transport and fragment parser members |
| `ev_55164980ce138b79c13e175da98e719db9af9b1e92862542ecb98dc516d71c27` | Async implementation bodies of DetectInfo read and decode |
| `ev_97d9b73015013e115044eff6e418712c233fd0b0658af36ac5fdc4afac356b80` | Actual CBOR deserializer and byte-string conversion calls |
| `ev_67fab42dc8da382cf09311866e09decc142626537b7a3f011eb573e36e838e55` | Async implementation's HIID/version-key and GATT literals |
| `ev_136c370d417b0b3a21aa61c4edfad759fc84ded74f2abca824eb050a44038e15` | Metax CBOR serializer members |
| `ev_3094af55094fbf5ab6a83c20e610ff82006cb380a1bcfbe20ef6d38feeaebbaf` | Display-identification conversion members |
| `ev_0de75e402fd1f857d2bda52c9d63d66e018560f6e721c7490f3b72545053d123` | Exact `HIID.SerialNumbers.serial_number` field key |

Relevant Ninjago method tokens include `DecodeDetectInformation` `0x060008e6`,
its async `MoveNext` `0x06000cba`, `HandleNotificationReceived` `0x060000ec`,
`IsFirstFragment` `0x060001b1`, and `CheckIfNotificationHasCorrectOrder`
`0x060001b5`. The full retained bundle is
`private/rea-identification-evidence.json`.

Representative resource hashes:

| Resource | SHA-256 |
| --- | --- |
| `470-UtlServiceContracts.detect_info-1.2.xml` | `3f533772fed0a14e23db98e4d90b4b53b5b0d21fc18f0a73a65f8d440dff2684` |
| `402-HiidInterface-4.5.xml` | `f3ac5a09c0878d7be6df92ff3b2942f0cf5e4c42a599b61b3480d1b0467a680d` |
| `403-HiidMappings-4.5.xml` | `567b6bedd905a9c7e030db110a698a39b70d95ebfb6dbaceb6db14e54c2ee8f8` |
| `404-HiidMemoryMap-4.5.xml` | `6b6f165b6b392885cfa953f8adb69a439007988c1b3f3cd6e93554f1c171360c` |
| `409-HiidReaders.4-4.5.xml` | `24ac84692ca6c98cb73d8bde32419a9358b49de9948a4f4f95eab8d9d0192ac3` |

The pure codec's seven tests cover wire maps, version gating, both serial
formats, absent serials, unrelated private fields, malformed/duplicate entries,
and parser bounds. They passed within the coordinated 111-test Swift suite.
Subsequent real reads returned distinct serial numbers for both connected
Intent 3 aids and populated their individual native device-information fields.
Actual serials and full identification records stay private; retained evidence
and remaining validation limits are in [hardware verification](hardware-verification.md).
