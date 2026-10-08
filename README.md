# BreatheRoute

A native iOS walking companion for comparing modelled PM2.5 exposure alongside walking time and distance, recording walks, and keeping symptom notes.

## Run the app

1. Open `BreathRoute.xcodeproj` in Xcode. Select the BreathRoute scheme and an iPhone or iPad simulator, then Run.
2. Complete the two-step introduction. You can start without an account.
3. Explore → See an example comparison opens explicitly labelled demo routes. Demo sessions record no actual movement or dose.
4. For live air-quality requests, add your OpenWeather key in You → Air-quality connection. Keys are stored in Keychain, not in source control. The supplied key has been configured on the development iPhone simulator and a real response verified; each new device needs its own configuration.
5. For route search, select a start and destination in Explore. Manual start selection works without location permission. MapKit may not return walking routes everywhere.
6. To run on a physical iPhone, select your signing team in Xcode and ensure the HealthKit capability is provisioned. Location, Face ID/passcode, notifications and real HealthKit samples require appropriate device settings.

The deployment target is iOS 17.0. Development/build verification used Xcode 26.6 and an iOS 26.5 simulator.

Simulator testing must use a locally signed build. Setting `CODE_SIGNING_ALLOWED=NO` prevented Keychain writes in this environment. Normal Xcode Run uses local simulator signing; the verified command-line build used `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`. Physical-device signing still requires your Apple development team.

## Current implementation

- Two-step onboarding and local profile preferences.
- Redesigned Today, Explore, Journal and You screens with a shared adaptive design system.
- Native tab navigation on iPhone and a sidebar on iPad; wider dashboard and planner layouts on iPad.
- MapKit type-ahead search suggestions, category shortcuts and nearby place recommendations ranked by straight-line distance within a checked 1/3/5 km radius.
- Current-location, chosen-start and map-area discovery; tappable place pins, details and destination selection.
- Street, satellite and hybrid maps, terrain elevation, full-screen exploration, recentering and search-after-panning controls.
- Available alternative walking directions, selectable route overlays and labelled pollution sample circles.
- OpenWeather Air Pollution API client, coordinate sampling and time-weighted dose estimates.
- Clearly labelled demo routes; missing/stale pollution samples reduce coverage.
- Foreground GPS walk recording with inaccurate jumps and tracking gaps excluded.
- Core Data local trip and symptom persistence; create/edit/delete notes and linked trips.
- Journal filters, walk details, recorded-exposure chart and shareable summaries.
- Optional recent HealthKit heart/respiratory context, on-device only.
- Device authentication lock and Keychain API-key storage.
- Spoken route summaries, system text sizes, accessibility labels and Reduce Motion-aware button effects.
- Configurable daily local check-in notification.
- Swift Testing for the production exposure calculation and nearby distance/ranking logic.

This is a development build, not a completed coursework submission. See `docs/COURSEWORK_PLAN.md` for the remaining proposal and marking requirements. Firebase has not yet been created or integrated; follow `docs/FIREBASE_SETUP.md` for the next setup step.

## Architecture

- `Domain`: units, exposure calculation and value models.
- `Services`: application state, Core Data, location/permissions, HealthKit, speech, reminders, air-quality requests and routing.
- `Views`: screen composition and shared design components.
- `Tests/BreatheRouteCoreTests`: Swift Testing tests of the same exposure calculation compiled into the app.

The UI is SwiftUI with Observation. The small local repository uses a programmatic Core Data model and versioned Codable payloads. This is suitable for the initial build; typed entities, migrations, injected services and cloud sync are further work.

## Tests

Run `swift test`. The package builds the app's production calculation and distance/ranking logic without requiring a simulator. Twelve test functions cover known units, missing data, zero measurements, weighted coverage, invalid samples, invalid ventilation, invalid duration, additive segments, distance units, radius enforcement, invalid coordinates and deterministic deduplication. Some tests are parameterised.

Core tests passing does not establish persistence, network, permission, accessibility or full UI correctness. Those need the checks in the coursework plan.

## Estimate limitations

Dose is PM2.5 concentration in µg/m³ × assumed ventilation in m³/min × time in minutes. Current Easy/Brisk/Fast assumptions are 15/25/35 L/min. These are illustrative, unvalidated assumptions. Heart rate and respiratory rate are displayed as context and do not currently change the estimate.

Coverage describes usable sampled time, not measured street-level accuracy. Nearby routes can have identical modelled pollution values. The app does not claim a route is medically safe, that pollution caused a symptom, or that it detects emergencies.

Tracking is currently foreground-only and active sessions are not restored after process termination. Cloud accounts, cloud backup/sync, remote push, segment-level pollution colouring, background tracking and further advanced integrations remain unfinished.

Nearby recommendations mean the closest returned matches for the chosen category, not a pollution or medical safety ranking. The 250 m circles illustrate sample locations; they are not measured pollution boundaries or enabled geofences. Geofence entry alerts and pollution-area avoidance routing remain future work. See `docs/MAP_EXPERIENCE.md`.

## Coursework and AI assistance

The supplied assessment document contains a prohibition on AI-generated executable code. On 7 October 2026, the student stated that their lecturer had approved AI-assisted implementation under updated rules. Confirm the applicable written guidance and describe the assistance accurately in the final report. Do not use the proposal's original declaration that all implementation code was written unaided if it no longer reflects the development process.

## References

- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/
- MapKit: https://developer.apple.com/documentation/mapkit
- Core Location: https://developer.apple.com/documentation/corelocation
- HealthKit: https://developer.apple.com/documentation/healthkit
- Swift Testing: https://developer.apple.com/documentation/testing
- OpenWeather Air Pollution API: https://openweathermap.org/api/air-pollution
- Firebase Auth setup (for the next integration): https://firebase.google.com/docs/auth/ios/start
