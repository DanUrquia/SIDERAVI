# Phase 5A sensor feasibility

Open a mission dashboard and tap **Sensor Test**. **Start Test** starts a foreground measurement window and requests When In Use location authorization if needed. Motion can still be tested if location is denied or unavailable. **Stop Test**, leaving the screen, and backgrounding the app stop collection. After backgrounding, tap **Start Test** to begin a new session.

## Sensors and devices

| Wi-Fi model | iPadOS | Apple specifications |
| --- | --- | --- |
| iPad Pro 12.9-inch, third generation | 26.7.3 | Three-axis gyro, accelerometer, digital compass; GPS/GNSS listed on the cellular model |
| iPad Air, fourth generation | 27.0.1 | Three-axis gyro, accelerometer, digital compass; GPS/GNSS listed on the cellular model |

[Apple iPad Pro specifications](https://support.apple.com/en-us/111979) · [Apple iPad Air specifications](https://support.apple.com/en-us/111905)

Sensor Test reads runtime availability for fused device motion, gyro, accelerometer, magnetometer, the Core Location compass API, and system-wide Location Services. Availability describes what the OS reports. Accuracy and sample delivery depend on the environment, authorization, and current device state. Apple’s device specifications describe the hardware separately from runtime readings. Core Location does not disclose which positioning technology produced a fix. A working internet connection provides no guarantee of a usable location fix.

- [Core Location](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services) supplies Earth location, timestamps, horizontal accuracy, authorization and, when available, speed, course and compass readings. The bridge requests When In Use authorization only after **Start Test**.
- [Core Motion](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data) supplies device attitude and rotation rate in the `xArbitraryZVertical` frame. The Runner registers the Swift bridge with the existing Flutter engine callback used by `FlutterSceneDelegate`.
- Native callbacks are batched and drained roughly four times per second. Motion requests 10 samples per second. The observed rates are calculated from positive intervals across the most recent 20 timestamps. Sample delay estimates the time between measurement and delivery to native code, separate from the screen refresh and the elapsed time between a physical turn or walk and a displayed change.

## Device verification

A signed release build launched on both target iPads. On each device, the assigned demo astronaut signed in, selected Jezero Crater, loaded its NASA Mars Trek dashboard, and opened Sensor Test. Both iPads reported Location Services, fused device motion, gyro, accelerometer, magnetometer and the compass API available. The initial authorization was Not determined, with zero samples before Start Test. Capability checks alone establish neither location accuracy nor heading quality.

Both iPads subsequently showed Authorized and Precise Location available. These are aggregate readings from the initial indoor device check. The devices were handled during the check, so the displacement values are not a controlled stationary drift measurement.

| Observed readings | iPad Pro | iPad Air |
| --- | --- | --- |
| Reported Earth accuracy | 26–44 m | 25–32 m |
| Recent location delivery | 0.10–0.17 Hz | 0.11–0.15 Hz |
| Relative motion delivery | About 10 Hz | About 9–10 Hz |
| Largest apparent displacement seen | 6 m | 7 m |
| Example displacement and combined uncertainty | 6 m vs. 65 m | 7 m vs. 62 m |

Both devices labeled the example displacement inconclusive and accepted no movement segments after the baseline. The first fixes observed had about 3–4 seconds of native callback delay. Later fixes shown had about 0.01–0.04 seconds of callback delay, separate from the several seconds between location updates. Motion callback delay displayed about 0.00–0.01 seconds at the screen’s precision. Relative readings changed during handling on both iPads. The Pro intermittently returned a qualifying true device heading with about 19–20° reported uncertainty. These readings do not validate north accuracy, direction of travel, or walking displacement.

Separate short runs were stopped and exported on each iPad. The table summarizes those exports without publishing timestamps, coordinates, or raw traces.

| Export result | iPad Pro | iPad Air |
| --- | --- | --- |
| Run length | 12.1 s | 5.7 s |
| Location fixes received / accepted | 7 / 1 baseline | 5 / 1 baseline |
| Accuracy range after invalid/stale filtering | 18.5–34.0 m | 30.8–43.3 m |
| Peak apparent displacement | 5.9 m | 5.6 m |
| Final apparent displacement / combined uncertainty | 3.6 m / 53.1 m | 5.6 m / 76.7 m |
| Valid relative orientation samples / recent rate | 118 / 9.98 Hz | 57 / 9.96 Hz |

Each export had zero accepted path after the baseline and no usable speed or course. The Air rejected two stale fixes. Those samples remained in the raw series, so the raw timestamp rate and longest sample age should not be read as steady delivery frequency or measured response to a walk. All exported motion samples had usable relative angles in landscape right. The traces show substantial rotation, but without measured turn angles or a stationary interval they do not establish angular error or drift. The controlled stationary, directional quarter/half turn and return-to-start trials, opposite landscape orientation, and measured walks are still open.



## Interpreting readings

**Earth location.** The UI shows Core Location’s horizontal accuracy radius in meters. Precise authorization allows full accuracy when available, independent of the accuracy of a specific fix. Latitude and longitude can only be displayed while a valid, recent fix exists. A position retained on the stopped test is interpreted as of the stop time. Earth fixes and the Mars map use independent coordinate systems.

**Physical movement.** The app uses great-circle distance on Earth. It retains raw fixes separately and excludes invalid coordinates or accuracy, fixes older than 15 seconds on delivery, fixes more than one second ahead of the clock, fixes with over 100 m reported uncertainty, and out-of-order or repeated timestamps from the accepted path. After the baseline, each accepted step must exceed the sum of both fixes’ reported accuracy radii. The same comparison is made independently against the origin. If the apparent displacement fits within that radius sum, movement is inconclusive. The thresholds are diagnostic choices. They are neither a statistical confidence bound nor a claim about Wi-Fi positioning accuracy. The accepted path is a coarse sum and can miss curves or genuine short steps. Speed is displayed alongside its reported uncertainty when available. Course over ground requires speed above its uncertainty and a valid course accuracy of 30° or better.

**Orientation.** The arrow follows the screen’s current top edge projected onto the horizontal plane. The first usable sample defines zero. **Calibrate Orientation** resets zero, and an interface orientation change establishes a new reference. The relative yaw is clockwise from that reference, with pitch and roll shown on Core Motion’s device axes. Pointing the screen top nearly vertically makes its horizontal direction undefined. Relative heading can drift and represents the device. Observe device orientation and the direction the operator walks as separate quantities.

**Absolute heading.** The screen shows true device heading only if Core Location reports a valid true-north value no more than five seconds old with reported heading accuracy from 0° to 25°. A magnetometer or gyro availability flag alone establishes neither north nor accuracy. A compass can be affected by nearby metal, magnets, electronics, or a case. Direction of travel is supplied independently by Core Location course when speed and course have usable accuracy.

**Quality.** Good requires a fresh fix at 15 m accuracy or better, Precise Location, a usable relative heading, and at least four recent motion intervals averaging 0.2 seconds or less with no interval over 0.5 seconds. Limited identifies approximate or stale location, or sparse or missing orientation. Unavailable means there is no fresh fix or sufficiently consistent heading. These labels describe sensor readings rather than verified walking accuracy.

## Repeatable physical procedure

1. Use the same measured course on both iPads, with comparable conditions, and record only aggregate values for shared notes. Start a clean run and wait for a fresh Earth fix before each distance trial. Record “no usable fix” if none arrives.
2. Leave the iPad stationary for 60 seconds. Record received and accepted counts, horizontal accuracy, update rate, peak observed displacement, drift within the uncertainty bound, and any false movement classifications.
3. Reset for each trial. Walk roughly 10 m, 30 m, and 50–100 m on a safe accessible course with a measured start and finish. Compare observed displacement, uncertainty, accepted path, and the elapsed time from reaching the finish to the first meaningful update. Repeat in the intended indoor and outdoor environments.
4. Start with the screen facing up and its top edge pointing toward a visible reference. Calibrate, measure stationary yaw drift, turn the top edge approximately 90° clockwise, continue to 180°, then return to the reference. Compare displayed angles, response delay, and return error. Repeat in the other landscape orientation and separately test a deliberate interface flip. Observe the arrow while carrying the iPad on the measured course.
5. Stop the test and check that counts stop advancing. If needed, use **Export Test Report** from the stopped screen and select a local Files destination. The JSON can contain exact Earth coordinates. Share aggregate accuracy, displacement, timing and drift with the team, and keep coordinate traces out of GitHub.

## Report and next phase

Each report contains the hardware model family, iPadOS version, test timestamps, capability and permission status, retained samples, summary counts and limitations. It contains no astronaut identity or unique device ID. Each raw, filtered, and orientation series retains the latest 900 entries. Whole-test counts and accumulated path are retained even as older samples fall out of the report. Before export all observations live in memory. The iPad share sheet appears only after an explicit export and its temporary file is deleted when sharing completes.

Advance relative orientation separately if repeated rotation and drift trials on both devices meet the prototype’s needs. Keep map translation manual or simulated until measured walking trials demonstrate repeatable displacement above uncertainty and acceptable update latency. Evaluate external GNSS or another validated positioning reference if the Wi-Fi-only devices cannot distinguish the intended walking distances. Evaluate any Earth-to-Mars conversion and synchronization after the feasibility review.
