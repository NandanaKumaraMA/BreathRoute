# BreatheRoute

A native SwiftUI walking companion for comparing modelled PM2.5 exposure, walking time and distance, recording foreground walks, and keeping private symptom notes.

## Run

1. Open `BreathRoute.xcodeproj`, select **BreathRoute** and an iPhone or iPad simulator, then Run. The deployment target is iOS 17.
2. Complete onboarding. A local guest profile works without signing in.
3. In **Explore**, choose **From** and **To**, then **Compare routes**. Suggestions are biased to the visible area. Nearby rows can also set a destination.
4. Select a route card or its numbered map label to preview it. The selected path is solid and alternatives are dashed purple. **Air samples and route details** opens coverage, samples and route details. **Show air sample areas** controls the optional circles.
5. Tap **Start this walk** to begin foreground recording. Keep the app open. Finish explicitly to save the recorded portion.
6. **Plan a walk** includes air circles and route comparison. Planning automatically requests an avoidance alternative when eligible fresh higher-AQI areas exist. Starting the walk activates foreground geofencing and route-departure checks; entry or sustained departure triggers an inline comparison. The user chooses whether to change paths. Optional notifications/Always access are in Walk preferences. The ellipsis contains departure forecasts and the labelled moving example.

### Provider keys at build time

The development checkout has the supplied OpenWeather and Geoapify keys configured in **`Config.local.xcconfig`**. They are read automatically; users do not need to paste keys into the app.

For another checkout, copy `Config.local.xcconfig.example` to `Config.local.xcconfig`, then set:

- `BREATHE_OPENWEATHER_KEY` for current air data and forecasts.
- `BREATHE_GEOAPIFY_KEY` for walking routes and polygon avoidance.
- `BREATHE_ORS_KEY` only if using the optional openrouteservice fallback.

`AppConfig.xcconfig` includes that ignored local file for Debug and Release, and `AppInfo.plist` passes the values to the app. Never commit or share the populated local file. Bundled client API keys can be extracted from an app binary; use provider restrictions/quotas appropriate to distribution. Geoapify requests use a key header rather than a key in the URL. With no routing key, MapKit is a fallback and walking coverage varies by region.

The Firebase plist remains a separate ignored local configuration. After replacing `BreathRoute/GoogleService-Info.plist`, run `python3 scripts/configure-google-signin.py` and rebuild. This generates the matching callback build setting in `GoogleSignIn.local.xcconfig`. The callback is a public OAuth client identifier; provider API keys remain in ignored local configuration. The Firebase project must have Google enabled in Authentication. Do not put service-account credentials in the app.

## Current source

User-facing copy uses concise Preview/Sample wording rather than developer labels. Saved preview titles and source captions are formatted for display; stored provenance and separation from measured activity remain intact.

- Adaptive Today, Explore, Journal and You screens; tab bar on iPhone and sidebar on iPad.
- MapKit place suggestions and nearby category/radius search, manual or current-location start, street/satellite/hybrid styles and optional 3D terrain.
- Geoapify balanced/short walking routes, duplicate-path suppression, polygon avoidance and returned-geometry intersection checks. Optional ORS and MapKit fallbacks.
- OpenWeather sampled air readings and coverage-aware modelled dose comparisons. Similar estimates are labelled as similar rather than promising a cleaner path.
- Grouped pollution-coloured route sections, optional approximate sample circles, original excluded areas on avoidance routes, and selectable alternatives.
- Hourly departure forecasting, charts, coverage-aware ranking and optional local reminders.
- Foreground GPS recording, jump/gap filtering, recoverable unfinished sessions and local Core Data journals with separate guest/account stores.
- Integrated foreground geofence awareness and automatic remaining-route suggestions, with explicit switching that preserves completed intervals. Simulator examples use the same walk flow; fixture paths remain synthetic.
- Optional iPhone motion activity and read-only HealthKit context; core walking does not require an Apple Watch.
- Google Sign-In through Firebase Authentication, session restoration and separate guest/account journals. Email/password forms remain available only for local Debug emulator tests.
- Optional manual Firestore sync for profile, preferences, walk summaries and symptom notes. Three-way merging preserves conflicting edits as labelled copies; deletion propagation and atomic local acknowledgement support safe retries.
- Owner-only Firestore document rules and structured private collections under `users/{uid}`. Raw GPS, Motion, Health records, provider keys and unfinished walks stay on the original device.
- Separate read-only demo journal with 30 fictional walks and 45 fictional notes, available offline. Loading existing cloud examples is explicit and does not import them into personal totals.
- Device authentication lock, speech summaries, semantic text sizes and Reduce Motion support.
- Free foreground Firestore journal updates with owner-only revision listening, quiet initial snapshots, duplicate/self-sync filtering and an explicit Review/Sync now flow. Optional generic local banners, a local test alert, and expiring Debug-only Simulator push checks require no Apple membership. The separate APNs/FCM connection remains available when Apple credentials are configured; see [notification setup](backend/PUSH_SETUP.md).

## Validation

`swift test` builds production domain and Core Data sources without a simulator. The current suite has **90 passing tests**, covering exposure and forecast calculations, routing decoding, Geoapify authentication/geometry/avoidance/cancellation, location gaps, geofence policy, activity aggregation, checkpoint validation and isolated persistence/failure handling. Core Data cases require macOS.

On 29 October 2026, the restored source passed:

- 75 Swift domain/persistence tests.
- 7 Firestore rules tests (owner access, cross-account denial, invalid data and revision validation).
- 14 native emulator sync checks covering local-only defaults, consent, upload, conflicts, empty-store restore, deletion, offline retry, account isolation and concurrent writers.
- 14 native structured-data checks covering typed collections, separate demo data, repeated seeding and partial projection repair.
- Live Google session restoration and manual sync of the previously authorised synthetic Account QA journal (3 entries).
- 5 read-only live restore checks: actual server records restored into an empty isolated local store; source journal unchanged.

The live restore used a separate local store, not a second-device Google login. No iPad sign-in was initiated. The new Explore layout and build-level provider configuration were preserved.

Build verification uses local simulator signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`). Tests do not establish live sensor delivery, background execution, provider accuracy or all accessibility interactions. Simulator usability checks and provider responses are checked separately.

On 30 October 2026, the integrated walk flow passed Debug/Release simulator builds, 87 domain/persistence tests, 12 isolated native integration checks and 16 movement checks. Native integration covers automatic avoidance, automatic foreground monitoring, entry-triggered comparisons, preserved totals on switching, separate recovery progress, invalid switches and late-response cancellation. Routing and air providers are mocked for these integration checks; they do not establish real background region delivery. A separate live simulator check returned a Geoapify remaining path with fresh OpenWeather coverage and verified inline switching. The test position had no eligible higher-AQI avoidance areas; the original unfinished walk stayed unchanged.

## Movement and health readings in Simulator

Use the map’s **+ / −** buttons to zoom in or out in Explore and the full-screen map. Zoom keeps the current centre, heading and tilt; during follow it stays centred on the walker and retains the chosen zoom on location updates.

Starting or recovering a walk enables camera follow. The map stays centred on the moving walker while reroute suggestions are shown. Panning pauses camera follow; the follow or recenter button restores it immediately, including while a preview is paused.

The Simulator does not walk automatically or measure a person's pulse. In **Explore → More walking tools → Preview a walk**, a labelled example starts moving immediately. Alternatively, compare a real provider route and tap **Preview walk**. That reuses its path and air samples while labelling movement/body metrics as synthetic. On a physical iPhone, **Start this walk** continues to use real GPS and optional Core Motion instead.

If an unfinished walk is present, **Preview this saved route** opens the same path in a separate in-memory preview; closing it preserves the original checkpoint and does not save a new trip.

Preview pace, speed, distance and example steps update as the marker advances. Provider-route previews request a fresh OpenWeather reading for the simulated position; **Refresh live air data** retries it. Exposure combines provider concentration with simulated time, and air-data coverage keeps missing intervals explicit. Bundled example routes keep their air readings synthetic. Fictional heart/breathing values are explicitly marked as examples, never inserted into HealthKit. **Pause/Resume** preserves progress; backgrounding pauses playback. **Follow the walker** starts on to keep the marker centred; turn it off to browse the map. Ending a preview saves a labelled demo, excluded from actual-walk totals.

**You → Health & motion sensors** and actual-walk activity show explicit availability for Apple Health records. Use **Refresh** for today's available HealthKit steps/distance and **Read Apple Health records** for recent heart/breathing snapshots. Missing data remains **Unavailable**. Permission does not generate sensor data, and an iPhone alone does not measure heart or breathing rate. Real readings still depend on a compatible source and permission.

Seven domain tests cover path advancement, exact arrival, pause/resume, recovered progress, invalid inputs, repeated vertices, date-line interpolation and GPS pace fallback. The Debug `--walking-preview-qa` workflow additionally checks movement/metrics, background pause and synthetic-data isolation using an in-memory journal, including successful and failed air requests through a mock provider; it does not query or write HealthKit. The final build passed 16 native checks, and a live OpenWeather response was separately verified on the saved-route preview.

## Cloud sync and local verification

In **You**, open account options and continue with Google. Signing in does not upload a journal. Choose **Set up cloud sync**, review what is shared, enable it, then tap **Sync now**. Sync preferences are separate for each account/device. Guest records are not automatically copied into an account. The current development QA account and backend were verified with synthetic data.

Readable Firestore collections are nested under `users/{uid}`: `preferences/current`, `walks/{uuid}` and `symptoms/{uuid}`. `journal/current` is the canonical conflict-safe snapshot. A root-level `users` collection is expected. The app creates child documents during the first approved sync; there is no SQL schema to import.

`backend/firestore.rules` and `backend/firestore.schema.json` describe the private data contract. To run rules tests, use Java 21+, Node 24 and `pnpm install --frozen-lockfile` in `backend`, then `pnpm test:rules`. Tests use the `demo-breatheroute` emulator project, never production.

For native emulator checks, start Auth/Firestore using `backend/firebase.json`, then launch a dedicated Debug simulator with `--firebase-auth-emulator --journal-sync-qa` or `--firebase-auth-emulator --structured-cloud-qa`. Reports are written as `cloud-journal-qa.json` and `structured-cloud-qa.json` in that simulator app's Documents directory. These workflows use synthetic accounts and data. Structured QA is disabled for production. The live restore flag is reserved for the previously authorised synthetic QA account and performs read-only server restoration into an isolated in-memory store.

## Architecture and limitations

`Domain` holds value models/calculations; `Services` holds state, providers, permissions and persistence; `Views` holds SwiftUI composition. The Swift package tests selected production sources directly.

Estimated dose is PM2.5 concentration (µg/m³) × assumed ventilation (Easy/Brisk/Fast: 15/25/35 L/min) × time. These illustrative assumptions are not personalised physiological measurements. Coverage means usable sampled time, not street-level accuracy. Nearest-sample line colours and 250 m circles do not represent measured pollution boundaries. Nearby places are distance-ranked matches, not medically safe recommendations. Similar nearby routes may receive identical provider readings.

Recording is foreground-only. Closed-app intervals are unobserved; recovery preserves the last saved checkpoint. Health and motion values depend on available permissions and records. Remote-notification client/backend code is implemented; live deployment and APNs/FCM delivery still require the Apple/Firebase setup in the push guide. Physical sensor/geofence delivery has not been established by simulator testing. Notify.lk is excluded. Google Sign-In and Firestore sync are restored in this checkout; see [the Firestore schema](backend/SCHEMA.md) for paths, limits and consistency rules.

## Coursework

The student stated that their lecturer approved AI-assisted implementation under updated rules. Describe the assistance accurately in the submission and follow the applicable lecturer guidance.

## Provider references

- [Apple MapKit](https://developer.apple.com/documentation/mapkit)
- [Geoapify Routing](https://apidocs.geoapify.com/docs/routing/)
- [OpenStreetMap copyright](https://www.openstreetmap.org/copyright)
- [OpenWeather Air Pollution](https://openweathermap.org/api/air-pollution)
- [Firebase Authentication](https://firebase.google.com/docs/auth/ios/start)
