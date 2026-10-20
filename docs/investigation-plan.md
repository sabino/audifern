# Audifern investigation

Target: installed Oticon Companion `com.oticon.app` 1.8.0 (617548), acquired locally over authorized Android USB on 2026-10-20. Scope is a native macOS BLE remote/inspector for the owner's hearing aids. Audio transport and clinical fitting are separate questions.

## Questions and evidence

| Question | Needed evidence | State |
| --- | --- | --- |
| Exact app and connected aid identity | APK metadata, hashes, passive phone state | App confirmed; aids reported as Intent 3 |
| Where BLE logic lives | DEX inventory, native split, managed metadata | MAUI/Mono assembly store identified |
| Discovery, services and characteristic roles | SDK call paths, advertisements, actual GATT discovery | Confirmed on both aids; see hardware report |
| Pairing, encryption, access and simultaneous phone connection | SDK security paths and bounded Mac connection | Existing Mac bond permits reads; phone coexistence observed; fresh pairing untested |
| Battery, volume, program and status messages | Serialization/response code and observed values | Direct reads confirmed; volume/mute physically confirmed; current program name Geral read from both aids |
| What can run on macOS | CoreBluetooth build, permission and hardware checks | Native build and direct hardware reads succeeded |
| Runnable independent prototype | Native source, local tests and bounded hardware results | Built and running; both aid connections plus volume/mute confirmed |
| Microphone and streaming EQ | Versioned SDK contracts, live authentication and readback | Consumer UTL session and COMMAND wrapper implemented; see advanced-controls and hardware reports for runtime status |
| Named profiles | Consumer program APIs versus local setting snapshots | App-local presets implemented; creating fitted aid programs is not established |
| Audiometry records | Measurement semantics, persistence and published schema | Native editor, JSON records and schema-tested HIMSA Audiogram 502 export implemented |
| Supplied Noah installer and fitting path | Static extraction, managed/native module APIs and official architecture | Noah host/database inspected; Oticon fitting module absent from examined inventories; official Genie route requires MyOticon |

Private originals, decompilation, captures, and evidence bundles stay under ignored `private/`. Tracked reports distinguish shipped-artifact observations, runtime observations and inferences. No fitting, firmware or hearing-level changes are part of the initial probe.

## Initial evidence

- Package metadata: REA `ev_1b45898548217c16ca7044aa5236b5948873105a5df2ab05ef76ef2bd83bb199`; derived summary `ev_3d485ad74b5617a1c3b50cc9bb0303429818a86ce2d6ba74a0418003407723ed`.
- APK inventory: REA `ev_46eef121b9736dbd8c7e6c81d9c65aace8ed6382071cb5ede48385a3620d7db6`; graph manifest `agm_3c1d01c5f3c69cd7838a45b1beb3ea89b5d4432c668d43a573ccc7da7a7464db`. Central-directory inventory is not signature verification.
- Base APK SHA-256: `acc8f305dab947806e997c989c6759e00b2d6bbf49589fe1efe43a69b722c767`.
- ARM64 split SHA-256: `745306fd82df71efec9e985a5b55066fae41fe0bbf6cdcd0f11b5b148ad82cf5`.
- Android Bluetooth bridge class-name search: REA `ev_8a043cfd83d7f504f09db3c5e6c546649cac6eb9341995ad77699405242460d9`. Class names alone do not establish protocol semantics.

Static decompilation does not prove a command works on the connected hardware. The initial probes used only discovery, explicit connections, service inventory and read-only information. After verifying the direct command path, the native app added user-initiated volume/mute and available-program selection. Volume and mute were physically confirmed by the user. Later consumer UTL reads are documented separately; fresh pairing and clinical programming remain untested.

Complete retained REA records are saved in three ignored bundles: `private/rea-evidence.json` (main APK/direct-control analysis), `private/rea-managed-evidence.json` (managed UTL analysis), and `private/rea-resource-evidence.json` (configuration analysis). These contain proprietary target material and are not Git deliverables.

Subsequent feature investigations retain `private/rea-sound-profiles-evidence.json`, `private/rea-advanced-evidence.json`, `private/rea-consumer-session-evidence.json`, and the evidence bundles under `private/noah/`. Each report records the applicable artifact identity and evidence scope.
