# Crew PIN and SOS

Open the same mission on two enrolled iOS or iPadOS devices. Crew connects automatically to the configured session. Enrolled simulators can exercise sharing and rescue presentation in an isolated session.

## Destination PIN

**Send PIN** shares the selected destination's Mars coordinates with the current mission's Crew. A tap without a valid selection shows **Select a destination on the map first.** The sender sees **Destination shared with Crew** after Firebase accepts the write. Each marker identifies its sender by ARES ID. The local astronaut's PIN is cyan and the teammate's PIN is amber. The colors follow the astronaut viewing the map. When close to a flag or crew marker, a short line connects the PIN symbol to its geographic point.

Receiving a PIN leaves the current route in place. Tap the teammate's PIN to select the point, then use **Start Navigation** when ready. A new PIN replaces the sender's prior PIN. The marker expires 60 seconds after its server timestamp and the selected destination and route remain available. Reconnect restores unexpired PINs. An offline tap with a valid selection displays the connection requirement.

## Crew rescue

**SOS → SEND SOS** shares the estimated Mars location at the moment of confirmation. The crew receives an educational in-app assistance alert. The feature contacts no emergency services.

The sender's confirmation uses a dark emergency panel. The receiving astronaut sees a deep-red distress panel with the sender's name and ID, the current estimated distance and the active waypoint status. Both dialogs use the briefing's full-width action buttons. On short displays and with larger text, the body scrolls while both actions stay available. The dialogs use the system Reduce Motion setting.

Crew sees a red mission boundary with the original geographic radius and a red marker at the captured point. The sender sees **SOS ACTIVE** and can use **Cancel SOS**. Their own astronaut marker keeps following accepted physical steps. The other astronaut sees one incident modal per app run with the sender's name, ID, and estimated separation. **Dismiss** closes the alert and leaves the rescue active. **View Waypoint** closes the alert and exposes the rescue map. The existing guidance points straight toward the rescue waypoint and takes priority over the local destination. That destination returns when the rescue ends. Terrain along the guidance line is unverified.

The sender can cancel. To complete a rescue, the teammate must make accepted PDR movement after the alert becomes active and enter the five-meter circle from outside. A teammate already inside must first leave that circle by accepted movement. Resets, restored positions, and heading-only changes do not count toward arrival. The distance is calculated on the Mars sphere from the estimated coordinates. It expresses estimated separation. The terminal state closes the waypoint and restores the orange boundary on both devices.

Closing the app or switching missions leaves the alert in its original Firebase session. Reconnecting reads the active or terminal record from the server. A connection within each mission owns its own signal stream.

## Firebase schema and authorization

All paths are relative to `missions/{missionId}/sessions/{sessionId}`.

| Path | Stored fields |
| --- | --- |
| `signals/pins/{ARES-id}` | `marsLon`, `marsLat`, `updated` |
| `signals/sos` | `id`, `sender`, `marsLon`, `marsLat`, `started`, `state`. Terminal records include `finishedBy` and `finished`. |

The PIN key identifies the astronaut. Timestamps come from Firebase. The client writes the selected coordinate to the sender's PIN path. Presence continues updating independently. SOS uses a conditional update with the current ETag. The server rejects replacing an active incident or changing the captured position during cancellation or resolution. A new alert can replace the latest terminal record. [Firebase Realtime Database conditional writes](https://firebase.google.com/docs/database/rest/save-data)

The same authenticated mission membership authorizes signal reads. An astronaut can write their own PIN and create or cancel an SOS as their assigned slot. Resolution requires an authenticated teammate with a recent, online, accepted live pose after activation and within a conservative Mars coordinate envelope. The app separately checks the exact five-meter distance and accepted movement across the boundary. Signed-in devices report their own PDR estimates. Server validation checks those estimates against the alert and cannot attest to physical arrival. No Earth location or account credentials are written to signals.

## Field procedure

1. Open Endeavour on both enrolled devices. Tap **Send PIN** before selecting a destination and check the prompt. Select a waypoint, send **PIN**, and compare its location on both phones. Tap the received PIN on the teammate’s map to select it. Repeat in reverse.
2. Send SOS from one phone. Check the sender status, the other phone's modal and rescue waypoint, and both red boundaries. Cancel and confirm both return to normal.
3. Start outside the five-meter radius and walk toward the waypoint with the rescuer's physical phone. Observe the transition to resolved and the restored boundary. A simulator can verify synchronization, presentation, and cancellation. Its step count is unavailable for physical arrival.

See [device enrollment](live_astronaut_tracking.md) for the field phones. Dan and Keren already own the two field slots. An operator must explicitly provision a replacement device or use an isolated test session.

## Phase 6G.2 verification

The matching DEV builds ran on Dan's iPhone 16 and the iPhone 18 Pro simulator in the isolated Endeavour session. Dan's physical phone sent the SOS and Firebase recorded its position and cancellation. The simulator confirmed the redesigned outgoing dialog and its Cancel action, then displayed ARES-01, Dan Urquía and 13 m in the new incoming alert. The estimate matched 12.9 m between the incident and the simulated astronaut. **View Waypoint** closed the dialog and showed the active rescue route.

Widget tests check dismissal without resolving the SOS, one alert per incident, live distance changes, Reduce Motion and the layout at iPhone 16, iPhone 14 Plus and small-phone dimensions with enlarged text. Firebase emulator tests exercise the existing SOS payload and authorization. Keren's physical iPhone 14 Plus was unavailable.

## Phase 6G.1 verification

Flutter tests exercise the destination requirement, acknowledged delivery, the compact anchored marker, a teammate's explicit tap, pan, zoom, both heading modes and expiry while guidance remains active. The Firebase emulator verifies that destination coordinates differ from the stored sender pose and reach the teammate stream, with writes scoped to the sender's slot and mission. The existing SOS capture and resolution tests still pass.

The DEV build was installed and launched in place on Dan's iPhone 16 and the iPhone 18 Pro simulator. The simulator showed the destination prompt in Endeavour as ARES-02. Both devices then connected to the previously enrolled isolated session. Firebase recorded a destination distinct from ARES-01's position. The simulator displayed both astronauts' PINs, kept its current destination on receipt and selected ARES-01's point when tapped. Keren's iPhone 14 Plus was unavailable for installation and paired physical-phone testing.

## Phase 6F verification

The iPhone 16 running as ARES-01 and the iPhone 18 Pro simulator running as ARES-02 joined a separate Endeavour session. Firebase accepted a PIN from each device in this historical trial. Phase 6F sent the estimated pose. The current action shares the selected destination, as verified in Phase 6G.1. The simulator displayed his PIN, its red rescue marker, the red boundary, and 13 m of remaining guidance during his SOS. When Dan canceled, the simulator cleared the rescue, and Firebase recorded the terminal state.

The app and Realtime Database emulator tests exercise expiry, delivery acknowledgments, cancellation, two-device authorization, connection loss, position-based resolution and isolation across the five missions. The simulator has its own enrolled identity for the isolated test and cannot assume a field slot.

The simulator then sent its own SOS from Habitat Base. It remained active while the iPhone temporarily left the foreground and when it reconnected. The simulator canceled its alert. The iPhone did not publish a qualifying walking arrival in that trial. The walking completion and the installation on Keren's unavailable iPhone remain field checks.
