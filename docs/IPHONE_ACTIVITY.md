# iPhone activity without an Apple Watch

Implemented on 8 October 2026. A Watch is optional. Location/geofencing use Core Location; motion uses the iPhone's Core Motion APIs; HealthKit reads the device's accessible Health records. Native sensor behaviour still needs a supported physical iPhone.

## Where to find it

- **You → iPhone motion → Track steps during walks** enables the optional preference. Motion & Fitness permission is requested when a real walk starts, rather than on app launch. The preference can also be changed in the active-walk movement panel.
- **Explore → active walk → Movement, from your iPhone** displays reported session steps, a separate pedometer distance estimate, walking/stationary/other/unclassified time, and fresh available cadence/active pace.
- **Journal → saved walk → Recorded phone activity** restores the summary alongside GPS and exposure metrics. Earlier walks remain readable and show that no activity summary was saved.
- **You → Today in Apple Health → Read today's activity** requests read-only step and walking/running-distance access. A returned snapshot also appears in Today. Each snapshot states its date and query end time; a previous-day snapshot is labelled for refresh.
- **You → Optional health records → Read recent health records** separately requests heart/respiratory records from the past hour. Source, record time and manually-entered metadata are shown. These are stored records, not live physiological measurements.
- **Preview motion metrics** is available in You and during demo walks. Its synthetic replay runs in local view state and never starts sensors, reads/writes Health, saves a trip or changes an open walk.

## Recording rules

`CMPedometer` returns cumulative steps/distance for each monitoring window. Each foreground window starts at its own start time. The app retains previous-window totals without adding repeated cumulative callbacks twice. Stopped-window callbacks, backdated updates, decreasing step counts, negative counts and invalid distances cannot inflate the aggregate.

`CMMotionActivityManager` supplies activity context. Low-confidence or contradictory walking/stationary flags stay unknown. Automotive/stationary overlaps are classified as other motion, not stationary walking. The initial state and every unmonitored period remain unclassified. Classification time begins at the callback receipt; the app does not backdate certainty to before monitoring started.

Motion is opt-in and foreground-only in this version. Backgrounding or disabling monitoring closes the window and clears current cadence/pace. Resuming starts a new window; the gap is not filled with fabricated steps. Current cadence and active pace are unavailable after 30 seconds without a fresh pedometer update. Cadence is converted from steps/second to steps/minute; pace from seconds/metre to minutes/kilometre.

At finish, the last reported sensor totals and classified/unclassified durations are encoded in the trip's optional activity field. There is no final historical sensor backfill; callback delays and foreground-window boundaries may undercount steps. Route switching does not start a new motion session or reset completed totals. A failed trip save keeps the current recording open; sensor shutdown follows a successful save.

Activity summaries are also included in the active-walk checkpoint. Explicit relaunch recovery retains reported totals and classified durations; closed-app time is added to unclassified time. Resumed pedometer monitoring adds a new window to restored totals without requesting a historical backfill. A sudden termination can lose activity after the last successful checkpoint, normally updated every 15 seconds in the foreground. Demo starts and shutdowns do not invoke sensor stop APIs unless the matching sensor was actually started.

GPS distance and pedometer distance are separate metrics and are never added together. Daily Health totals are separate from trip counts. Stationary time does not become zero pollution exposure, and motion does not change the assumed ventilation or measured physiological data. Heart/respiratory records do not drive the dose model.

## Health data and permissions

- Read-only HealthKit queries; the app does not write steps, workouts or synthetic samples into Health.
- Today's totals use a cumulative statistics query with samples starting within the current local calendar day, ending at request time. HealthKit supplies the aggregate; the app does not independently add overlapping device/app samples. Midnight-spanning or later-synced records can make these snapshots differ from the Health app's own display.
- Missing/unreadable totals remain nil and display **Unavailable**, rather than an invented zero. HealthKit does not disclose whether a missing result reflects denied read access or an empty store.
- Today snapshots and vital records stay in memory on this device. Core Data saves only the phone-motion summary with the walk. No motion or Health data is sent to the air/routing providers or a cloud service.
- Unsupported sensors, denied/restricted access, waiting updates and failures have distinct motion states. With no sensor access, GPS, route planning, exposure assumptions and the journal remain available.
- `NSMotionUsageDescription` and the updated `NSHealthShareUsageDescription` are configured for Debug and Release. The existing HealthKit entitlement is used with read-only authorization requests in this workflow.

## Verification

The iOS Simulator build compiles. With the 9 October forecast addition, the current Swift Testing suite has **42 test functions**: 38 domain functions plus four Core Data integration functions. Tests cover confidence/overlapping flags, foreground/background unknown time, window aggregation without duplicated counts, invalid values, Codable activity round trips, restored motion totals and closed-app gaps, GPS checkpoint rules, forecast timing/coverage/ranking, legacy trip decoding, isolated SQLite reopen, atomic completion retry and preservation after encoding failures. These are production calculation/storage sources.

The clean iPhone 17e simulator verifies the settings, synthetic replay, preference persistence and recovery after declining Health access. The later isolated recovery check verifies the active-demo movement panel, labelled no-actual-motion state, session resume and saved demo summary. Resetting Motion & Fitness permission on that QA device and starting another demo produces no sensor permission prompt. Actual sensor readings remain unverified. See `UI_VERIFICATION.md` for the exact scope of evidence.

Physical-device checks remain required: actual steps/cadence/pace, both Core Motion permissions, permission changes during a walk, phone placement, delayed callbacks, classification transitions, switching and save-failure lifecycle. Real Health activity and source-tagged vital records need a consenting test device with genuine readable records. Synthetic previews and simulator checks do not prove those behaviours.

## Official references

- [Core Motion pedometer](https://developer.apple.com/documentation/coremotion/cmpedometer)
- [Pedometer units and available fields](https://developer.apple.com/documentation/coremotion/cmpedometerdata)
- [Motion activity flags and confidence](https://developer.apple.com/documentation/coremotion/cmmotionactivity)
- [Activity delivery and suspension](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager/startactivityupdates(to:withhandler:))
- [HealthKit statistics and aggregation](https://developer.apple.com/documentation/healthkit/hkstatistics)
- [iPhone Health activity without a Watch](https://support.apple.com/guide/iphone/intro-to-health-data-iphbb8259c61/ios)
