# Phase 5F walking detection feasibility

**Walking Detection Lab** is available under **Jezero → Movement Log → Walking Detection Lab**. It runs independently of the Live Sensors selector. The Lab measures only device motion. The existing navigation and presence controllers receive no Lab results.

## Collection and processing

The Lab reuses the Runner's foreground `CMMotionManager` subscription in the `xArbitraryZVertical` frame. It requests 50 Hz while a capture is active and returns to the dashboard's 10 Hz request on stop. Dashboard heading remains downsampled during the capture. The Lab drains a separate native buffer four times per second. Dart sends the batches to an analysis isolate for filtering, step detection and JSON encoding. `Stop Capture` drains the final samples. Closing the Lab stops the session and discards its in-memory data. App inactivity ends an active capture and preserves a report for review on return. Collection is capped at 90 seconds and the retained trace can hold up to 5,400 rows. Core Motion and monotonic sample timestamps determine the observed frequency. [Apple Core Motion](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data) · [Apple update interval documentation](https://developer.apple.com/documentation/coremotion/cmmotionmanager/devicemotionupdateinterval)

Phase 5A measured about 10 Hz from each iPad at the existing 10 Hz request. Phase 5E found that both iPads exposed fused motion and gyro but returned code 109 for CMPedometer. These observations inform the initial choice of a fused, timestamped signal and a higher experimental request. No prior captures contained the acceleration needed to tune gait thresholds. [Phase 5A sensor results](sensor_feasibility.md) · [Phase 5E pedometer results](pedometer_validation.md)

The detector projects gravity-compensated acceleration onto the upward axis using the normalized negative gravity vector. The projection keeps the same meaning when the iPad tilts. It subtracts a 0.6 Hz exponential baseline and smooths the result at 4 Hz. The filter weights use the actual interval between samples. It retains the magnitude of user acceleration, vertical and horizontal energy, and the rotation-rate magnitude for handling checks. A local peak must reach 0.035 g with at least 0.075 g prominence from its preceding trough. A 0.32-second minimum interval suppresses close double peaks. Confirmation requires four accepted peaks with intervals of 0.32–1.10 seconds and a shortest-to-longest interval ratio of at least 0.68. The initial four are credited once when the pattern qualifies. Later peaks are counted once each while the rhythm remains consistent.

A rotation over 2.2 rad/s or acceleration over 0.65 g breaks the rhythmic sequence and blocks matching for 0.28 seconds. A horizontal-to-vertical energy ratio above 2.25 also breaks the sequence when horizontal energy clears the noise floor. Energy is smoothed over 0.35 seconds. Quiet acceleration below 0.026 g RMS and rotation below 0.16 rad/s RMS support a stationary classification after 0.8 seconds. The detector warms up for 0.45 seconds after a start, reset, or sample gap over 0.10 seconds. A pending or confirmed rhythm expires after 1.45 seconds without a qualifying peak. The displayed confidence is a cadence-consistency heuristic, with partial credit for pending peaks. It is uncalibrated.

The thresholds are experimental. A steady hand bounce can recreate a walking-like vertical waveform. A quick turn, soft footfall or change of grip can obscure real steps. Published phone experiments also identify confusion between handling and steps. Results for phones supply no accuracy estimate for these iPads. The Lab estimates neither stride length nor displacement. [Published inertial step detection study](https://pmc.ncbi.nlm.nih.gov/articles/PMC6165578/)

## Field procedure

1. Use the same helper, pace and landscape grip on both iPads where possible. Open the Lab, choose a scenario and tap **Start Capture**. Begin each action after a short quiet baseline. Hold the iPad steady at the end of action before tapping **Stop Capture**.
2. Run each row as a separate capture. Enter the independently counted steps after stopping, including zero-step controls. Use **Export JSON → Save to Files**. Begin a fresh capture for each repeat. **Reset Counter** is available while recording and creates a replay boundary. The field comparisons below use complete captures without resets.

| Scenario | Action | Manual count |
| --- | --- | --- |
| Stationary on a table | Leave on a stable surface for 30 s | 0 |
| Held stationary in both hands | Stand still and hold for 30 s | 0 |
| Walking straight | Walk 30 steps with a natural pace and a two-handed grip | 30 |
| Rotating while standing still | Turn or tilt the iPad repeatedly with feet planted | 0 |
| Moving the iPad by hand without walking | Move it forward/back and up/down, including a brief steady rhythm | 0 |
| Brief shake while standing still | Give it a brief controlled shake with feet planted | 0 |
| Sitting down or standing up | Change posture while holding the iPad | 0 |
| Turning while walking | Walk 30 steps with one 90° turn in the middle | 30 |

3. Repeat the straight, turning, and handling controls at least three times per device. Record the manual count, confirmed steps, observed Hz, confidence, and any native drops, gaps or interruptions. For a zero-step control, every confirmed step is a false positive. For a walk, total overcount and undercount give lower bounds. Use independent step timestamps if measuring per-step false positives and misses, since the two may cancel in the totals.
4. Review collection reliability separately from detection. Compare repeated runs at the same pace and grip. Preserve Demo Movement while accuracy and the handling controls are unresolved.

## Local report and replay

The export is named `sidera-walking-report-….json` and uses the existing iPad share sheet. It contains no location, identity, authentication token or Firebase configuration. Raw traces stay local unless the operator shares them.

- `schema`, `detectorVersion`, `scenario`, `scenarioLabel`, `actualSteps`, UTC start/end and monotonic boundaries identify the capture. The manual count is metadata.
- `summary.device` describes the hardware family, iPadOS version and runtime capabilities. `summary` separates measured frequency, native buffer overflow, rejected input rows, sampling gaps, confidence, cadence and the end reason. `summary.observedHz` is intervals divided by elapsed sample time across the retained capture, so interruptions can reduce it. `summary.nativeDropped` counts known queue overflows. A gap can represent lost, delayed or absent samples.
- `columns` defines each `trace` row. The first 16 fields are monotonic seconds since boot, acceleration and gravity vectors in g, rotation rates in rad/s, quaternion x/y/z/w, interval seconds, and the UIKit interface-orientation value. The last field contains the filtered vertical value in g. A rejected row's filtered field is null.
- `events` contains candidate, confirmation and rejection decisions, measured gap lengths, classification changes and resets with monotonic timestamps. Confirmations include cadence and confidence. `boundaries` specifies the exact trace index and clock for resets and stop. Native interruption or error information stays in the summary. Decision times can follow the original peak times.
- `thresholds` identifies the settings used by the recorded detector version. A complete retained raw trace can be analyzed using the same code as the Lab. The command prints the recorded and replay detector versions, both confirmed counts and whether all decisions match. It exits with a nonzero status when decisions differ. An updated detector can replay an older report with the same trace schema for comparison.

```sh
dart run tool/replay_walking.dart /path/to/sidera-walking-report.json
```

Automated coverage uses explicitly synthetic acceleration and rotation. It exercises stillness, regular and variable rhythm, duplicate timestamps and close peaks, irregular and horizontal handling, shaking, rotation, gaps, reset and stop boundaries, and deterministic replay. One test deliberately shows that a repeated vertical hand-like signal can match the walking heuristic. Widget coverage verifies the experimental label and unavailable-sensor controls. Native tests exercise bounded row export, monotonic intervals, foreground stop and time limits.

## Field evidence and decision

The signed experimental release installed on both target Wi-Fi iPads. Each opened the Lab and exported a table capture. The two recorded traces reproduced every detector decision on replay.

| Table capture | Duration | Samples | Observed rate | Native drops / gaps | Candidates / confirmed |
| --- | ---: | ---: | ---: | ---: | ---: |
| ARES-01 · iPad Pro | 43.5 s | 2,173 | 49.92 Hz | 0 / 0 | 1 / 0 |
| ARES-02 · iPad Air | 44.6 s | 2,222 | 49.82 Hz | 0 / 0 | 1 / 0 |

Both captures ended in the stationary classification. Each recorded one isolated late peak. The Air rejected it on horizontal energy. The Pro rejected it when the rhythm expired. Overall acceleration RMS was 0.019 g on the Pro and 0.012 g on the Air, including these transients. The operator confirmed these were the stationary trials.

The operator identified the two newer exports as the 40-step trials. The files retained the default table label and blank manual counts. The assessment uses the operator's count and leaves the source reports intact.

| 40-step walking trial | Duration | Samples | Observed rate | Native drops / gaps | Candidates / confirmed | Count shortfall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ARES-01 · iPad Pro | 45.4 s | 2,265 | 49.92 Hz | 0 / 0 | 84 / 4 | 36 |
| ARES-02 · iPad Air | 47.5 s | 2,367 | 49.81 Hz | 0 / 0 | 49 / 0 | 40 |

All four exports reproduced every decision on replay. Sampling was consistent across devices and scenarios. During the walks, horizontal acceleration RMS reached 0.077 g on the Pro and 0.083 g on the Air, against vertical RMS of 0.061 g and 0.055 g. The horizontal-motion veto rejected 39 Pro candidates and 44 Air candidates. The prominence gate rejected another 41 Pro candidates and four Air candidates. The one confirmed Pro bout estimated 79.5 steps/min with heuristic confidence around 95%. The confidence describes that short rhythm and the total still fell 36 steps short. The manual totals alone bound missed counts. Per-step matching and broader handling false-positive rates remain unmeasured.

Keep Demo Movement for navigation. The current detector is unsuitable for step counting on the two measured walks. Further feasibility work can compare periodicity across gravity-aligned axes on repeated walks and matched handling controls. Proceed to a separate stride and direction study only if both iPads distinguish the walking and control scenarios repeatably within a defined miss and false-positive budget. Evaluate individual event timing and agreement between devices as well as totals.
