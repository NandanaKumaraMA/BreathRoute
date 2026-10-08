# Explore map and nearby discovery

Implemented on 8 October 2026. This is an app enhancement, not evidence that the complete coursework or geofencing workflow is finished.

## User flow

1. Open Explore. If a recent authorised location is available, discover places near it. Otherwise show the explicitly labelled Colombo map preview; choose a start or tap Find places near me.
2. Choose Parks, Cafés, Culture or Essentials. The options menu selects a 1, 3 or 5 km search radius. Returned matches are filtered to that actual radius, deduplicated and ordered by straight-line distance from the search centre.
3. Tap a card or numbered pin for the returned address and available phone/website details. Check air quality at that place's coordinates if desired. Use as my destination connects the place to the existing walking-route comparison.
4. Tap Where to? or the start field. Type to receive native Apple Maps suggestions after a short debounce. Choose a suggestion, submit a complete query, or use the category shortcuts/nearby matches. Manual start selection works without location permission.
5. Switch Streets/Satellite/Hybrid, toggle terrain elevation or air sample circles, recenter and expand the map. Pan away from the search centre and use Search this area to fetch new matches. Camera movement itself does not issue repeated place requests.
6. Compare available walking directions. A pending current-location comparison waits for a new fix automatically, with a bounded wait and manual-start fallback. Selecting another place invalidates an older comparison.

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

Geofence registration/entry awareness, compare-from-here, remaining-route switching and openrouteservice polygon requests were subsequently added on 8 October; see `GEOFENCING_AND_ROUTING.md` for their verification limits. Background session recovery, forecast planning and Firebase accounts/sync remain unfinished. MapKit returned “Walking Directions Not Available” for the tested central-Colombo journey; live openrouteservice coverage still needs the configured account key. Physical-device location, accessibility and lifecycle verification are still needed.

## Official references

- [MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui)
- [Search suggestions with MKLocalSearchCompleter](https://developer.apple.com/documentation/mapkit/mklocalsearchcompleter)
- [MKLocalSearch request](https://developer.apple.com/documentation/mapkit/mklocalsearch/request)
- [OpenWeather Air Pollution API](https://openweathermap.org/api/air-pollution)
