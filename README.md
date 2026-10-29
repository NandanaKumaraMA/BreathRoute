# BreatheRoute

A native SwiftUI walking companion for comparing modelled PM2.5 exposure, walking time and distance, recording foreground walks, and keeping private symptom notes.

## Run

1. Open `BreathRoute.xcodeproj`, select **BreathRoute** and an iPhone or iPad simulator, then Run. The deployment target is iOS 17.
2. Complete onboarding. A local guest profile works without signing in.
3. In **Explore**, choose **From** and **To**, then **Compare routes**. Suggestions are biased to the visible area. Nearby rows can also set a destination.
4. Select a route card or its numbered map label to preview it. The selected path is solid and alternatives are dashed purple. **Air samples & alternative paths** opens coverage, samples and route details. **Show air sample areas** controls the optional circles.
5. Tap **Start this walk** to begin foreground recording. Keep the app open. Finish explicitly to save the recorded portion.
6. **More walking tools** (the ellipsis) contains departure forecasts, geofencing, rerouting and a clearly labelled example. Example sessions contain synthetic data.

### Provider keys at build time

The development checkout has the supplied OpenWeather and Geoapify keys configured in **`Config.local.xcconfig`**. They are read automatically; users do not need to paste keys into the app.

For another checkout, copy `Config.local.xcconfig.example` to `Config.local.xcconfig`, then set:

- `BREATHE_OPENWEATHER_KEY` for current air data and forecasts.
- `BREATHE_GEOAPIFY_KEY` for walking routes and polygon avoidance.
- `BREATHE_ORS_KEY` only if using the optional openrouteservice fallback.

`AppConfig.xcconfig` includes that ignored local file for Debug and Release, and `AppInfo.plist` passes the values to the app. Never commit or share the populated local file. Bundled client API keys can be extracted from an app binary; use provider restrictions/quotas appropriate to distribution. Geoapify requests use a key header rather than a key in the URL. With no routing key, MapKit is a fallback and walking coverage varies by region.

The Firebase plist, if used, remains a separate ignored local configuration. Do not put service-account credentials or Notify.lk secrets in the app.

## Current source

- Adaptive Today, Explore, Journal and You screens; tab bar on iPhone and sidebar on iPad.
- MapKit place suggestions and nearby category/radius search, manual or current-location start, street/satellite/hybrid styles and optional 3D terrain.
- Geoapify balanced/short walking routes, duplicate-path suppression, polygon avoidance and returned-geometry intersection checks. Optional ORS and MapKit fallbacks.
- OpenWeather sampled air readings and coverage-aware modelled dose comparisons. Similar estimates are labelled as similar rather than promising a cleaner path.
- Grouped pollution-coloured route sections, optional approximate sample circles, original excluded areas on avoidance routes, and selectable alternatives.
- Hourly departure forecasting, charts, coverage-aware ranking and optional local reminders.
- Foreground GPS recording, jump/gap filtering, recoverable unfinished sessions and local Core Data journals with separate guest/account stores.
- Geofence awareness and explicit remaining-route comparisons/switching, with isolated synthetic feature previews.
- Optional iPhone motion activity and read-only HealthKit context; core walking does not require an Apple Watch.
- Firebase email/password account UI, device authentication lock, speech summaries, semantic text sizes and Reduce Motion support in the current checkout.

## Validation

`swift test` builds production domain and Core Data sources without a simulator. The current suite has **58 passing tests**, covering exposure and forecast calculations, routing decoding, Geoapify authentication/geometry/avoidance/cancellation, location gaps, geofence policy, activity aggregation, checkpoint validation and isolated persistence/failure handling. Core Data cases require macOS.

Build verification uses local simulator signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`). Tests do not establish live sensor delivery, background execution, provider accuracy or all accessibility interactions. Simulator usability checks and provider responses are checked separately.

## Architecture and limitations

`Domain` holds value models/calculations; `Services` holds state, providers, permissions and persistence; `Views` holds SwiftUI composition. The Swift package tests selected production sources directly.

Estimated dose is PM2.5 concentration (µg/m³) × assumed ventilation (Easy/Brisk/Fast: 15/25/35 L/min) × time. These illustrative assumptions are not personalised physiological measurements. Coverage means usable sampled time, not street-level accuracy. Nearest-sample line colours and 250 m circles do not represent measured pollution boundaries. Nearby places are distance-ranked matches, not medically safe recommendations. Similar nearby routes may receive identical provider readings.

Recording is foreground-only. Closed-app intervals are unobserved; recovery preserves the last saved checkpoint. Health and motion values depend on available permissions and records. Live APNs delivery and physical sensor/geofence delivery have not been established by simulator testing. Notify.lk is excluded. Do not assume cloud sync or Google sign-in availability from earlier builds: the current checkout links FirebaseAuth/FirebaseCore only.

## Coursework

The student stated that their lecturer approved AI-assisted implementation under updated rules. Describe the assistance accurately in the submission and follow the applicable lecturer guidance.

## Provider references

- [Apple MapKit](https://developer.apple.com/documentation/mapkit)
- [Geoapify Routing](https://apidocs.geoapify.com/docs/routing/)
- [OpenStreetMap copyright](https://www.openstreetmap.org/copyright)
- [OpenWeather Air Pollution](https://openweathermap.org/api/air-pollution)
- [Firebase Authentication](https://firebase.google.com/docs/auth/ios/start)
