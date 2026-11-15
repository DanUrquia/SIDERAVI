# Phase 5B live astronaut tracking

Start a mission to place the signed-in astronaut at its simulated Habitat Base. The dashboard begins in **Demo Movement**. Waypoints and Return to Base control the simulated route. **Live Sensors** asks for foreground Earth location and gives validated sensor displacement control of the position. In live mode, Return to Base selects the habitat as a destination and leaves movement to the astronaut. **Pause Exploration** and demo SOS pause both movement sources. Ping and demo SOS stay local to this iPad. The dashboard continues to use NASA Mars Trek imagery, its north-up map and the existing points of interest.

**Follow Astronaut** recenters on the local marker while retaining zoom. A manual pan releases follow. **Reset View** restores original framing and turns follow off. Forward, motion source, simulated coordinates, and connection state are shown independently.

## Sensor and coordinate model

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

## Firebase sessions for the five missions

The independent field-test project is `sidera-vi`. Its Realtime Database is `https://sidera-vi-default-rtdb.firebaseio.com`. Each mission opens its own `missions/{missionId}/sessions/field-test-01` session using the catalog ID and the shared Habitat Base above. The mission carousel order is Endeavour Crater, Gale Crater, Columbia Hills, Valles Marineris and Jezero Crater.

On a provisioned iPhone, entering a mission automatically starts Firebase authentication and connects Crew. Firebase Anonymous Authentication issues a distinct UID to the selected astronaut on that phone. The app stores the renewable credential in the iOS Keychain and reads it on subsequent visits. The app's PIN selects the astronaut identity for the local experience. [Firebase Anonymous Authentication](https://firebase.google.com/docs/auth/flutter/anonymous-auth), [Firebase Auth REST API](https://firebase.google.com/docs/reference/rest/auth/).

The membership rules require an administrator to assign that UID to a single slot. A new anonymous identity begins without any database access. Each session retains `members/{slot}` for the existing iPad accounts and uses a separate, administrator-written `deviceMembers/{slot}` for one anonymous iPhone UID per slot. An enrolled client can resolve its own membership record, read the active session's crew presence, and write only its own presence record. The rules deny writes by unauthenticated clients, access to the membership collections, and cross-slot writes. [Firebase Database Security Rules](https://firebase.google.com/docs/reference/security/database/).

An unconfigured or unenrolled phone stays **Offline** and supports local step navigation. Firebase App Check is outside the field build. Authorization depends on the individually enrolled Firebase UID and server rules. App Check could add an app and device attestation layer through App Attest once the phone and compatibility clients support it. [Firebase App Check on Apple platforms](https://firebase.google.com/docs/app-check/ios/app-attest-provider).

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

Session data and device enrollment are separate from rule deployment. The emulator checks anonymous eligibility, authenticated per-slot writes, session termination, legacy iPad accounts and live event isolation across all five missions.

### Build and provision iPhones

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

Protect the Realtime Database with the deployed rules before enabling **Authentication → Sign-in method → Anonymous** in the Firebase console. Keep automatic cleanup of anonymous users disabled when it is offered so field devices retain their UIDs across visits. [Firebase Anonymous Authentication setup](https://firebase.google.com/docs/auth/flutter/anonymous-auth).

1. Install the same signed build on the authorized phones. On each phone choose its assigned SIDERA VI identity and enter a mission once so it obtains its anonymous identity.
2. With the intended physical iPhone attached and authorized, use CoreDevice on the operator Mac to read the app's preferences file at `Library/Preferences/com.bluelionsoft.sideraVi.plist` under the app data container. Extract only the non-secret UID from `crewEnrollment/sidera-vi-default-rtdb.firebaseio.com/ARES-01` or `crewEnrollment/sidera-vi-default-rtdb.firebaseio.com/ARES-02`. Remove the temporary preferences copy after extraction. Firebase tokens stay in the phone's Keychain.
3. From the repository root, use an administrator's short-lived Google OAuth access token on standard input for the enrollment command. The example obtains it from authorized Google Application Default Credentials. The script validates the field project, each active session and the anonymous identity before assigning the verified UID to that specific slot in all five missions.

```sh
gcloud auth application-default print-access-token |
  node firebase/admin-crew.mjs enroll ARES-01 "$DEVICE_UID"
gcloud auth application-default print-access-token |
  node firebase/admin-crew.mjs verify
```

Repeat for the other authorized phone using its own UID and slot. Use `--replace` only for an intentional replacement of the enrolled phone. The operator tool can also run `create-sessions` to copy the verified Jezero legacy memberships into missing missions with their corresponding Habitat Bases. It leaves existing sessions untouched.

Reopen any mission to see **Connected**. Crew shows an offline teammate's name, ARES ID and **OFFLINE**. A fresh online update restores their shared position and distance. Previously installed iPad builds can still connect through the legacy Firebase accounts and **Join Crew**. The current iOS build uses device enrollment for automatic Crew.

## Security, lifecycle and transport

Only the administrator creates session metadata and membership. Presence contains signed Mars coordinates, relative heading when available, mode, position quality, online status and server timestamp. Names and labels come from the local roster. Earth coordinates, sensor traces, and measured step totals stay on the device. Both platforms use Firebase REST and one subscription scoped to the current mission. [Firebase Realtime Database REST Authentication](https://firebase.google.com/docs/database/rest/auth), [Firebase Realtime Database REST Streaming](https://firebase.google.com/docs/database/rest/retrieve-data).

Writes run in sequence. A six-second heartbeat maintains presence while stationary. The client attempts an offline write when leaving the dashboard or backgrounding, with expiration after 18 seconds as the fallback. The iPhone reconnects automatically and publishes its current local pose. A saved iPhone position is scoped by mission and astronaut. An explicit new expedition writes Habitat Base for the local astronaut and preserves the other astronaut's position. The existing iPad demo restore stays in the compatibility dashboard.

## Physical validation

1. Sign in on both iPads, enter the same mission and check the Habitat Base marker and NASA imagery. Test map pan, pinch zoom, follow and reset. In Demo Movement, select a waypoint, start the route and use Return to Base.
2. Place each iPad face-up, calibrate, rotate its top edge 90° clockwise and then 180° from the initial direction, and return to the initial heading. Record display direction and return error. Repeat in the other landscape orientation and with normal carrying tilt.
3. Select Live Sensors and keep each iPad still for approximately one minute. Record accepted position changes, quality and false positives. Repeat on measured, safe 10 m, 30 m and 50–100 m walks. Compare reported uncertainty, confirmed displacement and time to first accepted movement. Keep coordinate traces private.
4. With a provisioned backend, join the same mission session. Verify distinct roster IDs, smooth remote heading and movement, and offline expiry. Toggle Wi-Fi and return to the same session, then verify that each roster slot appears once and positions do not reset. Test separate mission and session IDs for isolation.

The Phase 5B field check used the iPad Pro 12.9-inch (third generation) on iPadOS 26.7.3 and the iPad Air (fourth generation) on iPadOS 27.0.1. Both opened Jezero, rendered Mars Trek imagery, and displayed their own ARES marker at the same simulated base coordinate. Both markers rotated locally as their devices were handled. The Pro displayed a retry indicator for some tiles at high zoom while imagery remained visible. The Flutter tests exercise mode switching, uncertainty holds, demo navigation and map gestures, including follow and reset. The native tests check landscape transforms in the simulator. The Firebase Emulator Suite verified rules and streamed updates with two authenticated test accounts; this does not establish connectivity from the physical iPads.

### Phase 5C production field check

Both physical iPads authenticated as their assigned roster slots and showed **Connected** in the Jezero `field-test-01` session on `sidera-vi`. Each map displayed both ARES markers. Turning the Pro updated ARES-01's arrow on the Air, and turning the Air updated ARES-02's arrow on the Pro. When the Pro navigated to Channel Edge in Demo Movement, the Air showed its remote marker at that waypoint.

Both dashboards displayed **Position Uncertain** in Live Sensors. The Air's simulated position held throughout the sampled run. The Pro's simulated position shifted about 202 m between two live snapshots, then held in the follow-up snapshots. The test did not establish physical displacement for the Pro's shift. The reading is inconclusive for stationary-noise rejection and cannot validate walking accuracy.

When Wi-Fi was disabled on the Air, the Pro stayed connected and showed ARES-02's last position with an **Offline** label. The offline state was observed once the last Air update was about 20 seconds old. After Wi-Fi was restored, both dashboards showed Connected, both simulated positions matched the pre-reconnect values, and each map showed one marker per astronaut.

Phase 5A established that the Wi-Fi-only iPads can supply motion at approximately 10 Hz under the tested conditions. Its Earth results did not establish reliable walking translation. The Phase 5D filter can hold the position throughout short walks on these devices. Demonstrate navigation with Demo Movement until measured trials establish repeatable reliable displacement. Network sharing requires the project setup above.

### Phase 6E backend verification

The production project has all five active `field-test-01` sessions with their catalog Habitat Bases and both verified legacy memberships. Jezero keeps its existing session and presence records. The deployed rules deny public reads and writes. The emulator verifies access with an enrolled anonymous UID and its refreshed credential, denies writes to the other astronaut's slot, rejects extra pose fields, and exercises independent presence streams across all five missions.

Dan’s iPhone 16 and Keren’s iPhone 14 Plus were enrolled in ARES-01 and ARES-02. Both automatically published fresh presence in Endeavour at 0 m separation. The other four sessions had no fresh presence during that observation.
