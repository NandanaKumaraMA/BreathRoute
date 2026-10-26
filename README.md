# BreatheRoute

A native iOS walking companion for comparing modelled PM2.5 exposure alongside walking time and distance, recording walks, and keeping symptom notes.

## Run the app

1. Open `BreathRoute.xcodeproj` in Xcode. Select the BreathRoute scheme and an iPhone or iPad simulator, then Run.
2. Complete the two-step introduction. You can start without an account.
3. Explore → See an example comparison opens explicitly labelled demo routes. Demo sessions record no actual movement or dose.
   The **Geofencing** and **Rerouting** cards above the map are always available. Their **Open interactive preview** action demonstrates synthetic entry, comparison and switching without changing your walk or saving a trip.
4. For live air-quality requests, add your OpenWeather key in You → Air-quality connection. Keys are stored in Keychain, not in source control. The supplied key has been configured on the development iPhone simulator and a real response verified; each new device needs its own configuration.
5. For route search, select a start and destination in Explore. Manual start selection works without location permission. MapKit may not return walking routes everywhere.
   For ORS walking routes and polygon avoidance, save a routing key in **You → Walking-route connection**. During a real walk, open **Explore → Geofencing** for area-entry controls or **Explore → Rerouting** to compare and switch the remaining path. Live ORS responses and native region delivery still need verification.
6. To run on a physical iPhone, select your signing team in Xcode and ensure the HealthKit capability is provisioned. Location, Face ID/passcode, notifications and real HealthKit samples require appropriate device settings.

The deployment target is iOS 17.0. Development/build verification used Xcode 26.6 and an iOS 26.5 simulator.

Simulator testing must use a locally signed build. Setting `CODE_SIGNING_ALLOWED=NO` prevented Keychain writes in this environment. Normal Xcode Run uses local simulator signing; the verified command-line build used `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`. Physical-device signing still requires your Apple development team.

## Current implementation

- Two-step onboarding and local profile preferences.
- Firebase account forms, SDK session restoration and separate guest/account journals; local emulator verification is complete for sign-in/restoration/sign-out/isolation. Real project configuration remains required.
- Redesigned Today, Explore, Journal and You screens with a shared adaptive design system.
- Native tab navigation on iPhone and a sidebar on iPad; wider dashboard and planner layouts on iPad.
- MapKit type-ahead search suggestions, category shortcuts and nearby place recommendations ranked by straight-line distance within a checked 1/3/5 km radius.
- Current-location, chosen-start and map-area discovery; tappable place pins, details and destination selection.
- Street, satellite and hybrid maps, terrain elevation, full-screen exploration, recentering and search-after-panning controls.
- Available alternative walking directions, selectable route overlays and labelled pollution sample circles.
- Optional openrouteservice walking routes and polygon avoidance, with returned-geometry checks and clear provider attribution.
- Active-walk area awareness with Core Location regions (Always access) and foreground checks, bounded to eight fresh AQI 3–5 sample areas, overlap suppression and a five-minute alert cooldown.
- Compare-from-here and explicit remaining-route switching, preserving completed recorded intervals; recommendations apply an extra-time budget and complete-data policy.
- Always-visible geofencing/rerouting entry points, connection setup and an isolated interactive feature preview using clearly labelled synthetic data.
- OpenWeather Air Pollution API client, coordinate sampling and time-weighted dose estimates.
- **When to walk** departure-time planning: hourly OpenWeather forecasts, a Swift Charts comparison, coverage-aware ranking, relative/custom departure windows and an optional local reminder.
- Clearly labelled demo routes; missing/stale pollution samples reduce coverage.
- Foreground GPS walk recording with inaccurate jumps and tracking gaps excluded.
- Saved GPS paths with gap-aware map lines, a fix replay control and the last planned path for comparison.
- Recoverable unfinished walks: resume, save the recorded portion or explicitly discard after relaunch; finishing saves the trip and removes its checkpoint together.
- Core Data local trip and symptom persistence; create/edit/delete notes and linked trips.
- Journal filters, walk details, recorded-exposure chart and shareable summaries.
- Optional iPhone Core Motion steps, fresh available cadence/pace and walking/stationary context during monitored foreground portions, saved in each real walk's activity summary.
- Read-only HealthKit daily steps/walking distance, plus optional recent source/time-labelled heart/respiratory records, on-device only. No Apple Watch is required for the core walk.
- An isolated synthetic motion preview available in You and during demo walks.
- Device authentication lock and Keychain API-key storage.
- Spoken route summaries, system text sizes, accessibility labels and Reduce Motion-aware button effects.
- Configurable daily local check-in notification.
- Swift Testing for production domain rules and isolated Core Data persistence.

This is a development build, not a completed coursework submission. See `docs/COURSEWORK_PLAN.md` for remaining requirements. Firebase Authentication is integrated and locally tested, but the student has not yet created the real project/configuration. Firestore sync is not implemented. Follow `docs/FIREBASE_SETUP.md` and see `docs/AUTHENTICATION.md` for the precise verification scope.

## Architecture

- `Domain`: units, exposure calculation and value models.
- `Services`: application state, Core Data, location/permissions, HealthKit, speech, reminders, air-quality requests and routing.
- `Views`: screen composition and shared design components.
- `Tests/BreatheRouteCoreTests`: Swift Testing of the production domain calculations and motion policies.
- `Tests/BreatheRoutePersistenceTests`: native Core Data reopen, compatibility and save-failure tests with isolated stores.

The UI is SwiftUI with Observation. The small local repository uses a programmatic Core Data model and versioned Codable payloads. This is suitable for the initial build; typed entities, migrations, injected services and cloud sync are further work.

## Tests

Run `swift test`. The package builds production domain and Core Data storage sources without requiring a simulator. **45 test functions** cover exposure, nearby ranking, geofence policy/geometry, routing, motion confidence and monitored intervals, non-duplicated step aggregation, GPS gap handling, checkpoint validation, hourly forecast integration/arrival timing/horizon/coverage/ranking, account validation/namespaces, legacy compatibility, isolated account/store reopening and atomic/failure-safe completion. Some tests are parameterised. Core Data integration tests require macOS. The separate local Auth-emulator check is described in `docs/AUTHENTICATION.md`.

These tests establish the listed calculation/storage cases, not live sensors, provider results, permission delivery, accessibility or full UI correctness. Those need the checks in the coursework plan. See `docs/IPHONE_ACTIVITY.md` for the new activity workflow and its verification limits.

## Estimate limitations

Dose is PM2.5 concentration in µg/m³ × assumed ventilation in m³/min × time in minutes. Current Easy/Brisk/Fast assumptions are 15/25/35 L/min. These are illustrative, unvalidated assumptions. Heart rate and respiratory rate are displayed as context and do not currently change the estimate.

Coverage describes usable sampled time, not measured street-level accuracy. Nearby routes can have identical modelled pollution values. The app does not claim a route is medically safe, that pollution caused a symptom, or that it detects emergencies.

**Today or Explore → When to walk** opens departure planning. Choose a real route or the clearly labelled example path. The example initially uses synthetic forecasts; **Load live forecasts for this example path** explicitly requests provider data for its public coordinates. That forecast request was verified on 9 October, separately from real walking-route access. Forecasts do not become current air readings or recorded exposure. See `docs/DEPARTURE_FORECASTS.md` for assumptions and evidence.

Tracking is currently foreground-only. Relaunch offers explicit recovery from the last checkpoint; closed-app intervals remain unobserved. Checkpoints are written at accepted GPS fixes, session changes and every 15 seconds while the foreground timer runs. A sudden termination can lose activity since the last successful checkpoint. See `docs/WALK_RECORDING_AND_RECOVERY.md` for recording and recovery rules. Real cloud account verification, cloud backup/sync, remote push, segment-level pollution colouring, background tracking and further advanced integrations remain unfinished.

Nearby recommendations mean the closest returned matches for the chosen category, not a pollution or medical safety ranking. The 250 m circles illustrate sample locations; they are not measured pollution boundaries. Optional active-walk awareness registers eligible high-category samples separately. See `docs/MAP_EXPERIENCE.md` and `docs/GEOFENCING_AND_ROUTING.md` for setup, implementation and outstanding live/device verification.

## Coursework and AI assistance

The supplied assessment document contains a prohibition on AI-generated executable code. On 7 October 2026, the student stated that their lecturer had approved AI-assisted implementation under updated rules. Confirm the applicable written guidance and describe the assistance accurately in the final report. Do not use the proposal's original declaration that all implementation code was written unaided if it no longer reflects the development process.

## References

- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/
- MapKit: https://developer.apple.com/documentation/mapkit
- Core Location: https://developer.apple.com/documentation/corelocation
- HealthKit: https://developer.apple.com/documentation/healthkit
- Swift Testing: https://developer.apple.com/documentation/testing
- OpenWeather Air Pollution API: https://openweathermap.org/api/air-pollution
- Firebase Authentication: https://firebase.google.com/docs/auth/ios/start
