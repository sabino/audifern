# Battery alerts on this Mac

Battery notifications are local macOS notifications. The user enables them in Settings; the application never requests permission from launch or Bluetooth discovery. Users can select 50%, 30%, 20%, and **below 10%** separately, turn either side off, and optionally enable a notification sound. A test alert is sent only by its explicit button. Notification text contains the side and current percentage, without device names, serial numbers, account identifiers or audiogram data.

The application calls `retainConnectedDevices(_:)` before feeding confirmed readings into `BatteryNotificationManager.observe(deviceID:side:percentage:)`. Disconnecting removes cached live readings and cancels unfinished delivery tasks without deleting persisted history. Enabling alerts or retrying while offline therefore cannot use an old cached percentage. Unknown sides and missing/invalid values must not be substituted. There are no additional scans, periodic polls, battery estimation timers or Bluetooth connection attempts in this subsystem. It needs Audifern to remain running and receive readings; this is not a background service that survives quitting the application.

Each CoreBluetooth UUID has independent, persisted state:

- A downward crossing triggers its selected threshold once. The low-battery condition is strictly less than 10%, so 10% itself does not trigger that alert.
- A large drop produces one notification at the most urgent selected threshold, displaying the actual current percentage and covering earlier crossed milestones.
- An initial observation above 30% establishes a baseline without inventing a missed 50% crossing. An initial reading at 30% or below can produce one already-low alert at the most urgent enabled threshold.
- Disconnecting, reconnecting or restarting at the same battery level does not reset history.
- A threshold re-arms only when a later measured level reaches five percentage points above it: 55%, 35%, 25%, or 15%. Small fluctuations around a threshold stay quiet.
- A delivery failure leaves the alert pending. The next later reading can retry after a short failure cooldown, or the user can select **Retry pending alerts**. There is no retry timer. Permission changes can be checked explicitly without requesting authorization again.
- A queued notification is acknowledged in the state machine only after macOS accepts it. A stable request identifier, in-process accepted-request tracking and macOS pending/delivered lookup prevent repeating an accepted request when saving history needs a retry. Notification acceptance cannot guarantee a visible banner: macOS Focus and user notification settings still apply.

Settings and UUID history live in `~/Library/Application Support/Audifern/battery-alerts.json`. The containing directory is private (0700), and replacement files are created with 0600 permissions before writing. Malformed settings are preserved; saving and notifications remain blocked until that loading problem is resolved. The subsystem does not log device identifiers or battery readings.

The pure state-machine tests cover all thresholds, strict low-battery boundaries, already-low startup, drop coalescing, hysteresis, serialization, independent UUIDs, malformed readings and stale delivery acknowledgments. Notification-manager tests inject a fake delivery service and temporary/in-memory persistence: they never request actual macOS permissions, present a notification, or contact hearing aids. Tests cover permission denial, retries, private storage, repeated-reading efficiency and accepted-delivery/save-failure handling.

Implementation references: Apple's [notification authorization API](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)) and [foreground presentation delegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)). The implementation requests alerts and optional sounds, without APNs registration or a remote notification endpoint.
