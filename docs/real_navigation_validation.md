# Phase 6B.3 physical navigation

Opening a smartphone mission starts foreground attitude and step collection. The first stable phone-top direction is assigned to local map north. That is an educational map reference. Hold the phone with the screen tilted up and the top edge pointing along your walk. Optional calibration can align that direction with local map north or the Mars bearing of a selected waypoint. The iPad dashboard retains its existing movement controls.

## iPhone walking check

1. Open **Jezero Crater** as ARES-01 and give Motion & Fitness permission if prompted. Wait for **Exploration active**.
2. Hold the phone facing forward and walk 15–20 normal steps. Keep Jezero open after stopping and give delayed readings a few seconds to arrive.
3. In **Astronaut**, read **Total steps**, **Applied steps**, and **Estimated distance traveled**. Confirm that the marker moved without a destination and that the estimate holds steady after the last native batch arrives.

The phone's mission position and personal stride are restored locally. Live tracking works offline. Start Navigation provides guidance to a selected target, while Return to Base switches the target after the estimated distance from base exceeds 100 m. Arrival ends guidance within 8 m and preserves the estimated position.

## Starting or resuming a shared Jezero expedition

Open Jezero on both provisioned iPhones as ARES-01 and ARES-02. Each iPhone connects automatically to the same Jezero session. [Phone enrollment and Firebase sessions](live_astronaut_tracking.md). Reopening a mission resumes the Mars position saved for that mission and astronaut on the iPhone. A new local exploration starts at the mission's Habitat Base. Firebase shares the current estimates with crew members.

To begin together, have each astronaut choose **Astronaut → Start New Expedition → Start at Habitat Base** while both phones are stationary. The action clears each phone's own route and walking totals and keeps its mission checklist. When both phones publish the shared base coordinates, **Crew** should show **0 m** and the map should show two adjacent astronaut chips. To verify movement, have one astronaut walk while the other phone stays still, then swap roles. Compare the two phones' Crew readouts after each walk.

## Step windows and heading

Core Motion supplies timestamped relative attitude and cumulative pedometer readings. At calibration the app requests a new native window from the attitude's timestamp. It ignores callbacks from the prior window for movement and counts increases in the active window once. A delayed live callback or a same-window query can supply a higher cumulative count. Native distance replaces the stride estimate for the same eligible interval when it falls within 0.25–1.50 m per step. The starting stride estimate is 0.70 m.

A batch uses the last usable attitude at its endpoint. The app retains 45 seconds of heading history and can hold a bearing for up to six seconds through missing samples. Longer heading gaps withhold affected steps. Backgrounding and changes in device orientation establish a fresh reference and counting window. Pausing holds the position and restarts the step window on resume while preserving a usable direction reference. Opening sheets, changing targets, and using the map leave collection running.

The iPhone starts its pedometer without opening an Earth location stream. Firebase shares only the estimated Mars pose, heading, and existing status fields. The cached pose and stride setting stay on the phone. [Apple CMPedometer live updates](https://developer.apple.com/documentation/coremotion/cmpedometer/startupdates%28from%3Awithhandler%3A%29)

## Previous field trial

Phase 6B.2 reported 24 detected iPhone steps and 0.0 m in a 40-step walk. The count confirms the native result reached Dart. The prior code rejected a batch if its increment began before calibration or if it lacked a tightly timestamp-matched heading. The paused state could also withhold late delivery. The original field readout recorded the totals only, so it did not identify which gate withheld those 24 steps.

## Phase 6B.3 iPhone result

The signed DEV build launched on the iPhone 16. In the ARES-01 Jezero out-and-back walk, the Astronaut sheet showed **43 detected steps, 43 applied steps, and 35.6 m of estimated Mars travel**. The saved position was approximately **7 m from Habitat Base** and held steady across two readbacks after stopping. The walk was requested without a destination. The Astronaut screenshot verifies the step and distance totals, and the full-chain widget test verifies translation before selecting a destination or starting guidance.

Flutter analysis was clean. All 83 Flutter tests and all 8 iOS simulator XCTest cases passed. The full-chain test also covers native-format cumulative updates, delayed delivery during an attitude gap, pose publication, and foreground restart without step replay.


## Phase 6E iPhone field check

The signed build was installed and launched on Dan’s iPhone 16 as ARES-01 and Keren’s iPhone 14 Plus as ARES-02. Keren approved development signing on-device. Both entered Endeavour and connected through their operator-enrolled device identities. After a second install and app launch, both connected again and published the catalog Habitat Base at 0.00 m separation.

During Dan’s first walking check in Endeavour, a production read recorded 10.54 m of accepted estimated displacement from Habitat Base on ARES-01 and 0.00 m of change on the stationary ARES-02. Firebase later recorded both slots offline as their foreground Endeavour sessions ended.

The automated checks passed with 100 Flutter tests, 8 iOS XCTest cases, and the Auth and Realtime Database emulator suite. The emulator exercised five independent sessions, token refresh, per-device authorization, and rejection of cross-slot writes. Flutter exercised automatic reconnection, North-Up and Heading-Up, camera gestures, fixed-size markers, and local step-driven movement.
