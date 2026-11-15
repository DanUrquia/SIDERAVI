# Phase 5E pedometer validation and map markers

The Phase 5D Air field trial reported almost identical Core Location fixes over approximately 30 hand-counted steps. Wi-Fi positioning can return a useful area estimate while supplying little evidence about a short walk. The original Movement Log did not capture step measurements. The availability flags on both iPads only showed that iPadOS exposes the relevant APIs. [Phase 5D field notes](live_movement_validation.md)

## Measurement-only build

**Live Sensors** starts one foreground CMPedometer stream when step counting is supported. **Movement Log** shows motion authorization, step and distance availability, detected steps, estimated distance, latest sample age, cadence when reported, and the native error domain and code if collection fails. Before a measurement arrives, the totals are unavailable. A reported zero remains visible as zero. The activity line describes increases in reported steps. The readout flags measurements older than eight seconds as stale.

**Start Capture** starts a fresh counting window when Live Sensors is active. After capture starts in Demo Movement, entering Live Sensors starts the window. Switching to Demo Movement, leaving the dashboard, and backgrounding the app stop the stream. Resuming Live Sensors opens a new native window. The app discards callbacks from stopped windows and computes increments from increasing sample-end timestamps. A cumulative counter decrease establishes a new baseline. Missing distance stays unavailable until Core Motion reports it. **Stop Capture** freezes the recorded totals while Live Sensors remains selected. **Rebaseline** continues to reset the existing Earth location guard and keeps the current Mars pose. A Wi-Fi or Firebase reconnect does not restart the pedometer. If a capture ends with no live counts, the app can query only its latest authorized foreground counting window. The resulting retrospective total is labeled separately from streaming activity. It is never added to a live total. [CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer) · [CMPedometerData](https://developer.apple.com/documentation/coremotion/cmpedometerdata)

**Export JSON** includes cumulative and incremental pedometer readings, sample times, diagnostic decisions, authorization, the relative screen-top angle when available, and calibration events. Pedometer events are local and show zero applied Mars distance in this build. Firebase shares the simulated pose through the existing controller.

## Physical check on each iPad

1. Open Jezero, then choose **Live Sensors → Movement Log**. You can also activate Live Sensors directly from the log. Grant motion access if prompted. Confirm the app reports its actual authorization and device capability.
2. Put the iPad down at a marked point, tap **Start Capture**, and keep it on the same spot for 60 seconds. Note any detected steps. An unavailable or stale sample supplies limited evidence about stationary behavior.
3. Tap **Stop Capture** and then **Start Capture** to isolate a walk. Carry the iPad in both hands and take 30 steps along a marked straight line at a natural pace. Count the steps separately and measure the course length independently. Stop at the mark and wait for the final callback, which may arrive after the walk ends.
4. Compare the capture's steps and distance with the actual count and measured length. Record sample age, authorization, reported cadence if available, and any errors. Repeat the walk in both directions on each iPad. A usable input requires repeatable nonzero results during the measured walks and a quiet stationary control. An unavailable distance, a large discrepancy, or ongoing count while still calls for further measurement.
5. Stop and use **Export JSON** if needed. Captures may contain Earth coordinates. Keep raw reports private.

The first exported run on each physical iPad had been recorded in Demo Movement. Both exports listed hardware support, but contained no pedometer samples and reported no motion authorization decision. These captures did not exercise CMPedometer collection.

In the first Live Sensors trial, both exports showed motion authorization granted. The Air (iPadOS 27.0.1) captured 59.5 seconds and the Pro (iPadOS 26.7.3) captured 59.6 seconds. Each returned `CMErrorDomain` code 109 (`CMErrorNotAvailable`) and supplied no live pedometer samples. Both recorded ten Earth fixes and no applied movement.

The follow-up Live Sensors trial exercised the capture-window query on both iPads. The Air captured 50.9 seconds and the Pro captured 48.9 seconds. The live stream and the bounded query both returned code 109 on each device. Both reported step counting and distance support and authorized motion access. The captured step count and distance were unavailable. Core Location reported nine fixes on the Air and eight on the Pro. The guard classified every fix as uncertain and applied 0 m on Mars.

Walking-driven movement requires usable physical measurements. The diagnostic build leaves pedometer data out of pose updates while that evidence is pending. The existing Core Location guard still evaluates location-derived moves. Demo Movement remains available.

## Direction and simulated distance

The dashboard **Calibrate** button makes the iPad's screen-top direction correspond to map-up at that moment. For a direction trial, point that edge along the intended marked line before calibrating, hold the iPad in the chosen carrying position, and compare the arrow after a quarter turn. Relative orientation describes the iPad's pointing direction. Walking direction must be corroborated by the test setup or an explicit operator alignment. Compass and Earth geographic heading use a separate reference from simulated Mars map-up.

A future validated hybrid trial can use trusted incremental distance and an explicitly estimated walking bearing. With a clockwise angle from map-up, east is distance times sine of that angle and north is distance times cosine. The existing Mars sphere conversion takes east/north meters at 1:1 scale and wraps longitude. Pedometer samples currently supply evidence only. Absolute compass headings, acceleration integration, or counting a single delayed callback as repeated motion supply no walking-distance estimate for this app.

Once measurements support a trial, use 10 m, 30 steps, and 30 m courses with measured lengths, a measured quarter turn followed by another walk, a stationary stop, and a remote observer in the same session. Record actual travel and simulated displacement separately on both iPads.

## Fixed-size Mars map markers

Mars Trek tiles, the terrain boundary, and route paths use the existing map transform. Each point marker has a map-space center that still follows that transform. Its glyph, stroke, label and hit target use the inverse camera scale around that center, preserving their screen dimensions and keeping marker gestures inside the interactive map. The local and remote astronaut glyphs retain their existing relative-heading animation. Nearby peers separate by a small screen-space offset with a line to their common or nearby anchor. ARES IDs, **You**, and offline status retain their text scale. The same treatment covers the base, landmarks, destination, and pings so the nearby map symbols keep a consistent visual hierarchy.

On each iPad, compare the marker at reset, intermediate and maximum zoom using the same viewport. Pinch around a point off center and pan to check anchoring. Select a teammate at high zoom, rotate a device to check arrow updates, enable Follow Astronaut to check recentering, and reset again. Small simulated moves should spread farther apart on screen at higher zoom. Use paired Firebase sign-in to check the remote marker.

The physical check compared the local astronaut at 1× and 4× on both iPads. The Air's scale bar changed from about 2.4 km to 590 m and the Pro's from about 1.7 km to 430 m. The local marker ring measured 83–84 pixels in both axes at both zoom levels on each iPad. The arrow and astronaut label remained visually the same size. Both devices were offline during this comparison. The automated dashboard test also measures the remote arrow and its tap target across zoom levels.
