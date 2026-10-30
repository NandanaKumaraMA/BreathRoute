# Private Firestore data model

The app uses the default database in `breathe-route-75d07`, Mumbai (`asia-south1`). Firestore creates collections/documents on their first write; `firestore.rules` enforces the deployed document shapes. `firestore.schema.json` is a developer reference, not a SQL migration file.

| Path | Purpose |
| --- | --- |
| `users/{uid}` | Chosen display name, journal counts, completed projection revision and server update time |
| `users/{uid}/preferences/current` | Walking pace and extra-time budget |
| `users/{uid}/walks/{uuid}` | One typed walk summary per document, with a native Timestamp |
| `users/{uid}/symptoms/{uuid}` | One typed symptom note per document, with a native Timestamp |
| `users/{uid}/journal/current` | Versioned canonical journal for three-way merge and revision-checked commits |
| `users/{uid}/demoDatasets/coursework2026` | Explicitly synthetic demonstration profile/preferences and dataset metadata |
| `users/{uid}/demoDatasets/coursework2026/walks/{uuid}` | 30 stable, labelled synthetic walking examples |
| `users/{uid}/demoDatasets/coursework2026/symptoms/{uuid}` | 45 stable, labelled synthetic symptom examples |

Only the authenticated owner can access these paths. Profile and preference writes must name the current journal revision. Walk and symptom fields are allowlisted and type/range checked. All other paths are denied, including arbitrary profile documents, raw GPS and Health collections. Demo records require explicit synthetic markers and are separate from journal queries and totals.

## Sync and migration

Signing in does not upload data. Review expanded cloud-sync consent, enable it, then tap Sync now. Old journal-only consent does not automatically include the newly added profile fields. Version-one snapshots decode without invented settings; the next approved sync writes version two and creates the readable documents and parent user record.

The canonical snapshot remains the authority for conflict resolution, independent edits and deletion propagation. Readable records are a derived representation. Each bounded projection transaction checks that the canonical revision is still current. The parent `journalRevision` marks projection completion only after every record chunk succeeds. A network failure can leave a pending projection; local acknowledgement is withheld and retry safely repairs it. This is eventual projection consistency, not an atomic commit spanning every readable document. Server data changed through the Console should be treated as administration; application changes go through the app's journal sync.

Profiles/preferences merge independently of journal entries. Competing settings keep the server version and show a review message. Concurrent journal edits still preserve labelled conflict copies. Sync remains bounded to 500 journal entries and 350 KB. API keys, GPS geometry, Motion data, Apple Health records, device notification permissions and unfinished walks are excluded.

## Demonstration data

`CloudDemoFixtures` defines 30 fictional walks and 45 fictional notes over 26 September–25 October 2026. The scenarios include all six symptom types, severity 1–5, 30 linked and 15 independent notes, three modelled walking paces, two walks stopped early, and complete/partial/unavailable exposure coverage (12/12/6 walks). Distances, durations and covered exposure use consistent units. Missing exposure has no dose value. These examples are not real provider observations or health measurements.

`CloudDemoSeeder` writes all 75 records and the manifest in one batch under the private `demoDatasets/coursework2026` path with fixed IDs. Repeat seeding updates the same examples. It does not write the canonical journal, import examples into the user's records or change activity totals.

Journal → Explore a demo journal opens a separate read-only viewer with walking-distance and symptom-count charts, 7/30-example-day filters, coverage counts, notes and walk details. Bundled examples are available offline and labelled as such. A signed-in user can explicitly load cloud examples. Server-only reads validate document IDs, allowed fields, synthetic markers, counts and links. A before/after manifest comparison rejects mixed reads during replacement. Account checks reject obsolete identities; closing the viewer cancels the load. Viewing never seeds or uploads records.

The explicit Debug `--structured-cloud-qa` workflow is restricted to the local Auth/Firestore emulators and the `demo-breatheroute` project. It verifies migration, typed records, projection completion, demo isolation and idempotency. It cannot run against the production database. The separate `--synthetic-live-journal-qa` verifier requires the previously authorised signed-in QA account and performs a read-only server restore into an isolated in-memory local store.

## Private notification delivery metadata

Remote notifications use separate, server-managed collections. The default Spark configuration stores `users/{uid}/pushDevices/{installationUUID}` with owner-only client access and a separate in-app opt-in. Token fields are type/identity/timestamp validated. The optional Functions configuration uses the admin-only paths below. These are outside the journal snapshot, sync counts, example records and export data.

| Path | Purpose | Access |
| --- | --- | --- |
| `pushDevices/{sha256-token}` | Schema version, current owner UID, installation UUID, private FCM token, enabled flag and last registration time in milliseconds | Cloud Functions Admin SDK only |
| `pushDeliveryState/{hash}` | Connection-test/journal alert cooldown times and the last handled event ID | Cloud Functions Admin SDK only |

In Functions mode, a token maps to one server-side owner. In Spark mode, each owner/installation has one private current record; client account-switch cleanup invalidates the old FCM token before another account can reconnect. Opt-out/sign-out revoke the mapping when reachable and invalidate the local token. Delivery excludes registrations stale for 30 days. Notification content is generic; GPS, symptoms, Health data and the canonical journal payload are never copied into it. See [remote notification setup](PUSH_SETUP.md) for deployment and verification.
