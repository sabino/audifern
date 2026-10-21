# Automatic connection and Mac audio

Open **Settings → Connections**. Automatic connection starts disabled. The app
continues running in the menu bar when its main window closes; it must be
running for this automation to work. This does not register a login item.

## Reconnect

Choose **Use connected hearing aids** after connecting your own aids in Devices.
Enabling automation can also remember the currently connected, recognized pair.
Only those Mac-local peripheral identifiers and left/right sides are remembered;
names and nearby advertisements are never used to select an unknown aid.

- **Retry when hearing aids are nearby** keeps trying while this Mac is awake
  and unlocked. Cached identifiers use Core Bluetooth connection requests.
  When discovery is needed, service-filtered scans last four seconds and are
  separated by at least 30 seconds. Failed connections back off through 30, 60,
  120 and 300 seconds. Connected aids do not cause background scans.
- **Try after waking or unlocking this Mac** opens a 45-second attempt window.
  Turn off nearby retries to use only this trigger.
- **Disconnect app controls when this Mac locks** optionally cancels Audifern's
  own connections. macOS may retain its separate audio connection.
- **Pause app connection**, also in the menu bar, disconnects Audifern and
  suspends automatic retries. Pause survives a restart and an unlock. Resume or
  manually connect to end the pause. A manual Disconnect also pauses retries,
  so the app does not immediately undo it.

Turning automation off stops its scanning and retries while preserving existing
connections. No Bluetooth power toggle or sound-setting command is part of an
automatic reconnection. Sleep/session events and macOS screen-lock notifications
gate the policy. The latter notifications and lock-state dictionary field are
OS-specific. When the lock field is absent, a usable foreground application
and the observed session state are required; a login window or unknown session
does not start automatic retries.
Real lock/wake behavior still needs a user check on the target macOS installation.

## Nearby signal

Optionally require a minimum received signal strength, in dBm. Less-negative
values require a stronger signal. **Measure signal** asks connected aids for
RSSI and uses the weaker reading of your chosen pair as the threshold, provided
both readings arrive fresh within ten seconds. It never changes hearing gain.

Future connections require a fresh reading for each selected ear. Unknown,
invalid, future-dated or older-than-12-second readings do not pass the threshold.
Advertisements may be unavailable while another host is using the aids.

This is approximate signal tuning, not ranging in meters. Body orientation,
walls, interference and height affect RSSI; it cannot reliably distinguish a
particular room or floor. This implementation uses RSSI, not UWB or Bluetooth
Channel Sounding.

## Mac audio output

Audifern reads available outputs using public Core Audio APIs. Select a
preferred output, then explicitly use it now or opt in to selecting it after
the app's control connection succeeds. An absent output is shown as unavailable
and cannot be forced into existence by selecting its saved identifier.

Optional restoration on lock returns to the output that preceded Audifern's
change. If the user chose a different output afterward, Audifern leaves that
choice alone. A failed selection remains retryable by the user instead of
running an automatic loop. These controls do not alter microphone/input routing.

Selecting an output does **not** promise to release the underlying Bluetooth
audio profile. [Apple documents](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection(_:))
that cancelling an app connection need not disconnect a physical link held by
another client. The app's Connected state means its GATT controls are connected,
not that macOS has an audio output available.

## Android ↔ Mac handoff: current research boundary

[Oticon's LE Audio troubleshooting guide](https://assets-je.cas.dgs.com/-/media/oticon/main/pdf/australia/24point2/lions/61275294au_ug_ot_hands-free_troubleshooting_android-pc-le_audio.pdf)
describes different Apple and Android audio protocols and one active stream at
a time, even when multiple devices are connected. Its documented workaround
switches the active host's Bluetooth connection. The product guide identifies
Mac streaming as MFi and compatible Android streaming as LE Audio or ASHA.
[Apple's MFi guide](https://support.apple.com/en-us/108780) documents handoff
between supported Apple devices; that does not establish Android-to-Mac handoff.

A read-only check during this work found only the built-in microphone and
speakers in this Mac's Core Audio device list. After the Android phone was
connected over USB, its profile state showed both aids connected to an active
LE Audio group, with the older Hearing Aid/ASHA profile disconnected. This
confirms the phone's selected profile; it does not establish that it prevents
every possible simultaneous Mac connection. Synthetic tests verify the
scheduling and route-ownership policy, not physical audio switching.

The connected phone reports Android API 37. Android now documents per-device
[`BluetoothDevice.connect()`](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#connect())
and [`disconnect()`](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#disconnect())
from API 37, with Bluetooth permission and either privileged access or a
Companion Device Manager association. A user-approved Android helper is
therefore a possible path to coordinated release on this phone. It is not
implemented here, and these APIs must not be assumed available to ordinary
apps on older Android versions. Disconnect initiation is asynchronous and
needs profile/ACL state confirmation before attempting Mac audio.

The next hardware check should compare the phone's active profile, the Mac's
audio outputs and each app's control connection. Try cancelling only Audifern's
connection, then changing only the selected output, and observe which action
actually releases the audio host. If the OS still owns the link, a coordinated,
per-device system/phone helper needs investigation. No unverified private audio
command, global Bluetooth toggle or claim of seamless handoff is shipped here.
