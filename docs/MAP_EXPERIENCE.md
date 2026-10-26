# Explore map and nearby discovery

Implemented on 8 October 2026. This is an app enhancement, not evidence that the complete coursework or geofencing workflow is finished.

## User flow

1. Open Explore. If a recent authorised location is available, discover places near it. Otherwise show the explicitly labelled Colombo map preview; choose a start or tap Find places near me.
2. Choose Parks, Cafés, Culture or Essentials. The options menu selects a 1, 3 or 5 km search radius. Returned matches are filtered to that actual radius, deduplicated and ordered by straight-line distance from the search centre.
3. Tap a card or numbered pin for the returned address and available phone/website details. Check air quality at that place's coordinates if desired. Use as my destination connects the place to the existing walking-route comparison.
4. Tap Where to? or the start field. Type to receive native Apple Maps suggestions after a short debounce. Choose a suggestion, submit a complete query, or use the category shortcuts/nearby matches. Manual start selection works without location permission.
5. Switch Streets/Satellite/Hybrid, toggle terrain elevation or air sample circles, recenter and expand the map. Pan away from the search centre and use Search this area to fetch new matches. Camera movement itself does not issue repeated place requests.
6. Compare available walking directions. A pending current-location comparison waits for a new fix automatically, with a bounded wait and manual-start fallback. Selecting another place invalidates an older comparison.
7. Open the always-visible **Geofencing** or **Rerouting** cards above the map. Before a real walk they show setup and a clearly labelled interactive preview; during a real walk they expose area-entry alerts or remaining-route comparison and switching. These entry points remain available during demo walks.

## Data and interaction behaviour

- Native `MKLocalPointsOfInterestRequest` searches categories. Empty, failed or uncategorised POI responses fall back to a natural-language `MKLocalSearch`. Explicit category mismatches are excluded; local indexing and completeness remain provider limitations.
- `MKLocalSearchCompleter` supplies suggestions using the visible region. The region is a relevance hint; a submitted place query may legitimately return results outside the nearby radius.
- Nearby and submitted searches cancel superseded requests. Request tickets prevent old results or errors overwriting newer searches. Search suggestions use separate completers so an older delegate callback cannot replace the current query.
- Nearby discovery refreshes after movement exceeding 500 m, rather than on every GPS update. Each explicitly current-location request requires a recent accurate fix. GPS permission is requested through the user's location action.
- Close pins are hidden at broad zoom levels to avoid overlap; zooming reveals them. Every returned place remains available through the card/list interface.
- Camera transitions respect Reduce Motion. Textual distances, category labels, place lists and an air legend supplement map geometry and colours.
- Place facts and destinations come from Apple Maps. Ratings, opening hours and medical or pollution-safety claims are not invented.

## Pollution display

The selected route retains each sampled coordinate and optional provider reading. A checked nearby place also retains its point reading in the current Explore session. A 250 m circle is an illustrative display radius, not the provider's spatial resolution or a measured pollution boundary. Colours represent OpenWeather's **overall AQI (1–5)**, not a PM2.5-only scale. Missing/stale readings are grey, and point details show PM2.5, AQI, timestamp and source. Nearby points may share identical modelled values.

Place air checks are explicit to avoid silently spending quota on every pin. The app continues to estimate route dose separately using concentration × assumed ventilation × time and sampled coverage.

## Remaining work

Geofence registration/entry awareness, compare-from-here, remaining-route switching and openrouteservice polygon requests were subsequently added on 8 October; see `GEOFENCING_AND_ROUTING.md` for their verification limits. Saved GPS paths and explicit checkpoint recovery are implemented. Departure forecasting was added on 9 October; see `DEPARTURE_FORECASTS.md`. Background recording and Firebase accounts/sync remain unfinished. MapKit returned “Walking Directions Not Available” for the tested central-Colombo journey; live openrouteservice coverage still needs a confirmed saved key on the test device. Physical-device location, accessibility and lifecycle verification are still needed.

New saved walks retain the actual GPS path separately from the last planned path. Journal detail draws recorded legs in blue and the plan as a grey dashed line. Unobserved gaps break the recorded line; replay advances the saved fixes with their original timestamps and accuracy rather than inventing movement. Demo walks retain only synthetic planned geometry. See `WALK_RECORDING_AND_RECOVERY.md`.

## Official references

- [MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)
- [Search suggestions with MKLocalSearchCompleter](https://developer.apple.com/documentation/mapkit/mklocalsearchcompleter)
- [MKLocalSearch request](https://developer.apple.com/documentation/mapkit/mklocalsearch/request)
- [OpenWeather Air Pollution API](https://openweathermap.org/api/air-pollution)
# Route selection and pollution inspection — 8 October 2026

Tapping a route card or a numbered route label opens **Route & air quality**. The separate **Pollution coverage & alternative paths** button below the Explore map opens the same view. Selection now reveals a fitted comparison map instead of merely changing a checkmark below the map.

The selected path is solid green with a white outline; available alternatives are dashed purple. The details map shows numbered PM2.5 sample points inside 250 m illustrative circles, and a matching list with AQI, provider/sample time and missing/stale states. Route chips and alternative cards change the selected path and its sample areas before a walk starts. An open walk uses the existing Rerouting controls for remaining-path changes.

Coverage is calculated from the retained sample time fractions and currently usable readings. It describes estimated trip time with data, not the percentage of land measured. Missing/stale points remain unknown and do not become zero dose. Alternative cards show time, distance, coverage and estimated/partial dose; a single returned path has an explicit no-alternative explanation. The avoidance request is available in live-route details; its failures remain visible there while the existing paths remain available.

The labelled demo previously had no route air points, so its map could not draw any pollution circles. It now contains two synthetic samples per path: Park-side 12/16 µg/m³ and Town Hall 18/28 µg/m³. Their equal time weights retain the earlier 2.7/3.8 µg example-dose comparison. These values do not establish live pollution, geofence delivery or a real routing response.
