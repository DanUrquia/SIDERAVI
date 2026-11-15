# Crew connection and live astronaut tracking

On iPhone and iPad, open a mission to begin tracking locally. Devices that have been enrolled in the same Firebase mission session connect to Crew automatically. The current step-navigation and screen behavior is documented in the [physical navigation guide](real_navigation_validation.md) and [phone and iPad layouts](mobile_navigation.md).

## Firebase sessions for the five missions

The Realtime Database organizes Crew under `missions/{missionId}/sessions/{sessionId}`. The field configuration provides independent sessions at Endeavour Crater, Gale Crater, Columbia Hills, Valles Marineris and Jezero Crater. Each mission uses its own Habitat Base and server state. Simulators can join an isolated test session with their own enrollments.

At first mission entry, Firebase Anonymous Authentication issues an identity for the selected astronaut on that device. iOS stores the renewable credential in the Keychain. The local astronaut PIN selects the roster entry. A Firebase operator separately assigns the identity to one slot in each authorized session. Rules grant session access only after the assignment and enforce each slot's permitted writes. Older iPad builds used password-authenticated memberships. That flow is retained below as historical testing evidence. [Anonymous Authentication](https://firebase.google.com/docs/auth/flutter/anonymous-auth) · [Security Rules](../firebase/database.rules.json)

### Local development and authorized pairing

Run the app with the standard Flutter commands in the [README](../README.md#run-and-test-locally) to explore missions, telemetry and navigation locally. An unconfigured installation reports **OFFLINE** in Crew. Devices with a valid configuration but no matching assignment show **Crew device setup pending**.

For shared Crew testing, use an authorized Firebase project and local build values for `SIDERA_DATABASE_URL`, `SIDERA_FIREBASE_API_KEY` and `SIDERA_SESSION_ID`. Pass that file with `--dart-define-from-file`. Keep it outside version control. The operator creates an active mission session, verifies and enrolls each device identity under its assigned ARES slot, then checks that both devices report **Connected** in the same mission. Leave each app in the foreground while comparing Crew. [Field checks](real_navigation_validation.md#starting-or-resuming-a-shared-jezero-expedition) · [Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite/install_and_configure)

### Security, lifecycle and transport

The operator controls session metadata and membership. An enrolled client streams authorized Crew presence and signals over HTTPS server-sent events. REST writes publish the client's estimated Mars pose, relative heading when available, mode, position quality, online state and server timestamp. The app stores step totals, raw sensor traces and Earth coordinates locally. PIN and SOS have their own validation rules. [Destination PIN and SOS schema](crew_signals.md#firebase-schema-and-authorization)

Writes run in sequence. A six-second heartbeat maintains presence while stationary. The client attempts an offline write when leaving the dashboard or backgrounding, with expiry after 18 seconds as the fallback. It reconnects after transient failures and publishes the current mission pose. Saved positions are scoped to the astronaut and mission. An explicit new expedition resets the local slot at Habitat Base. [Realtime Database REST streaming](https://firebase.google.com/docs/database/rest/retrieve-data#section-rest-streaming)

## Historical record — Phase 5B and 5C

This section describes earlier tablet builds. The Demo Movement, Live Sensors and legacy sign-in steps document those experiments.

Start a mission to place the signed-in astronaut at its simulated Habitat Base. The dashboard begins in **Demo Movement**. Waypoints and Return to Base control the simulated route. **Live Sensors** asks for foreground Earth location and gives validated sensor displacement control of the position. In live mode, Return to Base selects the habitat as a destination and leaves movement to the astronaut. **Pause Exploration** and demo SOS pause both movement sources. Ping and demo SOS stay local to this iPad. The dashboard continues to use NASA Mars Trek imagery, its north-up map and the existing points of interest.

**Follow Astronaut** recenters on the local marker while retaining zoom. A manual pan releases follow. **Reset View** restores original framing and turns follow off. Forward, motion source, simulated coordinates, and connection state are shown independently.

### Sensor and coordinate model

The existing Swift method channel registers with the Flutter engine used by the UIKit scene. In either tracking mode, it collects approximately 10 Hz Core Motion attitude in the foreground. The iPad screen’s current top edge is forward. The bridge projects that edge onto the horizontal plane and accounts for both landscape directions. **Calibrate** makes the next usable orientation face up on the map. Point the screen top toward your chosen reference and keep it reasonably horizontal when calibrating. A landscape flip establishes a new reference, and a same-orientation sensor restart preserves the last displayed angle while reestablishing the native reference. Recalibrate if the device was turned while paused in the background. The glyph uses shortest-arc interpolation. After two seconds without a usable heading the numeric heading is unavailable. Relative yaw expresses how the iPad is held, independent of direction of travel or a verified Mars compass.

Only **Live Sensors** starts dashboard Core Location updates. The app requests When In Use authorization and requires Precise Location for live positioning. Routes, permission denial, and unavailable sensors have defined local fallback states. Leaving the dashboard or backgrounding the app stops its streams. Sensor Test temporarily takes over the bridge and returning resumes the dashboard without changing its Mars position.

Phase 5D adds an operator rebaseline, a hold for large location-derived steps, and a local diagnostic capture. Until a walk is independently measured, the location estimates remain experimental. [Phase 5D investigation, movement guard, and field procedure](live_movement_validation.md).

For accepted Earth steps, the filtered displacement outside reported uncertainty is resolved into east and north meters and transferred at **1 physical meter = 1 simulated Mars meter** via the Mars 2000 sphere (radius 3,396,190 m). The existing equidistant cylindrical projection maps the result to the overlay. East and north displacement map to Mars east and north for this experiment. Calibration changes the arrow only. The preexisting demo route retains its own scenario distances. Live route readouts use the Mars sphere.

Phase 5E adds local CMPedometer diagnostics and fixed-size map markers. [Pedometer validation and marker behavior](pedometer_validation.md).

Both iPads use the same existing normalized habitat marker as the base. Its Phase 4 map location is derived from the catalog reference and initial angular span. The following are simulated operational positions.

| Mission ID | Base latitude | Base east-positive signed longitude |
| --- | ---: | ---: |
| `jezero` | 18.3860 | 77.6564 |
| `gale` | -5.4150 | 137.7250 |
| `endeavour` | -2.2950 | -5.1700 |
| `columbia-hills` | -14.5478 | 175.6165 |
| `valles-marineris` | -13.8300 | -59.1550 |

### Historical physical procedure and results

1. Sign in on both iPads, enter the same mission and check the Habitat Base marker and NASA imagery. Test map pan, pinch zoom, follow and reset. In Demo Movement, select a waypoint, start the route and use Return to Base.
2. Place each iPad face-up, calibrate, rotate its top edge 90° clockwise and then 180° from the initial direction, and return to the initial heading. Record display direction and return error. Repeat in the other landscape orientation and with normal carrying tilt.
3. Select Live Sensors and keep each iPad still for approximately one minute. Record accepted position changes, quality and false positives. Repeat on measured, safe 10 m, 30 m and 50–100 m walks. Compare reported uncertainty, confirmed displacement and time to first accepted movement. Keep coordinate traces private.
4. With a provisioned backend, join the same mission session. Verify distinct roster IDs, smooth remote heading and movement, and offline expiry. Toggle Wi-Fi and return to the same session, then verify that each roster slot appears once and positions do not reset. Test separate mission and session IDs for isolation.

The Phase 5B field check used the iPad Pro 12.9-inch (third generation) on iPadOS 26.7.3 and the iPad Air (fourth generation) on iPadOS 27.0.1. Both opened Jezero, rendered Mars Trek imagery, and displayed their own ARES marker at the same simulated base coordinate. Both markers rotated locally as their devices were handled. The Pro displayed a retry indicator for some tiles at high zoom while imagery remained visible. The Flutter tests exercise mode switching, uncertainty holds, demo navigation and map gestures, including follow and reset. The native tests check landscape transforms in the simulator. The Firebase Emulator Suite verified rules and streamed updates with two authenticated test accounts; this does not establish connectivity from the physical iPads.

### Phase 5C field check

Both physical iPads authenticated as their assigned roster slots and showed **Connected** in the Jezero `field-test-01` session on `sidera-vi`. Each map displayed both ARES markers. Turning the Pro updated ARES-01's arrow on the Air, and turning the Air updated ARES-02's arrow on the Pro. When the Pro navigated to Channel Edge in Demo Movement, the Air showed its remote marker at that waypoint.

Both dashboards displayed **Position Uncertain** in Live Sensors. The Air's simulated position held throughout the sampled run. The Pro's simulated position shifted about 202 m between two live snapshots, then held in the follow-up snapshots. The test did not establish physical displacement for the Pro's shift. The reading is inconclusive for stationary-noise rejection and cannot validate walking accuracy.

When Wi-Fi was disabled on the Air, the Pro stayed connected and showed ARES-02's last position with an **Offline** label. The offline state was observed once the last Air update was about 20 seconds old. After Wi-Fi was restored, both dashboards showed Connected, both simulated positions matched the pre-reconnect values, and each map showed one marker per astronaut.

Phase 5A established that the Wi-Fi-only iPads can supply motion at approximately 10 Hz under the tested conditions. Its Earth results did not establish reliable walking translation. The Phase 5D filter can hold the position throughout short walks on these devices. Demonstrate navigation with Demo Movement until measured trials establish repeatable reliable displacement. Network sharing requires the project setup above.

## Phase 6E backend verification

The production project has all five active `field-test-01` sessions with their catalog Habitat Bases and both verified legacy memberships. Jezero keeps its existing session and presence records. The deployed rules deny public reads and writes. The emulator verifies access with an enrolled anonymous UID and its refreshed credential, denies writes to the other astronaut's slot, rejects extra pose fields, and exercises independent presence streams across all five missions.

Dan’s iPhone 16 and Keren’s iPhone 14 Plus were enrolled in ARES-01 and ARES-02. Both automatically published fresh presence in Endeavour at 0 m separation. The other four sessions had no fresh presence during that observation.

Phase 6F adds one authorized PIN per slot and a shared rescue alert per mission. [Crew PIN and SOS](crew_signals.md)
