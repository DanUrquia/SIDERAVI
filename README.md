# SIDERA VI — Martian Space Exploration

SIDERA VI is a landscape iPad prototype by team **SIDERA VI** for the [2026 NASA Space Apps Challenge](https://www.spaceappschallenge.org/2026/). The project explores how astronauts on Mars could navigate terrain, consult scientific information, and coordinate with their crew.

## Phase 1 · Astronaut login

- An offline, four-digit PIN login with a glove-friendly keypad, masked entry, and clear, backspace, and retry controls.
- Two demonstration astronaut identities. A valid PIN starts a personalized 5.5-second welcome with simulated dashboard initialization and support for Reduce Motion.
- A final mission-ready screen with a Return to Login button that clears the session.
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

```sh
flutter analyze
flutter test
```

The tests exercise both astronaut identities, PIN editing and retry, welcome timing, session reset, and landscape layout with larger text.

## Prototype limits

The two demo PINs are bundled in the offline prototype authentication service and can be recovered from the app or source. Ask the team for a demo PIN. Entered PINs are held only for the current attempt and never written to persistent storage or logs. The current astronaut identity is held in memory. Use only demo codes with this prototype.

The calibration sequence is simulated user interface progress. Phase 1 ends on the welcome screen and runs without a server, database, or network connection.

## Planned work

Phase 2 will introduce the Mission Dashboard and Martian navigation. The team plans to evaluate [NASA Mars Trek](https://trek.nasa.gov/mars/) and NASA Planetary Data System products for terrain, elevation, and imagery overlays. Integrating those sources, adding scientific context, synchronizing astronaut sessions, and developing rescue workflows are future work.

## Credits

- SIDERA VI team artwork supplied the wordmark and S‑VI icon. The login is based on the team's approved Stitch design.
- [Space Grotesk](https://github.com/floriankarsten/space-grotesk) and [Inter](https://github.com/rsms/inter) are bundled for offline use. Their SIL Open Font License texts are in [assets/fonts](assets/fonts).
- OpenAI Codex assisted with implementation, debugging, and documentation. The SIDERA VI team defined the project concept, functionality, and design direction.
