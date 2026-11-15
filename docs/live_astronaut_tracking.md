# Phase 5B live astronaut tracking

Start a mission to place the signed-in astronaut at its simulated Habitat Base. The dashboard begins in **Demo Movement**. Waypoints and Return to Base control the simulated route. **Live Sensors** asks for foreground Earth location and gives validated sensor displacement control of the position. In live mode, Return to Base selects the habitat as a destination and leaves movement to the astronaut. **Pause Exploration** and demo SOS pause both movement sources. Ping and demo SOS stay local to this iPad. The dashboard continues to use NASA Mars Trek imagery, its north-up map and the existing points of interest.

**Follow Astronaut** recenters on the local marker while retaining zoom. A manual pan releases follow. **Reset View** restores original framing and turns follow off. Forward, motion source, simulated coordinates, and connection state are shown independently.

## Sensor and coordinate model

The existing Swift method channel registers with the Flutter engine used by the UIKit scene. In either tracking mode, it collects approximately 10 Hz Core Motion attitude in the foreground. The iPad screen’s current top edge is forward. The bridge projects that edge onto the horizontal plane and accounts for both landscape directions. **Calibrate** makes the next usable orientation face up on the map. Point the screen top toward your chosen reference and keep it reasonably horizontal when calibrating. A landscape flip establishes a new reference, and a same-orientation sensor restart preserves the last displayed angle while reestablishing the native reference. Recalibrate if the device was turned while paused in the background. The glyph uses shortest-arc interpolation. After two seconds without a usable heading the numeric heading is unavailable. Relative yaw expresses how the iPad is held, independent of direction of travel or a verified Mars compass.

Only **Live Sensors** starts dashboard Core Location updates. The app requests When In Use authorization and requires Precise Location for live positioning. Routes, permission denial, and unavailable sensors have defined local fallback states. Leaving the dashboard or backgrounding the app stops its streams. Sensor Test temporarily takes over the bridge and returning resumes the dashboard without changing its Mars position.

The first valid Earth fix sets a baseline. Live mode excludes fixes sampled before the current measurement window, invalid and out-of-order observations, fixes with reported accuracy worse than 50 m, and readings over 15 seconds old. A gap of over 30 seconds between valid fixes establishes a new baseline. A candidate displacement must exceed the sum of the last accepted and current accuracy radii. The filter rejects candidates whose lower-bound speed exceeds 3.5 m/s and requires a second fix at least 0.5 seconds later, within 15 seconds, in the same direction and within the candidates’ combined uncertainty. When position is uncertain, the marker holds while the motion arrow continues to respond. These are prototype filters. Wi-Fi positioning can produce correlated errors, and overlapping accuracy circles can hide real walking.

Accepted Earth steps are resolved into east and north meters from the spherical geodesic distance and bearing. They are transferred at **1 physical meter = 1 simulated Mars meter** via the Mars 2000 sphere (radius 3,396,190 m) and projected into the Phase 4 equidistant cylindrical map. East and north displacement map to Mars east and north for this experiment. Calibration changes the arrow only. It has no effect on the displacement axes. The preexisting demo route retains its own scenario distances. Live route readouts use the Mars sphere.

Both iPads use the same existing normalized habitat marker as the base. Its Phase 4 map location is derived from the catalog reference and initial angular span. The following are simulated operational positions.

| Mission ID | Base latitude | Base east-positive signed longitude |
| --- | ---: | ---: |
| `jezero` | 18.3860 | 77.6564 |
| `gale` | -5.4150 | 137.7250 |
| `endeavour` | -2.2950 | -5.1700 |
| `columbia-hills` | -14.5478 | 175.6165 |
| `valles-marineris` | -13.8300 | -59.1550 |

## Shared Jezero session on Firebase

The independent field-test project is `sidera-vi`. Its Realtime Database is `https://sidera-vi-default-rtdb.firebaseio.com`, and both iPads join the active `missions/jezero/sessions/field-test-01` session. The project already contains both crew accounts, their ARES slot assignments, and the simulated base metadata. Keep those records when deploying rules or installing a new build.

The app uses [authenticated Firebase REST requests](https://firebase.google.com/docs/database/rest/auth) and [server-sent events](https://firebase.google.com/docs/database/rest/retrieve-data). An unconfigured build starts **Offline** and supports both local movement modes.

### Check and deploy rules

Run the emulator check from the repository root. The `demo-sideravi` ID is local to the emulator.

```sh
npx --yes firebase-tools emulators:exec --only auth,database \
  --project demo-sideravi 'node firebase/test-rules.mjs'
```

Use the authorized Firebase CLI session and explicit SIDERA VI project argument for the rules-only deployment.

```sh
npx --yes firebase-tools deploy --only database --project sidera-vi
```

The deployment updates access rules. The existing session, metadata, and crew UID assignments are provisioned separately. The Auth accounts are assigned to ARES-01 and ARES-02 by Firebase UID. A crew member may verify their own slot during sign-in. The rules deny listing the membership map and writing someone else's simulated pose.

### Build and join

Retrieve the client Web API key from the registered SIDERA VI Web app through the Firebase console or authenticated CLI. [Firebase CLI reference](https://firebase.google.com/docs/cli/)

```sh
npx --yes firebase-tools apps:list --project sidera-vi
npx --yes firebase-tools apps:sdkconfig web WEB_APP_ID --project sidera-vi
```

Pass the Firebase URL, client key, and session to Flutter at build time. The command below assumes the client key was loaded into a local shell variable.

```sh
flutter build ios --release \
  --dart-define=SIDERA_DATABASE_URL=https://sidera-vi-default-rtdb.firebaseio.com \
  --dart-define=SIDERA_FIREBASE_API_KEY="$SIDERA_FIREBASE_API_KEY" \
  --dart-define=SIDERA_SESSION_ID=field-test-01
```

The client key must permit the Identity Toolkit and Secure Token APIs. An untracked local file passed with `--dart-define-from-file` is another option. Keep build definitions and account credentials separate. The app has no Firebase plist or administrative credentials.

1. Install the configured build on both iPads. Sign in with each astronaut’s existing SIDERA VI PIN and enter Jezero.
2. On each device, tap **Join Crew** and enter the assigned Firebase email and password privately. The app verifies the authenticated account’s Firebase UID against the signed-in astronaut’s session slot before subscribing to crew presence.
3. Confirm **Connected** and look for both ARES markers. If an account is declined, check the assigned Firebase account, session state and membership on the administrator side. A new shared run can use a separately provisioned session ID.

## Security, lifecycle and transport

Only the administrator creates session metadata and membership. The rules authorize each roster slot by Firebase Auth UID and scope reads to participants in that session. Presence data contains only signed Mars coordinates, relative heading if usable, mode, position quality, online status and server timestamp. Names and labels come from the local roster. Rules validate the payload and reject extra fields. Earth coordinates and sample traces stay on the device. Credentials are entered at runtime, with tokens only in memory for the open dashboard.

A single stream updates the crew view. Writes are asynchronous and serialized. Heading changes of at least 2° and simulated demo animation snapshots publish at most about 4 Hz. Validated live position changes can publish sooner. A six-second heartbeat maintains presence while stationary. A remote marker turns muted and shows **Offline** after 18 seconds without a fresh heartbeat, or immediately when an offline update is received. The client attempts an offline write when leaving the dashboard or backgrounding, with expiry as the fallback. Reconnection uses backoff and sends the current pose without replaying a trace. Within the same open dashboard it retains position through sensor restarts and network changes. On app restart the offline dashboard starts at base. Joining the same shared session restores its prior position if the local astronaut is still at base.

Use the local Auth and Database emulators to verify the security rules and streamed writes with separate test accounts.

```sh
npx --yes firebase-tools emulators:exec --only auth,database \
  --project demo-sideravi 'node firebase/test-rules.mjs'
```

## Physical validation

1. Sign in on both iPads, enter the same mission and check the Habitat Base marker and NASA imagery. Test map pan, pinch zoom, follow and reset. In Demo Movement, select a waypoint, start the route and use Return to Base.
2. Place each iPad face-up, calibrate, rotate its top edge 90° clockwise and then 180° from the initial direction, and return to the initial heading. Record display direction and return error. Repeat in the other landscape orientation and with normal carrying tilt.
3. Select Live Sensors and keep each iPad still for approximately one minute. Record accepted position changes, quality and false positives. Repeat on measured, safe 10 m, 30 m and 50–100 m walks. Compare reported uncertainty, confirmed displacement and time to first accepted movement. Keep coordinate traces private.
4. With a provisioned backend, join the same mission session. Verify distinct roster IDs, smooth remote heading and movement, and offline expiry. Toggle Wi-Fi and return to the same session, then verify that each roster slot appears once and positions do not reset. Test separate mission and session IDs for isolation.

The Phase 5B field check used the iPad Pro 12.9-inch (third generation) on iPadOS 26.7.3 and the iPad Air (fourth generation) on iPadOS 27.0.1. Both opened Jezero, rendered Mars Trek imagery, and displayed their own ARES marker at the same simulated base coordinate. Both markers rotated locally as their devices were handled. The Pro displayed a retry indicator for some tiles at high zoom while imagery remained visible. The Flutter tests exercise mode switching, uncertainty holds, demo navigation and map gestures, including follow and reset. The native tests check landscape transforms in the simulator. The Firebase Emulator Suite verified rules and streamed updates with two authenticated test accounts; this does not establish connectivity from the physical iPads.

Phase 5A established that the Wi-Fi-only iPads can supply motion at approximately 10 Hz under the tested conditions. Its Earth results did not establish reliable walking translation. Phase 5B’s stricter filter can leave the marker at base for short walks. Demonstrate navigation with Demo Movement until measured trials establish repeatable reliable displacement. Network sharing requires the project setup above.
