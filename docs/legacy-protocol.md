# Direct Oticon remote-control protocol

This is a protocol description, not a copy of the vendor implementation. The source of the observations is the installed Companion 1.8.0 ARM64 split, specifically `Demant.MpHal.LegacyRemoteControlManager.dll`, SHA-256 `d5b0f7a2c3ed17bf8b4e801eedc1aaa290a19e59f02c837689dea8933bb53288`, MVID `727bc5cb-0147-49d5-ad68-384b85758e1d`.

REA metadata/CIL evidence: `ev_2ab7d1d00cf1b2bdecf12294ffeeab3b6fc573f083feedac4ea8b34c150becc3` (summary `ev_4b60ace21bf1149539a196a6af5d0d6c757de98c24eddada0235d28914ee0869`). The selected types are `GattServices`, `WdhHiServiceCharacteristic`, `VolumeCommandData`, `VolumeRangesCommandData`, and `WdhHiServiceClient`. Private ILSpy reconstruction supplies the algorithm interpretation; REA preserves the artifact, member coordinates and CIL anchors. No target code was executed.

## Services and formats

Direct remote service: `56772EAF-2153-4F74-ACF3-4368D99FBF5A`.

| Characteristic | UUID | Observed SDK interpretation |
| --- | --- | --- |
| Main volume | `1454E9D6-F658-4190-8589-22AA9E3021EB` | Two bytes: signed 8-bit level, then 0 = muted / 1 = unmuted |
| Volume ranges | `58BBCCC5-5A57-4E00-98D5-18C6A0408DFD` | At least six signed bytes: main min/max, streaming min/max, tinnitus min/max |
| Active program | `535442F7-0FF7-4FEC-9780-742F3EB00EDA` | One-byte program ID; SDK reads or writes it |
| Available programs | `DCBE7A3E-A742-4527-AEB5-CD8DEE63167F` | Bitmap, least significant bit first, byte index × 8 + bit index |
| Ear | `D28617FE-0AD5-40C5-A04A-BC89051FF755` | Side information; numeric interpretation remains unverified here |

`WdhHiServiceClient` uses GATT writes with response by default for main volume and active program. The same assembly supports additional features, but their presence is not proof this model exposes them. Program-information enumeration is not a purely passive read: the SDK writes a separate selection characteristic before reading metadata. The initial probe does not do this.

## Boundaries

- “Legacy” is the SDK's name. Actual discovery must establish whether Intent 3 exposes this service; this description is not a compatibility claim.
- BLE link encryption and authorization are OS/device concerns. Finding the byte format does not prove that writes will be accepted.
- The modern UTL service is a different, session-based protocol with an application challenge/response. Its operation IDs must not be written into these GATT characteristics.
- Standard Bluetooth VCS (`1844`) uses an unsigned volume and a different mute polarity. It is not established as the same control as Companion microphone volume. Keep their UI and values separate.
- The independent Swift parser rejects malformed states, bounds volume payloads to the aid's reported range, and limits selectable program IDs to the reported bitmap. No automatic setting changes are performed.
