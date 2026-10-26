# Saved GPS paths and unfinished-walk recovery

Implemented and checked on 8 October 2026. This adds durable foreground recordings; it does not enable background tracking or reconstruct an unobserved journey.

## User journey

1. Start a selected walk in Explore. The app first saves its initial recovery checkpoint; a failed save prevents starting an unrecoverable recording.
2. During a real walk, accepted GPS fixes appear as recorded blue path legs. The active card shows the last successful recovery-save time and any checkpoint failure.
3. Reopen after an interrupted session. Today and Explore offer **Resume saved walk**, **Save recorded portion**, or a confirmed **Discard unfinished walk**. No recording resumes automatically.
4. Resume retains the original start, recorded distance, exposure intervals, phone-motion summary, destination and last plan. Its next GPS fix starts a new leg. Closed-app time stays unobserved.
5. Save recorded portion ends the recovered summary at the last checkpoint time. Resume followed by Finish includes the closed-app interval in elapsed time, reducing coverage without adding movement or dose.
6. Finish saves the trip and removes the unfinished checkpoint in one Core Data transaction. Retry uses the same trip identifier, avoiding duplicate entries. A failure leaves the recording available.
7. Journal → saved walk shows actual GPS geometry in blue and the last planned route in grey dashes. The replay slider and button advance saved fixes with their timestamps and reported accuracy. Demo walks show only their labelled synthetic plan. Older entries remain readable without geometry.

## Recording and storage rules

- Coordinates must be finite and within geographic ranges; reported accuracy must be 0–100 m. Duplicate and backdated fixes are ignored.
- A distance/exposure interval requires consecutive accepted fixes no more than 30 seconds apart and a speed below 4 m/s. Longer gaps or implausible jumps start another leg and contribute no recorded distance, time or dose. Backgrounding explicitly breaks the path.
- Core Location supplies distance between fixes. Pedometer distance remains a separate metric. Pollution uses the latest usable non-demo reading; missing readings reduce coverage rather than becoming zero pollution.
- Walking-intensity ventilation is frozen at session start and stored with the summary. It remains an illustrative assumption, not a physiological measurement.
- Checkpoints include version, session ID, original start, last save, destination, planned geometry/source/samples, recorded fixes, exposure intervals, motion summary and ventilation. Validation rejects unsupported versions or inconsistent data. An unreadable checkpoint is retained until explicitly discarded.
- Saves occur at valid GPS updates, lifecycle/motion changes, remaining-route switches and every 15 seconds while the foreground timer runs. A sudden kill can lose data after the last successful checkpoint. Background suspension is excluded, not filled by that timer.
- Explicit motion recovery keeps reported totals and adds the closed-app gap to unclassified time. It starts a new monitoring window; there is no historical sensor backfill.
- Recovery does not silently restore old native geofence registrations or use an old sample as current dose data. Refresh data and re-enable area awareness as appropriate.
- New trip fields are optional so earlier Codable records remain compatible. GPS coordinates stay in local Core Data and are excluded from Share walk summary. No GPS trace, Health record or motion summary is uploaded to a cloud service in this implementation.

## Verification evidence

The simulator build succeeds. All **35 Swift Testing functions** pass, including production GPS gap/invalid-fix rules, checkpoint round trips/version validation, motion restoration and isolated SQLite reopen/atomic completion/retry/failure preservation.

On **BreatheRoute Recovery QA**, a labelled demo was started, checkpointed, terminated and reopened. The recovery card displayed its last-save time and zero actual GPS fixes. Resume retained the original elapsed time. Finish created one demo journal entry; a subsequent relaunch showed no unfinished recovery prompt and retained that entry. Its detail showed the recovery explanation, 15 L/min assumption, zero actual fixes and synthetic planned route metadata.

An unexpected demo Motion & Fitness prompt exposed unconditional sensor-stop calls. Those calls now run only for sensors actually started. After resetting that permission on the isolated QA device, starting another demo showed the active walk and no permission prompt.

`screenshots/iphone-walk-recovery.png` is an unaltered recovery-card screenshot. It contains a demo record, not a real tracked walk. A physical GPS walk, rendered blue-leg replay, real restored sensor totals, background/permission transitions, storage failure UI and largest-text/VoiceOver journeys remain runtime acceptance checks. Automated geometry/storage tests do not establish those hardware or UI behaviours.

## Official references

- [SwiftUI scene phases](https://developer.apple.com/documentation/swiftui/scenephase)
- [Core Data context save](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/save())
- [Core Data rollback](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/rollback())
- [MapPolyline](https://developer.apple.com/documentation/mapkit/mappolyline)
