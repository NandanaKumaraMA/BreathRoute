# New advanced feature proposal

Prepared on 7 October 2026 and updated on 8 October for the 31 October submission. Geofencing, rerouting, forecasts, motion sensing and Live Activities below remain **proposed additions, not lecturer-approved scope**. The current Explore build now implements nearby place discovery, type-ahead suggestions, richer map controls, retained route samples and illustrative sample circles; see `MAP_EXPERIENCE.md`. Existing authentication, persistence, API, accessibility and core walking work still needs completion.

## Recommended flagship: pollution-aware geofencing and rerouting

The student has proposed geofencing, pollution circles and alternative paths. Prioritise these as one integrated workflow: **view pollution samples → compare routes → monitor nearby areas during a walk → offer a fresh comparison after entry → let the user switch**. This remains proposed scope; the current build does not implement pollution-zone geofencing or area-avoidance routing.

### What a circle means

An API sample provides a concentration at a coordinate and a time. It does not establish a circular pollution boundary. Draw a clearly labelled **approximate monitoring area** around a relevant fresh sample, with PM2.5, provider, sample time, radius and a textual legend. The monitoring radius is an app configuration, not a claim about the provider's spatial resolution. Keep nearby identical modelled readings visibly consistent and merge duplicate/overlapping watch areas rather than inventing hotspots.

Pollution concentration and personal exposure are different: colour areas by the selected pollutant's concentration/category, and calculate route dose from concentration × assumed ventilation × interval duration. Do not label a route or a circle medically safe.

### Proposed user journey

1. Request actual walking routes and reuse bounded air-quality samples along each route.
2. Display fresh sample areas, segment colours, missing-data states and comparable route estimates. Include equivalent text so the map does not rely on colour alone.
3. Let the user enable area alerts for an active walk. Register only relevant nearby monitoring conditions and remove stale or obsolete ones. Apple allows at most 20 simultaneous monitoring conditions; keep a smaller working set and rotate it as the walk progresses.
4. On an entry event, check sample freshness and location availability before showing an awareness message. Use a cooldown, overlap deduplication and a foreground GPS fallback. Region monitoring is not an exact, instantaneous boundary detector; do not promise an alert precisely when the user crosses the displayed edge.
5. Offer **Compare from here**. Compare the remaining journey from the current valid location to the same destination, under the user's extra-time limit and consistent modelling assumptions.
6. Recommend an option only when data coverage is comparable and the estimated difference meets a documented policy. Explain why it ranks better. If readings are effectively the same, state that; shorter duration may explain a lower dose even without a cleaner street.
7. Require the user's **Switch route** action. Preserve completed intervals, dose and notes; replace only the remaining plan. Handle a destination inside a monitored area and the absence of any useful alternative explicitly.

### API approach

- **Initial comparison:** keep OpenWeather for point pollution readings and MapKit for available walking alternatives. Confirm real walking-direction coverage in the intended Colombo demonstration area; a working map or place search does not establish route availability.
- **Actual area avoidance:** MapKit's documented request supports available alternatives but does not expose an arbitrary pollution-circle exclusion field. A routing provider such as **openrouteservice** documents GeoJSON `avoid_polygons`. Convert a watch circle into a polygon and evaluate whether the returned walking path avoids it, then sample and score the resulting path too.
- **Provider validation:** verify the configured account, hosted API restrictions, attribution, usable local walking geometry and live requests before committing to an additional provider. An avoidance path is not necessarily lower exposure: its longer duration and other pollution samples still matter.
- **Data quality:** test spatial variation with the existing provider before promising street-level recommendations. OpenWeather's public endpoint documentation does not provide measured pollution-boundary polygons. If the samples cannot distinguish nearby streets, do not display a precise hotspot or a claimed cleaner detour.

### Implementation stages and acceptance

| Stage | Deliverable | Evidence required |
| --- | --- | --- |
| 1 | Persist coordinates, readings and timestamps per planned segment; add sample circles and an accessible legend | Actual API values on the map, with missing/stale/identical readings handled honestly |
| 2 | Comparable remaining-route ranking and an optional detour budget | Tests for ties, missing data, longer-but-higher-dose routes and inaccessible alternatives |
| 3 | Core Location monitoring lifecycle and optional entry awareness | Permission-denied fallback, expiry, overlapping areas, cooldown, monitoring limits and physical-device entry/exit checks |
| 4 | User-controlled rerouting; polygon avoidance if a provider is verified | Live routing evidence, polygon/path intersection tests and preserved completed-trip data |

Priority test cases include starting inside an area, a destination inside an area, delayed events for expired samples, two overlapping areas, background/relaunch recovery, an API error during rerouting, no alternative, and losing location accuracy near a boundary.

This provides a coherent advanced MapKit/Core Location workflow, algorithmic depth and meaningful API integration. Notifications and local persistence support it; they should not be counted as new advanced SDKs solely because they are connected to the feature.

## Other candidate additions

### 1. Departure-time forecast planner

**User question:** “Would this walk have lower estimated exposure if I left later?”

Add a **When to walk** screen: choose a destination and departure window, compare available hourly PM2.5 forecasts, then select a time and route. Show forecast concentration and modelled dose separately, with forecast timestamps, coverage and assumptions. Do not label a time medically safe.

OpenWeather documents hourly air-pollution forecasts for four days. This extends the connected provider rather than introducing another API account. Access with the configured key still needs verification. A route estimate must match each segment's anticipated arrival time to available forecasts; do not reuse the starting hour for an entire long walk.

**Technical work:** forecast decoding, bounded request reuse, temporal matching, route sampling, a testable comparison engine and Swift Charts.

**Acceptance:** no forecast outside the provider horizon; missing intervals reduce coverage; identical or negligible differences show “similar estimates”; only adequately comparable options receive a recommendation. Explain that modelled data may not distinguish nearby streets.

**Tests:** timestamp/time-zone boundaries, missing forecast hours, partial coverage, equal estimates, route duration crossing an hour and request reuse.

### 2. Motion-aware walk recording

**User question:** “How much of this session was actually spent walking?”

Combine Core Motion activity classification and available pedometer steps/cadence with GPS. Show walking time, stationary time and sensor availability separately. Offer a pause suggestion after a sustained stationary period; retain manual controls and permission-denied fallback.

Motion does not establish inhaled air volume. Standing still does not mean zero exposure. Do not automatically erase stationary exposure, transform steps into pollution samples or present sensor estimates as measured physiological dose. GPS and pedometer distances must not be added together.

**Technical work:** Core Motion availability/permission handling, asynchronous updates, confidence handling, GPS/sensor reconciliation and session-state transitions.

**Acceptance:** works without Motion permission; displays unsupported fields as unavailable; ignores low-confidence transitions; distinguishes walking metrics from the exposure interval. Validate on a physical iPhone because simulator replay cannot prove actual sensor behaviour.

**Tests:** missing sensors, low confidence, contradictory states, stationary transitions, permission denial and avoiding duplicated distance.

### 3. Lock Screen walk companion

**User question:** “Can I check my walk without reopening the app?”

Use ActivityKit and a WidgetKit extension to display session time, recorded distance, estimated dose, coverage and the last update time on the Lock Screen and supported Dynamic Island devices. Tapping returns to the active walk. Provide clear paused, stale, incomplete and ended states.

**Dependency:** establish background tracking and session recovery before promising continuously updated walk metrics. A Live Activity cannot collect location or fetch network data itself; the app supplies updates. Adding ActivityKit does not enable background execution on its own.

**Acceptance:** unavailable/disabled Live Activities leave the core walk usable; no duplicated activities after relaunch; finish ends the activity; stale data is visibly identified. Do not publish symptom text or destination details to the Lock Screen by default.

**Tests:** start/update/end lifecycle, recovery, disabled availability, stale content and ending a session after a save failure.

## Supporting and stretch ideas

| Idea | User benefit | Scope and evidence |
| --- | --- | --- |
| Walk replay and data-quality timeline | Scrub through a saved walk and understand where time, dose and missing coverage accumulated | MapKit + Swift Charts + richer local segment records. Distinguish planned, recorded, missing and inferred geometry. Strong supporting feature for the recommended workflow. |
| Explainable route trade-offs | Set a maximum extra walking time and compare estimated exposure, duration and coverage | A testable filtering/ranking algorithm with visible reasons. Use “lower estimated dose among comparable routes”, with equal/missing results handled explicitly. This is algorithmic depth; it is not a new Apple SDK by itself. |
| Private personal-pattern explorer | Compare the user's recorded walks by time of day, duration and pace | On-device descriptive summaries with record counts and comparable coverage. Avoid causal symptom claims, predictions of attacks or unsupported “AI” branding. Defer until enough genuine data and a clear comparison policy exist. |

## Delivery order

1. Complete core account/local-data isolation, verify real routing coverage, and add richer segment storage and session lifecycle.
2. Implement and test the flagship's sample overlays, route comparison and monitoring lifecycle in that order.
3. Add user-controlled rerouting. Use polygon avoidance only after the extra routing provider is verified; otherwise describe the feature accurately as ranking available alternatives.
4. Treat departure-time forecasting as the next extension. Core Motion and a Live Activity remain optional until the main walk and geofencing journey is reliable.
5. Complete device/accessibility verification and report evidence by 27 October. Reserve 28–30 October for submission preparation.

The proposed core demonstration becomes: **inspect sample areas → compare routes with reasons → begin a walk → receive a verified area-entry awareness message → compare and switch the remaining route → inspect the saved coverage**. Forecast planning and a Lock Screen presentation can extend this once reliable.

More features do not guarantee 70%+. This proposal targets relevance, integration depth, testable behaviour and polished complete journeys, while preserving time for the other rubric components and the separate Tutorial 4 requirement.

## Official sources

- [OpenWeather Air Pollution API and hourly forecasts](https://openweathermap.org/api/air-pollution)
- [Core Motion activity classification](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager)
- [Pedometer data and availability](https://developer.apple.com/documentation/coremotion/cmpedometer)
- [ActivityKit](https://developer.apple.com/documentation/activitykit)
- [Live Activity data, lifecycle and update restrictions](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Core Location geographic monitoring and limits](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions)
- [MapKit available alternative routes](https://developer.apple.com/documentation/mapkit/mkdirections/request/requestsalternateroutes)
- [openrouteservice polygon-avoidance options](https://giscience.github.io/openrouteservice/api-reference/endpoints/directions/routing-options)

SDK capabilities were checked against official sources on 7 October 2026. Geofence, avoidance-routing, forecast, motion and Live Activity implementation and runtime verification remain future work.
