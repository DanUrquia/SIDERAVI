# Crew PIN and SOS

Open the same mission on two enrolled iPhones. The field build uses the mission's existing `field-test-01` session and automatically connects Crew. The **Send PIN** and **SOS** controls share that session.

## Position PIN

**Send PIN** captures the current PDR-estimated Mars position and publishes it with the current crew pose in a single database update. The sender sees **PIN shared with Crew** after Firebase acknowledges the write. Each map shows the newest PIN for each astronaut, with the sender's ARES ID. A PIN stays at that captured location and expires 60 seconds after its server timestamp. An offline tap displays the connection requirement. A failed send is reported as unconfirmed. Reconnect loads existing unexpired PINs and leaves unsent taps behind.

## Crew rescue

**SOS → SEND SOS** shares the estimated Mars location at the moment of confirmation. The crew receives an educational in-app assistance alert. The feature contacts no emergency services.

Crew sees a red mission boundary with the original geographic radius and a red marker at the captured point. The sender sees **SOS ACTIVE** and can use **Cancel SOS**. Their own astronaut marker keeps following accepted physical steps. The other astronaut sees one incident modal per app run with the sender's name, ID, and estimated separation. Dismissing the modal leaves the rescue active. The existing guidance points straight toward the rescue waypoint and takes priority over the local destination. That destination returns when the rescue ends. Terrain along the guidance line is unverified.

The sender can cancel. To complete a rescue, the teammate must make accepted PDR movement after the alert becomes active and enter the five-meter circle from outside. A teammate already inside must first leave that circle by accepted movement. Resets, restored positions, and heading-only changes do not count toward arrival. The distance is calculated on the Mars sphere from the estimated coordinates. It expresses estimated separation. The terminal state closes the waypoint and restores the orange boundary on both devices.

Closing the app or switching missions leaves the alert in its original Firebase session. Reconnecting reads the active or terminal record from the server. A connection within each mission owns its own signal stream.

## Firebase schema and authorization

All paths are relative to `missions/{missionId}/sessions/{sessionId}`.

| Path | Stored fields |
| --- | --- |
| `signals/pins/{ARES-id}` | `marsLon`, `marsLat`, `updated` |
| `signals/sos` | `id`, `sender`, `marsLon`, `marsLat`, `started`, `state`. Terminal records include `finishedBy` and `finished`. |

The PIN key identifies the astronaut. Timestamps come from Firebase. PINs use an atomic multipath update of the PIN and the sender's existing pose. SOS uses a conditional update with the current ETag. The server rejects replacing an active incident or changing the captured position during cancellation or resolution. A new alert can replace the latest terminal record. [Firebase Realtime Database conditional writes](https://firebase.google.com/docs/database/rest/save-data)

The same authenticated mission membership authorizes signal reads. An astronaut can write their own PIN and create or cancel an SOS as their assigned slot. Resolution requires an authenticated teammate with a recent, online, accepted live pose after activation and within a conservative Mars coordinate envelope. The app separately checks the exact five-meter distance and accepted movement across the boundary. Signed-in devices report their own PDR estimates. Server validation checks those estimates against the alert and cannot attest to physical arrival. No Earth location or account credentials are written to signals.

## Field procedure

1. Open Endeavour on both enrolled devices. Walk with one physical phone while the other stays still, send **PIN**, and compare its marker against the published Mars coordinates. Repeat in reverse.
2. Send SOS from one phone. Check the sender status, the other phone's modal and rescue waypoint, and both red boundaries. Cancel and confirm both return to normal.
3. Start outside the five-meter radius and walk toward the waypoint with the rescuer's physical phone. Observe the transition to resolved and the restored boundary. A simulator can verify synchronization, presentation, and cancellation. Its step count is unavailable for physical arrival.

See [device enrollment](live_astronaut_tracking.md) for the field phones. Dan and Keren already own the two field slots. An operator must explicitly provision a replacement device or use an isolated test session.

## Phase 6F verification

The iPhone 16 running as ARES-01 and the iPhone 18 Pro simulator running as ARES-02 joined a separate Endeavour session. Firebase accepted a PIN from each device. Dan's PIN matched his estimated Mars pose. The simulator displayed his PIN, its red rescue marker, the red boundary, and 13 m of remaining guidance during his SOS. When Dan canceled, the simulator cleared the rescue, and Firebase recorded the terminal state.

The app and Realtime Database emulator tests exercise expiry, delivery acknowledgments, cancellation, two-device authorization, connection loss, position-based resolution and isolation across the five missions. The simulator has its own enrolled identity for the isolated test and cannot assume a field slot.

The simulator then sent its own SOS from Habitat Base. It remained active while the iPhone temporarily left the foreground and when it reconnected. The simulator canceled its alert. The iPhone did not publish a qualifying walking arrival in that trial. The walking completion and the installation on Keren's unavailable iPhone remain field checks.
