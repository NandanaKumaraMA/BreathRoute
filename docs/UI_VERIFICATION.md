# UI verification on 7 October 2026

## Confirmed

- The redesigned iOS app compiles successfully for the iOS Simulator with Xcode 26.6 and a deployment target of iOS 17.0.
- The app launches and renders on iPhone 17 Pro and iPad Air 11-inch (M4), using the iOS 26.5 runtime.
- Journal → Add a symptom note opens the new check-in sheet. Selecting severity 3 and saving creates an entry.
- Editing that entry with the exact text `UI verification note - synthetic test record.` persists the edited note and displays it in the Journal timeline.
- The saved note remains available after app relaunch. This is a synthetic verification entry, not user health data.
- The labelled demo comparison shows two selectable routes, dose/time/distance and sampled coverage, with a persistent Start button and a speech control.
- Place search and the map controls expose distinct start and destination accessibility labels.
- The iPad has native sidebar navigation. Compact detail widths use stacked compositions rather than squeezing two columns together.
- After correcting navigation-bar visibility on iPad, Hide Sidebar followed by Show Sidebar restores navigation successfully.
- The supplied OpenWeather key saves successfully to the development iPhone simulator's Keychain in a locally signed build. An unsigned simulator build previously rejected the write; local ad-hoc signing resolved it.
- After an app relaunch, a live OpenWeather request at a simulated public central-Colombo coordinate (6.9147, 79.8640) succeeds. The dashboard shows PM2.5 **4.4 µg/m³**, OpenWeather AQI **2/5 (Fair)** and provider time **12:06** on 7 October 2026. These are a response at test time, not a permanent current reading or a measurement of the student's location.
- The app icon is a 1024×1024 opaque PNG generated from the app's native leaf symbol and contour design.
- `git diff --check` reports no whitespace errors.

## Screenshots

- `screenshots/iphone-today-demo.png`: actual iPhone simulator screen, with explicitly labelled illustrative demo air-quality data. It does not show a verified live OpenWeather request.
- `screenshots/iphone-today-live.png`: actual iPhone simulator screen showing the successful live OpenWeather response at the simulated public Colombo location. No key is displayed in the screenshot.
- `screenshots/ipad-explore.png`: actual iPad simulator screen showing the responsive planner and sidebar.

The simulator screenshots are unaltered. They show the visible state at capture time.

## Checks still needed

The following have not been established by the visual review: a full VoiceOver walkthrough; largest accessibility text sizes across every screen; dark-mode contrast; iPad landscape and multitasking; real-device background/biometric/HealthKit behaviour; credential/quota/network failure paths (error handling is implemented but these paths have not yet been exercised); cloud auth/sync; remote push; comprehensive end-to-end regression tests.

The eight existing Swift Testing functions for exposure calculations passed in the initial implementation. This UI pass does not change their calculation source. They do not prove full app correctness or guarantee any coursework grade.
