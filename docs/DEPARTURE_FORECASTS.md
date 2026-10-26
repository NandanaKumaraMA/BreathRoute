# Departure-time forecasts — 9 October 2026

The student selected departure forecasting as the next advanced feature. **When to walk** is now available in Today, Explore and pre-walk route details. It extends the existing route/pollution workflow with temporal modelling, bounded provider requests and Swift Charts.

## Workflow

1. Select a walking path, then open **When to walk**. If no path is selected, open Explore or choose the clearly labelled example path. An unfinished recording must be resolved first.
2. Load OpenWeather forecasts for the retained route sample coordinates. A real-route screen does not automatically spend API quota on opening. Example paths initially use synthetic data; an explicit **Load live forecasts for this example path** action fetches real provider forecasts for those public coordinates while preserving the illustrative path warning.
3. Compare hourly departures across 6, 12 or 24 hours. Start now, in 24/48/72 hours, or choose a custom date/time. Display times use the device time zone; calculation uses absolute Date timestamps. Relative windows advance each minute. A custom first departure stays fixed, and passed options are removed.
4. Read the chart and matching textual list: departure/arrival, estimated dose in µg, mean PM2.5 in µg/m³ over covered time, and forecast-time coverage. Green bars are complete; grey bars are partial. Unavailable options have no bar and remain unknown, not zero.
5. Compare only fully covered options. At least two are needed. When their range is no greater than the larger of 0.1 µg or 1%, show similar estimates. Otherwise identify the lowest estimate **among fully covered options shown**, with a difference from the first departure when that baseline is complete. This threshold is an app policy, not an established health threshold.
6. Select a fully covered future provider-data option to schedule one optional local reminder. Synthetic/unknown/partial/current options cannot schedule it. The notification uses generic text and asks the user to review current conditions; it does not reveal the destination or symptoms, start a recording, track forecast changes or automatically reschedule. Its identifier is separate from the daily check-in. The chosen reminder time remains on this device and a cancel control is provided.

## Calculation and API boundaries

- Use the same route geometry, duration and labelled ventilation assumption across departures. A uniform-speed approximation maps retained spatial sample weights to consecutive travel-time intervals.
- For each spatial interval, integrate linearly interpolated PM2.5 between adjacent returned hourly forecast timestamps over the corresponding anticipated arrival times. Do not apply only the departure-hour concentration to a long walk.
- Exclude missing/invalid values, conflicting duplicate timestamps, gaps greater than one hour, overflow, expired data and time before the first or after the last returned forecast point. Do not extrapolate or fill missing forecasts with zero.
- Coverage is covered estimated trip time divided by total estimated trip time. Incomplete options are excluded from ranking. Mean concentration is over covered time only; estimated dose additionally uses ventilation and duration.
- The endpoint is HTTPS `/data/2.5/air_pollution/forecast`. OpenWeather documents hourly forecasts for four days, but the actual returned first/last timestamps determine usable coverage.
- Make no more than eight point requests per load. Successful identical point requests within a load are deduplicated. An app-memory cache reuses points for ten minutes, retains at most 64 entries and is cleared when the saved credential changes. Explicit refresh bypasses old cache entries. Changing the departure window performs no new network requests.
- A 30-minute freshness limit is an app policy. Expired results remain timestamped but contribute no coverage until refreshed. Authentication/quota errors stop the load. Other point failures remain unknown; a wholly failed load shows an error. Cancellation/dismissal prevents an old load updating the screen.
- Provider forecasts do not replace current air readings, actual GPS exposure intervals or saved journal data. No forecast is described as a measured future condition, personalised health prediction or guarantee of a safe time.

## Verified evidence

The final simulator build succeeds. All **42 Swift Testing functions** pass, including seven new forecast functions covering exact interval integration, anticipated route-point arrival times, missing hours/points, no extrapolation, freshness/invalid weights/overflow, genuine zero readings, decoding/duplicates and coverage-aware ranking.

On the isolated Recovery QA simulator, Today → When to walk → Preview with an example path opens labelled synthetic forecasts, a chart and matching values. Departure selection updates its checkmark, and synthetic reminders are disabled. No sensor or location permission is requested by that flow.

On iPhone 17 Pro, the existing Keychain connection loaded real forecasts for the two public Colombo sample points on the illustrative Park-side path. At about 16:02 on 9 October, the returned horizon was 9 October 15:30 through 13 October 14:30. The next twelve-hour comparison had full coverage and similar estimates. Changing to a 72-hour offset and a 24-hour window reused those fetched results: 23 options had complete coverage and two beyond the horizon showed Unavailable/0% coverage and were excluded from ranking. Selecting an unavailable departure disabled its reminder.

`screenshots/iphone-forecast-live.png` is an unaltered native screenshot of the real provider forecast chart and similar-estimates state. Its path/travel time are illustrative; it does not establish live routing access or accuracy of future pollution. Values are the response at test time, not permanent current data.

The Mac locked during the final control checks. The custom-time refinement and reminder API compile, but custom-date interaction, reminder permission/delivery/relaunch/cancellation, missing-key UI, real routed-geometry forecasts, partial network/cancellation/expiry UI, VoiceOver, large text and iPad layout remain runtime acceptance checks. Automated production calculation tests do not establish those UI/device behaviours.

## Primary references

- [OpenWeather Air Pollution API, forecast endpoint and timestamps](https://openweathermap.org/api/air-pollution)
- [Swift Charts](https://developer.apple.com/documentation/charts)
- [Local time-interval notification triggers](https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger)
