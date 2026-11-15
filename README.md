# SIDERA VI — Martian Space Exploration

SIDERA VI is a smartphone and iPad prototype by team **SIDERA VI** for the [2026 NASA Space Apps Challenge](https://www.spaceappschallenge.org/2026/). The project explores how astronauts on Mars could navigate terrain, consult scientific information, and coordinate with their crew.

## Login, mission selection and dashboard

- An offline, four-digit PIN login with a glove-friendly keypad, masked entry, and clear, backspace, and retry controls.
- Dan Urquía (ARES-01) and Adrian Flores (ARES-02) each have a demonstration PIN. A valid PIN starts a personalized 5.5-second welcome with simulated dashboard initialization and support for Reduce Motion.
- Five offline Mars mission briefings with authentic rover or orbital imagery, regional coordinates and educational objectives. Browse with the arrows or a horizontal swipe.
- Start Mission opens the interactive dashboard. Back to Missions restores the selected briefing. Back from Select Mission clears the session and returns to login.
- Each dashboard centers on its mission region with [NASA Mars Trek imagery](docs/mars_trek_integration.md), Habitat Base, and selectable landmarks. Uncached tiles need internet access.
- Tap an in-bounds map point, a landmark, or a connected teammate to set a destination. On phones, Start Navigation shows direct guidance, and Return to Base offers guidance when the estimated position is more than 100 m from base.
- Send Ping places a location, item or danger marker on the current device. SOS requires confirmation, highlights the signed-in astronaut, and pauses exploration until the user cancels and resumes.
- Phones begin tracking physical steps automatically on mission entry, even offline and without a destination. Relative device attitude and estimated stride determine Mars movement. The iPhone restores its saved mission position. The landscape iPad dashboard retains its simulation controls. [iPhone walking procedure](docs/real_navigation_validation.md).
- **Sensor Test** opens a foreground Earth location and device orientation diagnostic from the dashboard. It shows reported accuracy, movement uncertainty, relative heading, and sample timing. Optional JSON export uses the system share sheet or document picker. [Phase 5A procedure and limitations](docs/sensor_feasibility.md).
- **Movement Log** is an optional diagnostic with step counts, estimates, and an opt-in local timeline. Map markers retain their screen size during zoom.
- **Walking Detection Lab** on iOS opens from Movement Log and tests whether the iPad's acceleration and rotation reveal rhythmic walking. It supports labeled captures, manual step counts, and local JSON replay. [Phase 5F field procedure and results](docs/walking_detection_feasibility.md).
- The official SIDERA VI wordmark, S‑VI home-screen icon, and display name.

## Run on phones and iPad

On phones, the dashboard puts Missions, Astronaut and Crew sheets over one full-screen map. The wide dashboard remains available on iPad. The field devices use ARES-01 on iPhone 16 and ARES-02 on OPPO. [Mobile navigation, Android setup and device verification](docs/mobile_navigation.md).

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

The two demo PINs are bundled in the offline prototype authentication service and can be recovered from the app or source. Ask the team for a demo PIN. Entered PINs are held only for the current attempt and never written to persistent storage or logs. The current astronaut identity is held in memory. Use only demo codes with this prototype.

Login, mission briefings, and physical step tracking run offline. Mars Trek tiles are cached in memory for the current run. Phone navigation estimates positions on the Mars 2000 sphere with a local direction reference. Optional Firebase sharing sends the estimated Mars pose and crew presence. Mission objectives, pings, and SOS are educational simulations. Pings and SOS affect the local interface.

The Earth clock reads the device time in Tegucigalpa (UTC−6). Mars local solar time and temperature are illustrative. Elevation displays published regional relief when available. Image credits and geographic references are in the [Mars mission sources](docs/mars_mission_sources.md).

## Planned work

Future phases will explore scientific navigation, NASA Planetary Data System elevation products, astronaut synchronization, and rescue workflows.

## Credits

- SIDERA VI team artwork supplied the wordmark and S‑VI icon. The login is based on the team's approved Stitch design.
- [Space Grotesk](https://github.com/floriankarsten/space-grotesk) and [Inter](https://github.com/rsms/inter) are bundled for offline use. Their SIL Open Font License texts are in [assets/fonts](assets/fonts).
- OpenAI Codex assisted with implementation, debugging, and documentation. The SIDERA VI team defined the project concept, functionality, and design direction.
