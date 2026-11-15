# Phase 5D live movement validation

This is a historical engineering record of the movement guard. See [current iPhone step navigation](real_navigation_validation.md) and [current device layouts](mobile_navigation.md) for the submitted build.

The location guard below is retained for optional diagnostics. [Phase 6B.2 step navigation](real_navigation_validation.md) drives the live Mars position.

## What the existing evidence establishes

Phase 5C recorded an approximately 202 m change in the Pro's shared simulated position between two Live Sensors snapshots. The snapshots contain simulated coordinates, the current mode and quality, and server timestamps. They contain no raw Earth fixes, history of accepted steps, or position writer. Both displayed samples said **Position Uncertain**. The exact cause of the historical shift remains unconfirmed.

A synthetic replay against commit `2f63bdd` reproduced a plausible path to the same size of jump. The replay used a stationary baseline, 30 m reported accuracy on the baseline and later fixes, then two fixes 202 m away with identical coordinates and timestamps two seconds apart. At 50 seconds since the baseline the old lower-bound check allowed 142 m (202 minus 60 m) across that interval. The second fix satisfied the direction and proximity checks. The old code applied the full 202 m as one simulated Mars step. The replay shows how a correlated change in an Earth location estimate could produce that outcome. It does not establish that the field fix came from Wi-Fi or that this replay matches the original sequence.

The investigation traced the other position writers:

- The Demo Movement ticker changes position only while its source is enabled. Switching into Live Sensors cancels the demo route without moving the marker. Actions taken just before the switch can still change the position while Demo Movement is active.
- Firebase can restore the local astronaut's stored simulated pose on the first accepted session snapshot. Subsequent presence snapshots update remote markers. A reconnect within the open dashboard reuses the same restoration guard. The Phase 5C reconnect preserved both positions. The field snapshots do not record the full transition sequence, so the absence of a restoration event for the jump cannot be proved retroactively.
- Foreground resume, location gaps, and switching modes reset the Earth window. Establishing a fresh baseline does not apply displacement. Reconnection alone does not reset Earth tracking.
- The map and near-1:1 Earth-to-Mars conversion tests preserve scale, east/north direction, longitude wrapping, and map anchoring. The observed shift exists in the shared coordinates, so a visual marker offset, pan, zoom, or orientation arrow alone cannot explain it.
- Previously, a position write could be triggered before the accepted quality reached the same pose, and a later fix could revert quality to uncertain. The current display and metadata alone are insufficient to infer which location decision produced a previous position. The new controller sets accepted quality before publishing a changed sensor-derived pose.

## Movement guard

Live Sensors still requires Precise Location and fresh valid Core Location samples. A clean baseline uses the first eligible fix. The filter excludes locations sampled before the active window, stale, malformed or out-of-order fixes, software-simulated fixes when flagged, and fixes with reported accuracy worse than 50 m. A gap over 30 seconds takes a new baseline without moving.

A movement candidate must exceed the baseline and sample accuracy radii added together. A baseline or successive-fix jump above both 40 m and the corresponding combined uncertainty puts the sensor position on hold. The last Mars position is retained and the dashboard shows **Position Uncertain**. The 40 m ceiling is an explicit operational limit for a single experimental step, separate from the accuracy requirement and independent of how long the baseline has been in place. The hold survives foreground resume, permission interruptions, mode changes, and network reconnection within the open mission. **Rebaseline** clears it on explicit operator action and uses the next eligible Earth fix while retaining the current simulated position.

Below the jump limit, the filter needs three outward-progressing candidates from separate Core Location callbacks. Samples must be at least 0.5 seconds apart, no more than 15 seconds apart, and make at least 2 m of course-aligned progress. The walking envelope is measured from the most recent fix consistent with the baseline, limiting the contribution of older waiting time. Candidates also need a reported speed of at most 3.5 m/s, speed accuracy at most 1 m/s, speed above its reported error by at least 0.35 m/s, and a course within 45° of the displacement with reported course accuracy at most 35°. Identical clustered fixes cannot by themselves establish progression. Core Location speed and course can be unavailable or correlated with the same position estimate, so the checks are corroboration within one API and do not establish independent ground truth.

Accepted travel uses the displacement outside the combined reported uncertainty, projected along its estimated bearing at 1:1 scale. It is deliberately conservative and can undercount real distance. The radii are accuracy estimates, so the applied value is neither a confidence interval nor a certified lower bound. Indoor Wi-Fi fixes with wide uncertainty or unavailable speed and course may leave both devices stationary through a real walk. A gradual, correlated error remains possible. Use an independent measured walking course to evaluate performance.

## Read and export a local capture

1. In the dashboard, open **Movement Log** or **Review Position Hold**. Tap **Start Capture**. Close the overlay to run the dashboard normally.
2. Open Movement Log again to see the latest decision, last position writer and available native APIs. Tap **Stop Capture** or **Export JSON**. Export stops capture and opens the iPad share sheet. Select a local destination.
3. Keep the report private. It can contain exact Earth coordinates. Captures are opt-in, kept in memory for the open dashboard, and limited to the newest 6,000 events. The app never adds these events to Firebase presence. The share sheet's temporary file is removed when the sheet completes.

The `sidera-movement-v1` JSON contains raw location samples and timing, callback grouping, optional source flags, accuracy and speed/course when reported, the active baseline and previous candidate, observed displacement, combined uncertainty, decision, and applied Mars meters. Position changes carry a writer of `coreLocation`, `demoMovement`, `firebaseRestore` or `localNavigation`. The report records mode, route, connection, restore and Earth rebaseline events. A skipped restore has an outcome and no corresponding position change.

## Available motion evidence

The native bridge reports Core Motion and accelerometer availability, compass capability, step counting, pedometer distance support, and pedometer authorization status at runtime. It does not start a pedometer query. Apple lists gyro, accelerometer and digital compass on both models, with built-in GPS/GNSS listed on the cellular variants. The Phase 5A iPads produced relative attitude at approximately 10 Hz. The prior short device exports contained no usable speed or course. Raw acceleration and relative attitude can indicate that the iPad is being handled. Neither provides validated walking distance. Compass capability provides a possible device orientation reference and cannot corroborate translation. The source flags can identify software-simulated or accessory-derived fixes when available. They cannot establish Wi-Fi as the provider or prove that separately delivered fixes are independent. [iPad Pro technical specifications](https://support.apple.com/en-us/111979) · [iPad Air technical specifications](https://support.apple.com/en-us/111905) · [Core Location source information](https://developer.apple.com/documentation/corelocation/cllocationsourceinformation) · [Core Motion step counting availability](https://developer.apple.com/documentation/coremotion/cmpedometer/isstepcountingavailable%28%29) · [Core Motion user acceleration](https://developer.apple.com/documentation/coremotion/cmdevicemotion/useracceleration)

## Physical procedure

The signed Phase 5D release containing the existing Jezero Firebase configuration installed and launched on both target iPads. The 202 m replay, mode switch, restoration, reconnection, and diagnostic export have automated coverage.

In the stationary spot check, both astronaut markers stayed at Habitat Base and displayed **Position Uncertain** in screenshots taken about 85 seconds apart. Each Movement Log showed an Earth baseline with no further fix or position-change event observable during the check. This verifies that the markers held across the observed interval. It does not measure rejection of ongoing physical location drift. Both devices reported Core Motion, accelerometer, compass, step counting, and pedometer distance as available. Pedometer collection and measured walking were outside this check.

Use the same route and conditions on both iPads. Record tape-measured or independently surveyed distance separately from the greatest reported Earth displacement and the sum of applied Mars steps. Mark the test start and stop times separately. For each trial record accuracy, speed/course availability, uncertainty, the number of accepted steps, and any hold.

| Trial | Procedure | What to check |
| --- | --- | --- |
| Stationary, 60 seconds | Start a fresh capture, enable Live Sensors, rebaseline while the iPad is already still, and leave it on the same spot for 60 seconds after the baseline. Repeat on each device. | Zero applied Mars steps, and a comparable marker on the other iPad if sharing. A false movement is a failed trial even if the UI later says Position Uncertain. |
| 10 m measured walk | Start from a fresh baseline, walk a marked straight 10 m, stop and wait for follow-up fixes. | Record accepted movement or Position Uncertain and the actual comparison to the measured distance. |
| 30 m measured walk | Repeat with an independent 30 m course in the same conditions. | Compare estimate and uncertainty to the measured distance. Check for candidates without usable speed/course. |
| 50–100 m measured walk | Repeat on a measured course with safe access. Keep the device in normal carrying position and repeat in both directions. | Look for progressive accepted steps and check latency and held positions. A single large noisy fix should never move the marker. |
| Demo to Live | Start capture in Demo Movement, navigate to a waypoint and switch to Live Sensors while stationary. | Only Demo Movement changes pose before the switch. The mode and Earth baseline events after the switch retain the current pose. |
| Wi-Fi interruption | With both devices connected, leave one as an observer and turn Wi-Fi off on the other until its marker is offline. Reconnect to the same session. | One marker per astronaut, unchanged positions absent accepted movement, no second restoration, and live relative headings after reconnect. |

A successful software regression replay establishes that the older failure mechanism is blocked by the new guard. A measured physical trial is required to establish walking accuracy on either iPad. For the NASA Space Apps demonstration, use **Demo Movement** for position and show live **relative iPad orientation** and Firebase sharing. Present Live Sensors as an experiment alongside its uncertainty status and local diagnostics.
