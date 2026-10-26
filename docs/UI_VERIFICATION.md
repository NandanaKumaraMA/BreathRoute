# UI verification on 7–16 October 2026

## Authentication checks on 16 October

- Firebase SDK integration and account screens compile in Debug and Release for iOS Simulator. All **45** Swift Testing functions pass, including account validation/namespace and isolated guest/two-account store tests. A separate local emulator script verifies two distinct registrations, sign-in identity, wrong-password rejection and a reset request.
- A new isolated **BreatheRoute Account QA** device verifies normal launch without a Firebase file: local features remain usable, and You shows the missing-configuration notice. The student reconfirmed that a real project has not been created.
- In explicitly labelled local Auth-emulator mode, a guest synthetic note remains separate from Alice's empty account journal. Alice saves a different synthetic note; app termination/relaunch restores her session and only her note. Sign-out returns the original guest note. Bob's journal shows neither record.
- Native reset submission reaches the local emulator and shows the generic inbox message. No real email delivery or completed password change is claimed. Native registration submission remains unverified; the backend registration check uses the emulator API.
- `screenshots/iphone-account-setup.png` and `screenshots/iphone-account-emulator.png` are unaltered native evidence of these distinct states. Apple's test-password save prompt was declined.
- The user's simulator interaction interrupted the final unfinished-walk guard check. Real-project verification, guard/expiry/error transitions, verification/reset inbox delivery, accessibility and cloud sync remain outstanding. See `AUTHENTICATION.md`.

## Departure forecast checks on 9 October

- The forecast update builds for iOS Simulator; all **42** test functions pass, including seven new production forecast-calculation/decoder tests.
- Today exposes **When to walk**. Without a route, its screen explains the dependency and offers Explore or a labelled example. The example shows synthetic forecasts, a native chart, matching departure/arrival/dose/coverage rows and selectable options. Synthetic reminder scheduling is disabled.
- iPhone 17 Pro's existing OpenWeather Keychain connection successfully loads real hourly forecasts for both public Colombo example points. The route geometry and 13-minute travel time remain clearly illustrative. No key is inspected or printed.
- The next twelve-hour provider comparison has 100% forecast-time coverage and similar estimates. A changed 72-hour start / 24-hour window uses the same fetched data, ranks 23 complete options and excludes two beyond the returned 13 October 14:30 endpoint. Selecting an unavailable option disables the reminder.
- The native live chart renders with readable shortened hour ticks. `screenshots/iphone-forecast-live.png` captures the provider/similar-estimates/chart state; it does not prove actual walking access, forecast accuracy or a medically safe departure.
- Custom date/time controls and generic local departure-reminder scheduling/cancellation compile. The Mac locked before their final runtime checks and before missing-key UI verification. Reminder permissions/delivery/relaunch, custom date selection, stale/partial network UI, real route integration, VoiceOver, largest text and iPad remain acceptance checks.

See `DEPARTURE_FORECASTS.md` for the model, cache limits, data privacy and exact evidence.

## Walk recovery checks on 8 October

- The saved-path/recovery update compiles for iOS Simulator. All **35** Swift Testing functions pass: 31 domain functions and four isolated Core Data integration functions. Tests cover GPS gaps, invalid fixes, motion restoration, checkpoint validation and atomic/failure-safe completion.
- A new isolated iPhone 17e simulator, **BreatheRoute Recovery QA**, starts a labelled demo with no routing/air credentials and zero actual GPS or motion readings. Its recovery checkpoint was saved, the app terminated and then relaunched with the same store.
- The native recovery card shows the original demo, last-save time, 0 m and 0 GPS fixes, with Resume, Save recorded portion and confirmed Discard controls. `screenshots/iphone-walk-recovery.png` captures that state.
- **Resume saved walk** retains the original session start and displays the recovered-demo explanation. **Finish & save walk** creates one demo journal entry. After another relaunch, no unfinished recovery prompt remains and the entry is still present.
- Saved detail exposes the recovery/gap explanation, 15 L/min ventilation assumption, zero actual fixes, synthetic planned-route metadata and no actual phone activity. The planned-path map compiles and its A/B annotations appear in native accessibility; a full visible replay of a real GPS trace has not been established by this demo.
- A demo initially triggered an unexpected Motion & Fitness prompt. Sensor shutdown now calls stop APIs only when those sensors were started. Resetting Motion & Fitness permission on the isolated QA device and starting a new demo opens the active-walk movement panel without a permission prompt; it clearly states **Demo · no actual motion recorded**.
- The final update was installed on **iPhone 17 Pro** after Explore showed no recording walk. The app relaunched normally and the OpenWeather connection remained configured; its data and Keychain were not reset. The student's routing-key-save reply was checked against native status on iPhone 17 Pro and Motion QA. Both still showed **Add routes and area-avoidance support**; a device/setup clarification is pending. No live ORS success is claimed and no key was printed.
- Physical GPS traces, real recovered motion totals, storage-failure UI, native area delivery, live remaining-route switching, VoiceOver and largest text sizes remain acceptance checks. These demo/runtime and production storage tests are separate evidence.

See `WALK_RECORDING_AND_RECOVERY.md` for recording, checkpoint and privacy rules.

## Route pollution-details checks on 8 October

- The update compiles for iOS Simulator, and all **29** calculation/storage test functions still pass. The final build is installed on the development iPhone 17 Pro simulator after confirming it had no recording walk open. Saved data and Keychain contents were not reset.
- On the isolated **BreatheRoute Motion QA** simulator, tapping the Town Hall route card opens **Route & air quality**. The native Apple basemap renders, with the selected path in solid green, the alternative in dashed purple, A/B markers and amber/red numbered sample circles.
- Selecting **Route 1 · 13 min** updates the title to Park-side walk, the circles/readings to its green 12/16 µg/m³ samples and the alternative comparison to Town Hall. The comparison labels 13 min / 0.92 km / 2.7 µg versus 11 min / 0.82 km / 3.8 µg. All these values are explicitly synthetic.
- The coverage card shows **100% sampled trip time**, **2/2 recent air points**, walking distance and estimated dose. The sample list exposes PM2.5, AQI and synthetic sample date/time through native accessibility. This does not establish a full VoiceOver walkthrough.
- The coverage launcher also opens successfully during an active demo. Route changes are disabled in that recording state and the view directs remaining-path changes to Rerouting. The open QA walk was preserved after it appeared during verification.
- `screenshots/iphone-route-pollution.png` is an unaltered screenshot of the Town Hall details, showing the alternative card and numbered PM2.5/AQI values. The screenshot is from the QA simulator, not a live API route. The map overlays were reviewed in the native computer-control screenshot separately.
- Actual live alternative generation, provider-specific one-route responses and rendered missing/stale samples still need API/device verification. Existing domain tests cover missing exposure and route decoding; synthetic UI does not prove routing-provider behaviour.

## iPhone activity checks on 8 October

- The Core Motion and read-only HealthKit additions build successfully for iOS Simulator. All **29** Swift Testing functions pass, including the new motion rules and two native Core Data persistence tests using isolated stores. No actual user Health records are used by those tests.
- On a clean iPhone 17e simulator named **BreatheRoute Motion QA**, You shows **iPhone motion**, its optional tracking toggle, **Preview motion metrics**, **Today in Apple Health** and separate optional vital-record controls.
- Sensor availability is correctly reported as unavailable on this simulator. No Watch dependency or fabricated sensor readings are shown.
- The isolated motion preview initially shows step count/distance as unavailable. **Run activity example** displays explicitly synthetic **42 steps / 29 m**, **0:30 walking / 0:20 stationary / 0:10 unclassified**. It neither saves a trip nor changes the app's actual motion summary.
- **Read today's activity** opens the native Health Access screen for **Steps** and **Walking + Running Distance**, with no write-data categories. Selecting **Don't Allow** and dismissing the native notice returns to a usable app with **Activity could not be read. Check Health access and try again.**, without manufactured totals.
- The optional **Track steps during walks** preference changes and remains enabled after a test-app relaunch. This does not establish real sensor authorization or actual tracking on hardware.
- The final build also compiles the explicit vital-query time label and waiting state for a nil activity callback. Actual source-tagged vital records and a positive Health statistics response have not been verified.
- The Mac locked while beginning the active-demo movement-panel check. That remaining UI check and largest-text-size visual review were not completed in this pass. Physical iPhone steps/cadence, permission transitions, motion-session lifecycle and saved live-walk summaries still need runtime/device verification.
- The original development simulator's open walk and the earlier feature-preview simulator were not terminated or replaced during these checks.

See `IPHONE_ACTIVITY.md` for the implemented workflow, units, privacy boundaries and device acceptance checks.

## Explore enhancement checks on 8 October

- A further visibility fix adds **Geofencing** and **Rerouting** cards above the Explore map. Both render with complete readable labels on an isolated iPhone 17 simulator named **BreatheRoute Feature Preview**, using iOS 26.5. The original development iPhone 17 Pro's open demo session was not terminated or replaced during this verification.
- Opening Geofencing shows provider key status, monitoring radius, eligible AQI and cooldown, along with setup and preview actions. The new simulator has no copied provider credentials.
- Rerouting opens its dedicated remaining-route setup sheet, including the extra-time budget. **Configure data connections** dismisses the sheet and opens **You** successfully.
- Loading an example comparison and starting an isolated demo session retains both tool buttons. Geofencing opens successfully in that active demo and displays **Example walk is open** rather than hiding the feature. No demo trip was saved during this check.
- **Open interactive preview → Simulate entering an area → Compare example routes → Switch to example detour** completes successfully. The displayed synthetic comparison is 18 min / 9.5 µg versus 30 min / 8.1 µg, with the detour recommended inside a separate 20-minute preview budget. Its sketched geometry avoids the next example circle. The switched state displays synthetic completed metrics of 3 min / 120 m / 1.6 µg. This isolated preview does not establish live route-switch preservation, native geofence delivery or a real ORS response.
- The synthetic map circles and path overlays render in the preview. Apple basemap tiles and nearby search did not load during this separate simulator check; this pass does not establish live map connectivity on that device. Earlier live Apple Maps results below refer to the development simulator.
- The updated Explore map and native type-ahead suggestions compile and launch on the development iPhone simulator.
- At the simulated public Colombo coordinate, Parks and Cafés return live Apple Maps matches. The café list shows Cafe Latte at 162 m and CafeNova at 231 m from the search centre; these are test-time straight-line distances, not user-location measurements or route distances.
- Typing `Vihara` produces Apple Maps suggestions including Vihara Mahadevi Park, its Buddha statue and nearby streets. Selecting the park suggestion resolves it and updates the destination field.
- Selecting Cafe Latte opens its address/detail sheet. **Check air quality here** returns a live OpenWeather response: PM2.5 **0.8 µg/m³**, overall AQI **1/5**, provider sample **10:19 on 8 October**. **Use as my destination** updates the route planner and shows the sample legend. These are response values at test time, not permanent current data.
- A MapKit walking request to that place returns **Walking Directions Not Available**. Nearby search alone does not establish walking-routing support. The subsequently added openrouteservice connection needs a local routing key and live verification.
- The installed app exposes **You → Walking-route connection**, a secure key field and a Save routing key on this device action. No routing key has been inspected or printed by the verification tools.
- Builds containing native geofence registration, polygon requests and remaining-route switching compile. **Their runtime/native/physical-device behaviour has not yet been established.**
- All **21** Swift Testing domain functions pass, covering exposure, nearby ranking, watch-area policy/entry/cooldown, polygon crossing, route decoding and recommendation constraints.

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

- `screenshots/iphone-forecast-live.png`: real provider forecast chart for a clearly illustrative public Colombo path, with no preferred time claimed for the similar next-twelve-hour estimates.
- `screenshots/iphone-walk-recovery.png`: unaltered recovery card for an interrupted labelled demo; no actual GPS fixes or live sensor data.
- `screenshots/iphone-motion-preview.png`: unaltered iPhone 17e screen with explicitly labelled synthetic activity and an unmonitored example gap.
- `screenshots/iphone-activity-settings.png`: unaltered test-device screen showing unavailable motion hardware, the enabled optional preference and the Health access failure state after declining permission.
- `screenshots/iphone-today-demo.png`: actual iPhone simulator screen, with explicitly labelled illustrative demo air-quality data. It does not show a verified live OpenWeather request.
- `screenshots/iphone-today-live.png`: actual iPhone simulator screen showing the successful live OpenWeather response at the simulated public Colombo location. No key is displayed in the screenshot.
- `screenshots/ipad-explore.png`: actual iPad simulator screen showing the responsive planner and sidebar.

The simulator screenshots are unaltered. They show the visible state at capture time.

## Checks still needed

The following have not been established by the visual review: a full VoiceOver walkthrough; largest accessibility text sizes across every screen; dark-mode contrast; iPad landscape and multitasking; real-device background/biometric/HealthKit behaviour; credential/quota/network failure paths (error handling is implemented but these paths have not yet been exercised); cloud auth/sync; remote push; comprehensive end-to-end regression tests.

The eight existing Swift Testing functions for exposure calculations passed in the initial implementation. This UI pass does not change their calculation source. They do not prove full app correctness or guarantee any coursework grade.
