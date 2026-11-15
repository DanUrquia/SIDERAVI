# Phase 6A smartphone navigation

Phone-sized viewports open one edge-to-edge Mars Trek dashboard. The existing geographic map, route controller, camera transform, fixed-size glyphs, and Firebase presence stay mounted while the sheets change. The portrait phone UI follows the Stitch guide's dark floating surfaces, orange selected tab, and cyan orientation controls. The navigation header and dock respect system insets. The wider landscape iPad layout still uses the map, sidebar and action row.

## Map controls and telemetry

The mission header reserves one line for the destination name and distance. It shows **Destination: —** when no destination is selected. Once selected, a long name can truncate while the distance stays visible. The header keeps the same height as the navigation state changes. When crew markers cluster near Habitat Base, the phone offsets the teammate marker to leave the base label readable and draws a tether to its map coordinate.

Directly below the header, three equal-width floating cards show Mars local solar time, temperature and Habitat Base elevation. The time is a demo reference, temperature is illustrative, and elevation is the existing MOLA grid estimate relative to the GMM3 Martian areoid. The elevation card's accessibility label includes the datum. The row fits under the system insets on phones. [Scientific missions and MOLA method](scientific_missions.md)

Start Navigation, Return to Base, Send Ping and SOS are four orange circular buttons with dark icons in a single column on the right. Recenter and Follow sit on the left. The action column returns when the active sheet closes. The Start control requires a valid destination in Demo Movement. Return to Base asks for confirmation, then starts a route from the current position in Demo Movement or selects base in Live Sensors.

Send Ping and SOS each show equal-width **NO** and **YES** controls when space permits, with initial focus on **NO**. **NO** closes the dialog. **YES** places one local location marker at the current simulated position or activates the existing local demo SOS, respectively. Demo SOS pauses exploration until dismissed and the astronaut resumes. The iPad retains its ping picker and emergency controls.

## Bottom sheets

Missions, Astronaut and Crew open at medium height. Drag up or use the extent button to expand to just below the top system inset, then scroll the content. Drag down through medium and peek to dismiss, tap the active tab again, or use Close. Android Back dismisses an open sheet first. The sheet has rounded top corners and square bottom corners, and it meets the dock on one continuous navy surface. The map stays mounted throughout, with pinch and pan on the exposed area.

- **Missions** presents the three existing scientific objectives from the briefing. Tap any objective card to complete it. The entire card turns green and reads **Completed**. Tap again to return it to **Pending**. A waypoint shortcut can select a destination independently. Progress saves on that installation by astronaut ID, mission ID and objective ID, including after restart.
- **Astronaut** shows the astronaut identity, simulated Mars coordinates, mission state, distance traveled, distance to base, movement source, position quality and measured steps when available. Earth time uses the device clock converted to Tegucigalpa (UTC−6). The sheet retains pause, resume and device-sensor controls. Distance traveled accumulates accepted simulated route segments and excludes the initial position and Firebase restores. The local step total sums accepted native pedometer readings while Live Sensors is active and the mission is unpaused. The OS may batch measurements. The total uses foreground sensor windows and excludes retrospective reports and the Walking Detection Lab.
- **Crew** shows the authenticated roster and distinguishes shared, stale, offline and simulated positions. Separation uses Mars spherical geometry. Relative position describes the map direction from the local astronaut. The presence schema carries no shared step count. Join Crew uses the existing account dialog.

## Platform readiness

| Platform | Collection |
| --- | --- |
| iOS | The existing Core Motion attitude, Core Location and CMPedometer bridge covers iPhone and iPad. The phone runs in portrait and iPad keeps landscape. Location and motion collection use existing foreground controls and permission descriptions. Measured steps require actual Core Motion callbacks. The Walking Detection Lab remains available in iOS Movement Log as a diagnostic. |
| Android | The bridge checks the accelerometer, gyro, optional rotation vector and optional hardware step sensors. It prefers the game rotation vector for relative attitude and falls back to the standard rotation vector. When the projected screen top is too close to vertical, heading is unavailable. Android's step counter discards the pre-window hardware total, with the hardware step detector used on models that lack a counter. It supplies steps only. Live Sensors requests activity recognition when the hardware and OS require it. Sensor Test and Live Sensors can request location while in use. Approximate location remains subject to the existing movement guard. |

Both bridges stop hardware collection in the background. Android exposes capability and runtime readings through Sensor Test and can save diagnostic JSON using the system document picker. Android does not offer the experimental iOS Walking Detection Lab. The shared Live Sensors movement guard remains the source of any accepted Earth-to-Mars movement. Physical walking-driven navigation remains unvalidated. [Android motion sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion) · [Android location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime) · [Apple Core Motion](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data)

## Install and pair

Run `flutter doctor -v` and `flutter devices`. Supply the existing SIDERA VI Firebase build settings through a local Dart defines file. The native builds use the same Dart REST/SSE client and the `sidera-vi` project at `missions/jezero/sessions/field-test-01`. Account credentials are entered in the app. The iPhone uses ARES-01, and the OPPO uses ARES-02.

- **iOS.** Use the existing `com.bluelionsoft.sideraVi` bundle ID and development team. The app's deployment target is iOS 17.6 and its target family includes iPhone and iPad. Build, sign and install with Xcode or `flutter build ios --release --dart-define-from-file=/path/to/sidera-defines.json`. If a generic profile does not list the iPhone, select the physical device in Xcode with automatic signing so Xcode can include it. iOS may request Developer Mode or explicit trust for the installed development signing identity.
- **Android.** The unique app ID is `com.bluelionsoft.sideravi`. On a connected, ADB-authorized OPPO, run `flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=/path/to/sidera-defines.json`, then `adb install -r build/app/outputs/flutter-apk/app-debug.apk` and `adb shell am start -n com.bluelionsoft.sideravi/.MainActivity`. The APK uses development signing.

## Physical checklist

1. Open Gale Crater on both phones, then repeat in another mission. Check the system insets, three telemetry cards, stable header height when a destination is selected, and four orange circles aligned on the right. Pinch and pan, and compare marker size before and after zoom.
2. Open each sheet, drag to the top safe area, scroll, and dismiss. Confirm the sheet meets the dock and the Astronaut sheet shows Earth time. Tap an objective card to turn it green, restart the app to check persistence, then tap the card again to restore its prior state.
3. Open Send Ping and SOS separately and choose **NO**. Confirm the map gains no ping and exploration remains active. For the paired Jezero session, use **Crew → Join Crew** with each assigned account and verify the other astronaut's marker. Test stale and reconnect behavior by temporarily interrupting one device's connection.
4. In **Astronaut → Sensor Test**, compare reported capability and sample delivery. In Live Sensors, align the top edge of the phone with a visible point, calibrate the arrow, then turn the device about 90° with the top edge near the horizontal plane. Record real sample availability and any permission or freshness limitations separately from map movement.
5. On an iPad, confirm the landscape dashboard, map gestures, navigation and diagnostics remain available.

## Verification

Flutter widget tests cover the four circular controls, safe-area layout, stable header, telemetry, near-full-height scrolling sheets, fixed-size markers, objective card state and persistence, safe return, and cancellation and confirmation of the local ping and SOS actions. Existing iPad, sensor and live presence tests remain in the suite. iOS tests cover the relative screen-top projection in both phone portrait and iPad landscape. Android JVM tests cover heading and step window accounting.

### Phase 6A.3 field results

- **iPhone 16, ARES-01.** The physical UI walkthrough opened Gale and Jezero, canceled both Gale dialogs, expanded all three Gale sheets, and exercised pinch and pan. A separate Gale objective check restored the saved progress after terminating and reopening the app, then returned the objective to its starting state.
- **OPPO CPH2579, ARES-02.** The physical walkthrough opened Gale and Jezero and checked the three telemetry cards, the fixed header, dialog cancellation, and the three expanded sheets. The Gale objective state survived a restart and was restored after the test. Fit area zoom and pan worked on the Gale map.
- These checks used the local demo session. The paired Firebase field results below are from Phase 6A.

### Earlier Phase 6A field results

- **OPPO CPH2579, Android 15.** ADB installed and launched the DEV APK. The physical device showed the portrait Jezero map and a scrolled Crew sheet as ARES-02, with Mars Trek imagery behind them. Android's sensor service reported accelerometer, gyro, game rotation vector, rotation vector, step counter and step detector. The app registered foreground motion listeners. A controlled sensor capture, calibration and step test remain to be done.
- **iPhone 16.** A generic development profile failed installation because it excluded the iPhone. Xcode signed a device-specific build, and CoreDevice subsequently confirmed installation and launch. Developer Mode was enabled. The portrait Jezero map and Crew sheet were visible as ARES-01 on the physical phone, with Mars Trek imagery behind them.
- **Paired session.** Both assigned accounts joined Jezero and each displayed the other astronaut's live marker. The OPPO followed a selected Demo Movement waypoint to 0 m and the remote marker moved on the iPhone. During a brief OPPO network interruption, the OPPO displayed Reconnecting and the iPhone showed ARES-02's last-known marker as offline. Restoring the network brought the OPPO back to Connected and restored the live ARES-02 marker on the iPhone. The OPPO's original airplane mode and Wi-Fi settings were restored after this check.
- The field check exposed an overlapping teammate and Habitat base label. The marker now uses a fixed visual offset and a tether at that anchor. The regression test checks separate labels at 1×, 2× and 4× and confirms that tapping the shifted marker still targets its actual position. The phone's recenter and follow buttons also have distinct icons.
