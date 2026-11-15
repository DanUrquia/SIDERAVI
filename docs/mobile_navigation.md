# Smartphone navigation

For current automatic iPhone tracking and the walking procedure, see [Phase 6B.3](real_navigation_validation.md).

Phone-sized viewports open one edge-to-edge Mars Trek dashboard. The existing geographic map, route controller, camera transform, fixed-size glyphs, and Firebase presence stay mounted while the sheets change. The portrait phone UI follows the Stitch guide's dark floating surfaces, orange selected tab, and cyan orientation controls. The navigation header and dock respect system insets. The wider landscape iPad layout still uses the map, sidebar and action row.

## Phone camera

The phone opens at the mission's original regional scale. After one second, the camera takes 1.6 seconds to center the astronaut at a scale of 200 Mars meters along the 50-point scale bar. It computes the scale from the Mars 2000 projection and the astronaut's latitude. With Reduce Motion enabled, the camera changes to the final framing at the end of the delay.

The opening scale stops at the finest useful raster for the imagery covering the astronaut. Endeavour can reach the 200 m scale-bar target on iPhone 16 using the Opportunity HiRISE mosaic. Missions with coarser coverage open at a wider ground span. The renderer requests only published matrices and keeps available imagery visible during transitions. The phone keeps loading and Retry feedback for tile failures. [Mars Trek layer metadata](mars_trek_integration.md) · [Opportunity WMTS capabilities](https://trek.nasa.gov/tiles/Mars/EQ/HiRISE_Opportunity/1.0.0/WMTSCapabilities.xml)

The phone defaults to **North-up**. Its terrain remains north-up and the astronaut arrow turns with the calibrated heading. Follow turns on when the opening zoom completes. In North-up, manually panning releases Follow. **Recenter** returns the camera to the astronaut while preserving zoom.

Tap the final right-side control to enable **Heading-up**. The same camera transform rotates the terrain opposite the calibrated heading and follows accepted movement. The local arrow faces the screen top, and map labels and controls stay upright. Rotation follows the shortest arc, filters small heading changes, and holds the last valid orientation during attitude interruptions. During a pan or pinch, the gesture owns the camera. Heading updates resume afterward and accepted steps recenter the view. Tap the same control to restore North-up at the selected zoom.

Touching the map, using a camera control, or opening a bottom sheet cancels an outstanding opening zoom for that visit. Fit Area frames the published mission radius. The scale bar measures spherical Mars distance across its horizontal screen span, including when the map is rotated.

## Map controls and telemetry

The mission header reserves one line for the destination name and distance. It shows **Destination: —** when no destination is selected. Once selected, a long name can truncate while the distance stays visible. The header keeps the same height as the navigation state changes. When crew markers share a map point, their glyphs appear next to each other and keep the same geographic anchor. If the selected destination shares that point, the header identifies it.

Directly below the header, three compact cards show Mars local mean solar time (LMST) at Habitat Base, temperature availability, and Habitat Base elevation. The clock follows NASA's Mars24 algorithm using the device's UTC. Temperature displays **Unavailable** at all five sites. The Elevation card shows the MOLA estimate relative to the GMM3 Martian areoid, and **Astronaut → MOLA Topography** provides the maximum gridded elevation within that mission's radius. [Scientific missions and telemetry methods](scientific_missions.md)

Start Navigation, Return to Base, Send Ping and SOS are four orange circular buttons with dark icons. Recenter and the Heading-up toggle sit below SOS in the same right-side column. The column reduces its spacing and button size on shorter displays, keeping 44 logical-pixel touch targets. It scrolls only when the available height cannot hold all six controls. The controls return to the map when the active sheet closes. On phones, Start Navigation begins guidance to a valid destination. Return to Base confirms before selecting Habitat Base.

Fit Area, the scale bar and NASA Mars Trek attribution form one compact panel at the lower left. Tile loading and error messages occupy a row above that panel with a fixed gap. Retry re-requests the failed tiles and the scale panel stays anchored. Both overlays are hidden while a sheet is open. Close the sheet to see any remaining map error and Retry.

Send Ping and SOS each show equal-width **NO** and **YES** controls when space permits, with initial focus on **NO**. **NO** closes the dialog. **YES** places one local location marker at the estimated position or activates the local SOS alert. SOS pauses exploration until dismissed and the astronaut resumes.

## Bottom sheets

Missions, Astronaut and Crew open at full usable height on the first tap and when switching tabs. The expanded top sits just below the status-bar safe area. The sheet can scroll internally and drag down through medium and peek to dismiss. The extent button toggles between peek and full height. Tap the active tab again or use Close to dismiss. Android Back closes an open sheet first.

The sheet has rounded top corners and square bottom corners. Its bottom edge meets the top of the independently interactive dock at the shared layout boundary. The dock keeps the same height and position above the device's bottom safe area in every state. The map remains mounted while tabs change and responds to pinch and pan on exposed areas.

- **Missions** presents the three existing scientific objectives from the briefing. Tap any objective card to complete it. The entire card turns green and reads **Completed**. Tap again to return it to **Pending**. A waypoint shortcut can select a destination independently. Progress saves on that installation by astronaut ID, mission ID and objective ID, including after restart.
- **Astronaut** shows the astronaut identity, estimated Mars coordinates, exploration state, distance traveled, distance to base, movement source, position quality and measured steps when available. Earth time uses the device clock converted to Tegucigalpa (UTC−6). The sheet retains pause, resume and device-sensor controls. Distance traveled accumulates accepted walking intervals. The local step total reflects native pedometer readings. The OS may batch measurements. The total uses foreground sensor windows and excludes retrospective reports and the Walking Detection Lab.
- **Crew** connects automatically on an enrolled iOS device. A teammate in the same mission appears with an estimated Mars position and spherical separation. The offline card shows their name, astronaut ID and **OFFLINE**. [Crew setup and Firebase authorization](live_astronaut_tracking.md)

## Platform readiness

| Platform | Collection |
| --- | --- |
| iOS | The existing Core Motion attitude, Core Location and CMPedometer bridge covers iPhone and iPad. The phone runs in portrait and iPad keeps landscape. Location and motion collection use existing foreground controls and permission descriptions. Measured steps require actual Core Motion callbacks. The Walking Detection Lab remains available in iOS Movement Log as a diagnostic. |
| Android | The bridge checks the accelerometer, gyro, optional rotation vector and optional hardware step sensors. It prefers the game rotation vector for relative attitude and falls back to the standard rotation vector. When the projected screen top is too close to vertical, heading is unavailable. Android's step counter discards the pre-window hardware total, with the hardware step detector used on models that lack a counter. It supplies steps only. Live Sensors requests activity recognition when the hardware and OS require it. Sensor Test and Live Sensors can request location while in use. Approximate location remains subject to the existing movement guard. |

Both bridges stop hardware collection in the background. Android exposes capability and runtime readings through Sensor Test and can save diagnostic JSON using the system document picker. Android does not offer the experimental iOS Walking Detection Lab. The iPhone field result is recorded in [physical navigation validation](real_navigation_validation.md). [Android motion sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion) · [Android location permissions](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime) · [Apple Core Motion](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data)

## Install and pair

Run `flutter doctor -v` and `flutter devices`. Supply the existing SIDERA VI Firebase build settings through a local Dart defines file for iOS. The operator enrolls the device after the astronaut opens a mission for the first time. Dan’s iPhone 16 uses ARES-01 and Keren’s iPhone 14 Plus uses ARES-02. [Device enrollment](live_astronaut_tracking.md)

- **iOS.** Use the existing `com.bluelionsoft.sideraVi` bundle ID and development team. The app's deployment target is iOS 17.6 and its target family includes iPhone and iPad. Build, sign and install with Xcode or `flutter build ios --release --dart-define-from-file=/path/to/sidera-defines.json`. If a generic profile does not list the iPhone, select the physical device in Xcode with automatic signing so Xcode can include it. iOS may request Developer Mode or explicit trust for the installed development signing identity.
- **Android.** The unique app ID is `com.bluelionsoft.sideravi`. On a connected, ADB-authorized OPPO, run `flutter build apk --debug --target-platform android-arm64`, then `adb install -r build/app/outputs/flutter-apk/app-debug.apk` and `adb shell am start -n com.bluelionsoft.sideravi/.MainActivity`. The APK uses development signing. This phase’s automatic Crew enrollment runs on iOS.

## Physical checklist

1. Open Endeavour Crater on both phones. Check the safe areas, the four orange circles, and Recenter and Heading-up immediately below SOS. Try Fit Area, pinch or pan, and recenter. Compare marker size before and after zoom. Turn the phone in Heading-up and then in North-up to verify which layer rotates. If a tile error appears, verify that Retry is above the scale panel.
2. Tap each tab once and check that its sheet reaches the top safe area and ends at the dock. Switch between the three tabs, scroll inside a sheet, then dismiss it by dragging down or tapping its active tab or close button. Tap an objective card and restart to check that its state persists.
3. Open Send Ping and SOS separately and choose **NO**. Confirm the map gains no ping and exploration remains active. Open **Crew** and check that each iPhone connects automatically. Move one iPhone to Gale while the other stays in Endeavour to verify mission isolation. Check the other three missions and temporarily interrupt one device’s connection to verify the offline card and automatic reconnect.
4. Hold each phone with its top edge pointed along the walk. Turn the device about 90° in Heading-Up and then in North-Up. Walk while the teammate’s phone stays still, then swap roles. Check **Applied steps** and the estimated Mars distance between astronauts.
5. On an iPad, confirm the landscape dashboard, map gestures, navigation and diagnostics remain available.

## Verification

Flutter widget tests cover the four circular controls, safe-area layout, stable header, telemetry, near-full-height scrolling sheets, fixed-size markers, objective card state and persistence, safe return, and cancellation and confirmation of the local ping and SOS actions. Existing iPad, sensor and live presence tests remain in the suite. iOS tests cover the relative screen-top projection in both phone portrait and iPad landscape. Android JVM tests cover heading and step window accounting.

### Phase 6A.4 field results

Jezero opened on the iPhone 16 as ARES-01 and on the OPPO CPH2579 as ARES-02. On both phones the three tabs expanded on the first tap and switched at the same height. The dock stayed above the bottom safe area. Recenter and Follow responded below SOS. Live tile errors appeared above the compact scale panel, and Retry was tappable on both phones. The iPhone test pinched and panned. The OPPO used Fit Area, panned, and followed a route to the delta outcrop.

### Phase 6A.3 field results

- **iPhone 16, ARES-01.** The physical UI walkthrough opened Gale and Jezero, canceled both Gale dialogs, expanded all three Gale sheets, and exercised pinch and pan. A separate Gale objective check restored the saved progress after terminating and reopening the app, then returned the objective to its starting state.
- **OPPO CPH2579, ARES-02.** The physical walkthrough opened Gale and Jezero and checked the three telemetry cards, the fixed header, dialog cancellation, and the three expanded sheets. The Gale objective state survived a restart and was restored after the test. Fit area zoom and pan worked on the Gale map.
- These checks used the local demo session. The paired Firebase field results below are from Phase 6A.

### Earlier Phase 6A field results

- **OPPO CPH2579, Android 15.** ADB installed and launched the DEV APK. The physical device showed the portrait Jezero map and a scrolled Crew sheet as ARES-02, with Mars Trek imagery behind them. Android's sensor service reported accelerometer, gyro, game rotation vector, rotation vector, step counter and step detector. The app registered foreground motion listeners. A controlled sensor capture, calibration and step test remain to be done.
- **iPhone 16.** A generic development profile failed installation because it excluded the iPhone. Xcode signed a device-specific build, and CoreDevice subsequently confirmed installation and launch. Developer Mode was enabled. The portrait Jezero map and Crew sheet were visible as ARES-01 on the physical phone, with Mars Trek imagery behind them.
- **Paired session.** Both assigned accounts joined Jezero and each displayed the other astronaut's live marker. The OPPO followed a selected Demo Movement waypoint to 0 m and the remote marker moved on the iPhone. During a brief OPPO network interruption, the OPPO displayed Reconnecting and the iPhone showed ARES-02's last-known marker as offline. Restoring the network brought the OPPO back to Connected and restored the live ARES-02 marker on the iPhone. The OPPO's original airplane mode and Wi-Fi settings were restored after this check.
- The field check exposed an overlapping teammate and Habitat base label. The marker now uses a fixed visual offset and a tether at that anchor. The regression test checks separate labels at 1×, 2× and 4× and confirms that tapping the shifted marker still targets its actual position. The phone's recenter and follow buttons also have distinct icons.
