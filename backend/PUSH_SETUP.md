# Remote notification setup

## Free notification workflow

No Apple membership or billing upgrade is needed for these features:

- **You → Notifications → Live journal updates** listens to the signed-in owner's private `users/{uid}` summary while BreatheRoute is open and unlocked. It reads the journal revision, not the symptom-note payload. The first server snapshot is a quiet baseline; cached/pending snapshots, duplicates and this device's sync acknowledgements do not generate alerts. A changed committed revision shows a **Review** prompt. The journal is still merged only when the user chooses **Sync now**. Turning this off, signing out, locking or backgrounding detaches the listener. Resuming checks the next server revision. Firestore's free-plan quotas still apply.
- **Show notification banners** optionally adds a generic local banner after a real Firestore change. Notification permission is separate from the live-update toggle; denying banners still allows in-app updates. This is foreground cloud listening followed by a local notification, not APNs background delivery.
- **Check notifications → Send local test alert** schedules a local alert in three seconds. Tap it to return to You. Daily reminders, departure reminders and walk area alerts remain separate.
- In a **Debug simulator build**, **Check notifications → Prepare simulator push** writes a short-lived payload for the current app/account/installation. On the Mac, run:

```sh
cd /Users/nandana/dev/BreathRoute
python3 scripts/send-simulator-notification.py
# If several simulators are booted, add --device YOUR_SIMULATOR_UUID
```

The helper injects the prepared payload with Apple's `simctl push`. It neither contacts FCM/APNs nor requests payment. Verify the banner and tap action. The app reports **Simulated push received**; this is not proof of internet delivery. The test expires after 15 minutes and is invalidated on account changes/sign-out. Release builds and physical-device builds reject this test path.

The **Remote delivery connection** disclosure retains the optional APNs/FCM implementation described below. It is independent of the free workflow.

Debug checks `--free-notification-qa` exercise lifecycle, account isolation, permission interruptions, duplicate filtering and simulator-session expiry with injected adapters. `--firebase-auth-emulator --free-notification-emulator-qa` verifies native Firestore snapshot delivery against isolated `demo-breatheroute` Auth/Firestore emulators. Neither workflow writes to the production Firebase project.

## Optional APNs/FCM delivery

The default configuration works with Firebase's free Spark plan. APNs/FCM device registration, permission controls, private Firestore token storage, opt-out, account-switch cleanup and notification-tap handling are implemented. Delivery can be requested manually from Firebase Console or the trusted sender tool. No Cloud Functions deployment or Firebase billing upgrade is required for this path.

Automatic notifications when the cloud journal changes are a separate optional Cloud Functions path that requires Blaze. They are not enabled on Spark. No billing change has been made. The private token rules were published through Firebase Console in Chrome on 30 October 2026. Live APNs delivery remains unverified: Firebase has no development or production APNs key/certificate, and the owner confirmed that no Apple Developer Program membership or APNs key is available.

## Apple configuration

Firebase's free plan does not replace Apple's APNs credentials:

1. Use an active Apple Developer membership and enable Push Notifications for `MANKumara.BreathRoute` in the Apple developer account.
2. Select the correct signing team in Xcode. Push Notifications capability and the entitlement are included: Debug uses `development`, Release uses `production`. Device/distribution provisioning profiles must authorize that entitlement.
3. In Firebase Console → Project settings → Cloud Messaging → Apple app configuration, upload a suitable APNs `.p8` key, Key ID and Team ID. Complete the development/production selection shown by Firebase.
4. Keep Apple credentials and `.p8` keys private and outside the app/repository. Keep the existing matching `GoogleService-Info.plist` in the app.

This feature uses visible alerts. It does not enable silent background sync, background GPS recording or emergency health monitoring.

## Spark setup

`AppConfig.xcconfig` defaults `BREATHE_PUSH_BACKEND` to `firestore`. It can be overridden by the ignored local configuration if the owner later chooses the optional Functions path.

The tested rules are already published for `breathe-route-75d07`. For future rule updates, either use Firebase Console or complete the Firebase CLI login yourself before deploying:

```sh
cd /Users/nandana/dev/BreathRoute/backend
pnpm exec firebase login
pnpm exec firebase deploy --project breathe-route-75d07 --only firestore:rules
```

Use the explicit `firestore:rules` target on Spark. Do not use a blanket deploy of the optional Functions configuration.

After Google sign-in, open **You → Notifications → Remote delivery connection → Enable cloud notifications**, review the token disclosure and handle the OS permission prompt. The app obtains an APNs token before requesting an FCM token, then saves this private document:

```text
users/{uid}/pushDevices/{installationUUID}
```

Fields are `schemaVersion`, `uid`, `installationID`, `token`, `enabled` and server `updatedAt`. Only the authenticated owner can read/write their records. Validation rejects a forged UID, wrong installation ID, unexpected fields or forged timestamp. A token rotation replaces the current installation record. Tokens are excluded from journal sync, exports and personal activity totals.

**Connected** confirms server registration, not APNs delivery. Turning notifications off unregisters APNs, clears matching delivered cloud alerts, removes the registration when reachable and invalidates the FCM token. Sign-out does the same before changing Auth state. Failed token invalidation prevents a different account from connecting until cleanup succeeds. Local reminders and local journals stay separate.

## Send a notification without Blaze

### Firebase Console

Use your own project's Messaging notification composer and target the registered FCM token from the private device document. Keep the text generic. Add these custom data values so the app can validate and route the alert:

```text
version = 1
kind = connection_test
recipientUID = the owning Firebase Auth UID
installationID = the device document's installation UUID
```

The app accepts only its current opted-in account/installation. The connection test opens **You**. A `journal_updated` message opens **Journal**. Arbitrary URLs/actions are not supported. Do not paste device tokens into chat or public files.

### Trusted sender tool

`functions/send-push.mjs` can run on a trusted computer with Firebase Admin Application Default Credentials. Credentials must remain outside the app/repository; configure the private credential file locally using `GOOGLE_APPLICATION_CREDENTIALS`, or an existing suitable ADC setup. Do not share the private key in chat. The script does not create credentials or enable billing.

```sh
cd /Users/nandana/dev/BreathRoute/backend
pnpm --dir functions install --frozen-lockfile --ignore-scripts
node functions/send-push.mjs --project breathe-route-75d07 --uid YOUR_UID --installation YOUR_INSTALLATION_UUID
```

The default run asks FCM to validate the fixed payload without delivering it. After reviewing the target, explicitly add `--send` to request delivery. Optional `--kind journal_updated` selects the other fixed generic message; use it only when an actual journal update is being demonstrated. The tool accepts no custom title, body or URL, never prints tokens and reads only the named owner's installation. It excludes stale registrations after 30 days and removes invalid tokens only if the current stored token still matches.

There is no always-running sender on Spark in this implementation. Manual sending is genuine remote FCM delivery; it does not automatically react to journal changes. The in-app test-send button is shown only when a configured server endpoint can perform that action.

## Optional automatic sender on Blaze

Only choose this if the project owner explicitly decides to enable billing. Functions use region `asia-south1`, Node.js 22, at most two instances per function and no minimum instance setting. Those limits are not a spending cap.

Set `BREATHE_PUSH_BACKEND = functions` in the ignored local build configuration, rebuild, and deploy:

```sh
cd /Users/nandana/dev/BreathRoute/backend
pnpm --dir functions install --frozen-lockfile --ignore-scripts
pnpm --dir functions test
pnpm exec firebase deploy --project breathe-route-75d07 --only functions:cloud-alerts,firestore:rules
```

The authenticated callable endpoints register/revoke devices and provide a self-only, fixed-message connection test with a 60-second cooldown. A canonical journal-revision trigger sends generic update text to that account's opted-in devices, with five-minute cooldown/event suppression. It never copies journal content into a notification. The server-side `pushDevices/{sha256-token}` and `pushDeliveryState/{hash}` collections deny all client SDK access; each token has one owner and at most 20 active installations are allowed per account. Device mappings from Spark are not automatically migrated; reconnect after switching modes.

## Verification

Verify an actual banner/notification and its tap action. Foreground receipt and notification taps record a received time. FCM acceptance alone does not establish device delivery; Focus, permissions and provider conditions can delay/suppress alerts. Never treat this as a time-critical health channel.

Automated checks use no production credentials or real FCM sends:

```sh
cd /Users/nandana/dev/BreathRoute
swift test --disable-sandbox
cd backend
pnpm --dir functions test
GCLOUD_PROJECT=demo-breatheroute BREATHE_PUSH_TEST_TRANSPORT=true pnpm exec firebase emulators:exec \
  --project demo-breatheroute --only auth,firestore,functions \
  'node --test functions/test/push-integration.test.mjs && node --test tests/firestore.rules.test.mjs'
```

The explicit mock send transport is enabled only inside the Functions Emulator with project ID exactly `demo-breatheroute`. It captures payloads locally instead of calling FCM. Rules checks cover Spark owner-only registrations and the admin-only optional sender records. Local emulator checks use Java 21+.

The Debug `--remote-push-qa` workflow uses injected permissions, APNs, token and backend adapters with isolated preferences. It checks guest/permission gates, token sequencing, typed routing, sign-out races, account switching, failed revocation and delayed cleanup. It neither requests system permission nor sends a real push. The report is `remote-push-qa.json` in the dedicated simulator's Documents directory.

## References

- [Firebase pricing](https://firebase.google.com/pricing)
- [Apple client setup and APNs mapping](https://firebase.google.com/docs/cloud-messaging/ios/client)
- [Callable HTTP protocol for the optional sender](https://firebase.google.com/docs/functions/callable-reference)
- [Functions deployment requirements](https://firebase.google.com/docs/functions/get-started)
- [FCM token management](https://firebase.google.com/docs/cloud-messaging/manage-tokens)
- [Firestore snapshot listeners](https://firebase.google.com/docs/firestore/query-data/listen)
- [Apple Simulator push testing](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-11_4-release-notes)
