# SIDERA VI — Martian Space Exploration

SIDERA VI is a landscape iPad prototype by team **SIDERA VI** for the [2026 NASA Space Apps Challenge](https://www.spaceappschallenge.org/2026/). The project explores how astronauts on Mars could navigate terrain, consult scientific information, and coordinate with their crew.

## Login, mission selection and dashboard

- An offline, four-digit PIN login with a glove-friendly keypad, masked entry, and clear, backspace, and retry controls.
- Dan Urquía (ARES-01) and Adrian Flores (ARES-02) each have a demonstration PIN. A valid PIN starts a personalized 5.5-second welcome with simulated dashboard initialization and support for Reduce Motion.
- Five offline Mars mission briefings with authentic rover or orbital imagery, regional coordinates and educational objectives. Browse with the arrows or a horizontal swipe.
- Start Mission opens the interactive dashboard. Back to Missions restores the selected briefing. Back from Select Mission clears the session and returns to login.
- Every mission has a distinct offline NASA orbital backdrop, a demo grid, a habitat base, three selectable landmarks and a simulated teammate.
- Tap a point inside the exploration boundary, tap a landmark or select the demo teammate to set a destination. Pinch and drag the map or use the zoom and reset buttons. Start Navigation moves the astronaut along a straight demo route that can be paused or resumed. Return to Base plans the same kind of route to the habitat.
- Send Ping places a location, item or danger marker on the iPad. SOS requires confirmation, highlights the signed-in astronaut, and pauses exploration until the user cancels and resumes.
- The official SIDERA VI wordmark, S‑VI home-screen icon, and display name.

## Run on iPad

The app uses **Flutter 3.35.4** and **Dart 3.9.2**. It targets iPads running **iPadOS 17.6 or later** and uses both landscape orientations in full screen. Use macOS with Xcode and a compatible iPad simulator or a trusted, developer-enabled iPad.

From the repository root:

```sh
flutter pub get
flutter devices
flutter run -d <ipad-device-id>
```

For a physical iPad, select an Apple Development signing team with access to the Runner bundle identifier in `ios/Runner.xcworkspace`. The existing team can use the project's signing configuration. Other developers can select their own team and bundle ID locally if required by Xcode.

On iPadOS 27, UIKit requires scene-based launch for builds linked against the iOS 27 SDK. The Runner's single scene loads `Main.storyboard` through Flutter 3.35.4's built-in `FlutterSceneDelegate`. The storyboard's Flutter view controller calls `FlutterPluginRegistrant` to register plugins with its engine.

```sh
flutter analyze
flutter test
```

The tests exercise both astronauts, PIN editing and retry, welcome timing, mission browsing, all five dashboards, map gestures and marker alignment, navigation, pings, demo SOS, session reset, and landscape layout with larger text.

## Prototype limits

The two demo PINs are bundled in the offline prototype authentication service and can be recovered from the app or source. Ask the team for a demo PIN. Entered PINs are held only for the current attempt and never written to persistent storage or logs. The current astronaut identity is held in memory. Use only demo codes with this prototype.

The app runs offline. Calibration, mission objectives, difficulty, exploration boundaries, movement, teammate position, pings and SOS are simulated. Starting a dashboard opens a fresh local scenario. Demo markers and straight-line distances use a separate north-up grid with no geographic registration, terrain routing, GPS, or device-to-device communication. Pings and SOS only affect the local interface.

The Earth clock reads the device time in Tegucigalpa (UTC−6). Mars local solar time and temperature are illustrative. Elevation displays published regional relief when available. Image credits and geographic references are in the [Mars mission sources](docs/mars_mission_sources.md).

## Planned work

Future phases will explore georeferenced terrain and real navigation. The team plans to evaluate [NASA Mars Trek](https://trek.nasa.gov/mars/) and NASA Planetary Data System products for terrain, elevation, and imagery overlays. Integrating those sources, adding scientific context, synchronizing astronaut sessions, and developing rescue workflows are future work.

## Credits

- SIDERA VI team artwork supplied the wordmark and S‑VI icon. The login is based on the team's approved Stitch design.
- [Space Grotesk](https://github.com/floriankarsten/space-grotesk) and [Inter](https://github.com/rsms/inter) are bundled for offline use. Their SIL Open Font License texts are in [assets/fonts](assets/fonts).
- OpenAI Codex assisted with implementation, debugging, and documentation. The SIDERA VI team defined the project concept, functionality, and design direction.
