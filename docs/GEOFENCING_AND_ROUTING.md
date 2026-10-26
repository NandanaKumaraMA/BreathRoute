# Sample-area awareness and walking-route avoidance

Implemented on 8 October 2026. The iOS Simulator build compiles and all 21 domain test functions pass. **Native region entry/background delivery, active-walk switching and live openrouteservice responses have not yet been verified.** No coursework grade is implied.

## Setup

The student has an openrouteservice account. Enter its API key in **You → Walking-route connection → Save routing key on this device**. This uses Keychain; do not place the key in source control or the report. A saved routing key makes new comparisons use the hosted `foot-walking` GeoJSON endpoint. OpenWeather remains the pollution provider. Requests send route coordinates and any avoidance polygons to openrouteservice.

MapKit maps, nearby search and suggestions worked in the simulated central-Colombo area. The tested live MapKit walking request returned “Walking Directions Not Available”. MapKit is still used for available walking directions when an openrouteservice key has not been configured. The new provider's account, local coverage, hosted limits and actual results still need live verification.

## Implemented workflow

The **Geofencing** and **Rerouting** cards now remain visible at the top of **Explore**, including before planning and during example walks. Each opens a dedicated sheet. Before a live walk, the sheet explains setup, shows whether each provider key is saved and links to the connections in You. During a real walk, it exposes the corresponding live controls. The previous screen hid these tools entirely during demo walks.

**Open interactive preview** demonstrates synthetic area entry, a remaining-path comparison and an explicit switch in isolated view state. It uses the production entry gate, exposure calculator, geometry intersection check and recommendation policy. It does not use AppModel, request location or notification permission, enable region registrations, invoke the routing API or save a trip. Example paths are sketches; the synthetic metrics are not live provider results. This preview is UI evidence, not verification of native region delivery or live route switching.

1. Compare walking routes and retain each sampled coordinate, AQI, PM2.5 and provider timestamp. Show illustrative 250 m circles and a textual overall-AQI legend. Missing/stale values are grey.
2. **Find an area-avoidance option** selects at most eight fresh AQI 3–5 samples from the selected route, merging nearby watch candidates. Areas containing either endpoint are omitted because excluding an endpoint can prevent routing entirely.
3. Send closed circumscribed GeoJSON MultiPolygon rings through ORS `options.avoid_polygons`. Validate decoded metric units/coordinate ranges and reject paths whose geometry intersects excluded circles, including segments with endpoints outside the area. A conservative small-area local projection is used; exact provider topology and field accuracy still need validation. Duplicate paths are not added as new alternatives.
4. Start a real walk. Open **Explore → Geofencing → Enable area-entry alerts**. Only eligible fresh route samples become watch areas. Empty/low/stale samples produce an explicit no-watch-area state without requesting notification permission.
5. Foreground GPS evaluates entry with accuracy checks, overlap suppression and a global five-minute cooldown. Starting inside a valid watch area may produce one awareness message. An uncertainty circle must fit inside the area before a GPS-based entry is accepted.
6. Optionally request Always location access for native `CLCircularRegion` monitoring. Never exceed eight app watch areas or the remaining system monitoring capacity. Native events are checked against fresh samples and a recent accurate fix. A failed/delayed/unverifiable event does not create a confident entry message. Foreground awareness remains available.
7. **Explore → Rerouting → Compare remaining walk** requests fresh baseline options to the same destination. If requested and eligible, add a geometry-checked avoidance candidate. If avoidance fails, retain baseline options with an explanation. Display remaining-route geometry as dashed lines and time/dose/coverage in cards.
8. Recommend only when at least two options inside the extra-time budget have complete finite estimates and a difference greater than both 0.1 µg and 1%. Longer duration can outweigh a lower concentration. Unknown/near-equal results do not receive a lower-dose recommendation.
9. The user explicitly chooses **Switch remaining route**. Preserve the original session start, completed GPS distance, recorded path and accumulated exposure intervals; checkpoint the replacement remaining plan and watch areas. Save/finish removes area registrations. Relaunch removes obsolete registrations and offers explicit session recovery; sample-area alerts must be enabled again with usable data rather than silently restoring old registrations.

## Important scope limits

- These are modelled sample areas, not measured pollution boundaries. Overall AQI 3–5 is an app awareness policy, not a personalised medical threshold.
- The 250 m radius is an app configuration. Neighbouring API samples may be identical; no street-level hotspot or medically safe path is claimed.
- Always permission does not guarantee immediate region delivery. Native monitoring can be delayed, disabled or unsupported. Foreground session recovery is implemented; background walk recording remains unfinished.
- Actual walking access, snapping, geometry, alternatives, quota handling and hosted avoidance support need verification with the configured ORS account. The API may return only one route.
- Recorded GPS points and exposure intervals are checkpointed during route switches and saved at finish. Explicit recovery retains completed portions and starts a new GPS leg; it does not reconstruct a closed-app gap. See `WALK_RECORDING_AND_RECOVERY.md`.

## Automated evidence

The same production code used by the app is compiled into the Swift Testing package. New tests check stale/future/invalid/low samples, overlap deduplication, the eight-area limit, accuracy rejection, duplicate entries and cooldown/re-entry; polygon closure/order/radius; crossing segments with outside endpoints; malformed route geometry and invalid durations; and recommendation limits for unknown, equivalent and over-budget estimates. The existing exposure and nearby tests remain included.

## Required device/live checks

- Save the ORS key locally; test the selected Colombo walking journey, alternatives and source attribution.
- With genuine eligible readings or an explicitly isolated test fixture, test entry/exit, starting inside, overlap, cooldown, denied permissions, stale expiry and delayed native callbacks.
- Verify background/suspension and checkpoint recovery on a physical iPhone, including retained GPS legs, motion totals, missing intervals and area-alert re-enablement.
- Exercise no-detour, endpoint-inside, rejected geometry and quota/network errors. Verify switching preserves completed metrics and finish removes every app region.
- Walk through VoiceOver, large text and Reduce Motion controls.

## Official sources

- [Core Location geographic region monitoring](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions)
- [openrouteservice routing options and polygon avoidance](https://giscience.github.io/openrouteservice/api-reference/endpoints/directions/routing-options)
- [ORS requests and GeoJSON response types](https://giscience.github.io/openrouteservice/api-reference/endpoints/directions/requests-and-return-types)
- [Hosted ORS API authentication and playground](https://openrouteservice.org/dev/)
- [OpenWeather Air Pollution API](https://openweathermap.org/api/air-pollution)
