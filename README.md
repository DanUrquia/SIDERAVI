# SIDERA VI — Martian Space Exploration

SIDERA VI is a smartphone and iPad prototype by team **SIDERA VI** for the [2026 NASA Space Apps Challenge](https://www.spaceappschallenge.org/2026/). The project explores how astronauts on Mars could navigate terrain, consult scientific information, and coordinate with their crew.

## Astronaut selection and exploration

- An offline, four-digit astronaut selection PIN with a glove-friendly keypad, masked entry, and clear, backspace, and retry controls.
- Dan Urquía (ARES-01) and Adrian Flores (ARES-02) each have an expedition PIN. A valid PIN starts the personalized 5.5-second welcome and respects Reduce Motion.
- Browse Endeavour Crater, Gale Crater, Columbia Hills, Valles Marineris and Jezero Crater in that order. Each briefing has rover or orbital imagery, regional coordinates and scientific objectives.
- Start Mission opens the dashboard and automatically connects enrolled iOS devices to that mission’s Crew session. Back to Missions restores the selected briefing. Back from Select Mission returns to astronaut selection. [Crew setup and Firebase authorization](docs/live_astronaut_tracking.md)
- Each dashboard centers on its mission region with Habitat Base and selectable landmarks. On phones, the last map control toggles Heading-Up and North-Up. Uncached tiles need internet access. [NASA Mars Trek imagery](docs/mars_trek_integration.md)
- Tap an in-bounds map point, a landmark, or a connected teammate to set a destination. On phones, Start Navigation shows direct guidance, and Return to Base offers guidance when the estimated position is more than 100 m from base.
- Send Ping places a location, item or danger marker on the current device. SOS requires confirmation, highlights the signed-in astronaut, and pauses exploration until the user cancels and resumes.
- Phones begin tracking physical steps automatically on mission entry, even offline and without a destination. Relative device attitude and estimated stride determine Mars movement. The iPhone restores its saved mission position. The landscape iPad dashboard retains its simulation controls. [iPhone walking procedure](docs/real_navigation_validation.md).
- **Sensor Test** opens a foreground Earth location and device orientation diagnostic from the dashboard. It shows reported accuracy, movement uncertainty, relative heading, and sample timing. Optional JSON export uses the system share sheet or document picker. [Phase 5A procedure and limitations](docs/sensor_feasibility.md).
- **Movement Log** is an optional diagnostic with step counts, estimates, and an opt-in local timeline. Map markers retain their screen size during zoom.
- **Walking Detection Lab** on iOS opens from Movement Log and tests whether the iPad's acceleration and rotation reveal rhythmic walking. It supports labeled captures, manual step counts, and local JSON replay. [Phase 5F field procedure and results](docs/walking_detection_feasibility.md).
- The official SIDERA VI wordmark, S‑VI home-screen icon, and display name.

## Run on phones and iPad

On phones, the dashboard puts Missions, Astronaut and Crew sheets over one full-screen map. The wide dashboard remains available on iPad. The iOS field setup uses ARES-01 on Dan’s iPhone 16 and ARES-02 on Keren’s iPhone 14 Plus. [Mobile navigation and device verification](docs/mobile_navigation.md)

The app uses **Flutter 3.35.4** and **Dart 3.9.2**. It targets **iOS and iPadOS 17.6 or later** and uses both landscape orientations on iPad. Use macOS with Xcode and a compatible iPad simulator or a trusted, developer-enabled iPad.

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

The tests exercise both astronauts, PIN editing and retry, welcome timing, mission browsing, all five dashboards, map gestures and marker alignment, navigation, pings, demo SOS, session reset, and landscape layout with larger text. Sensor tests use mocked data to cover permissions, filtering, geodesic distance, calibration, arrow rotation, lifecycle, reset and export.

## Prototype limits

The two astronaut PINs are bundled in the app for offline roster selection. Firebase authorizes device enrollment separately from the local PIN. On phones, pings and SOS affect the local interface.

The mission briefings and physical step tracking work offline. PDR estimates positions on the Mars 2000 sphere using a calibrated local direction and measured steps. Crew sharing publishes the estimated Mars pose to the selected mission. Mars Trek imagery is cached in memory for the current run.

The phone shows local mean solar time at Habitat Base calculated with NASA Mars24. Temperature appears as **Unavailable**. The base and maximum gridded elevations use NASA MOLA topography referenced to the GMM3 areoid. [Scientific missions and telemetry methods](docs/scientific_missions.md)

## Credits

- SIDERA VI team artwork supplied the wordmark and S‑VI icon. The login is based on the team's approved Stitch design.
- [Space Grotesk](https://github.com/floriankarsten/space-grotesk) and [Inter](https://github.com/rsms/inter) are bundled for offline use. Their SIL Open Font License texts are in [assets/fonts](assets/fonts).
- OpenAI Codex assisted with implementation, debugging, and documentation. The SIDERA VI team defined the project concept, functionality, and design direction.
