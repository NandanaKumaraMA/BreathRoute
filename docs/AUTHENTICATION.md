# Account implementation — 16 October 2026

This is the first stage of the student's request to implement the remaining work one step at a time. Firebase Authentication is integrated; cloud journal sync remains the next stage. The student confirmed that no Firebase project has been created. Do not present the local emulator as a connected cloud backend.

## User flow

**You → Your account** offers sign-in, registration and password-reset modes. Sign-in restores the SDK user session after relaunch. A signed-in card shows email/verification status, verification and refresh controls, and confirmed sign-out. Password fields use native secure entry/autofill semantics; the app never stores passwords in Core Data or preferences. The SDK manages its session credentials.

A missing or mismatched `GoogleService-Info.plist` leaves the app in a usable local mode and disables account submission. Follow `FIREBASE_SETUP.md` for the real configuration. Do not create a fake production configuration to make the button appear enabled.

Registration uses an app minimum of eight characters, checks exact confirmation and preserves password whitespace. Existing sign-ins are not blocked by the new-registration length policy. Firebase can enforce a stronger server policy. Account errors use fixed messages rather than raw request errors/URLs; reset success does not disclose whether an email is registered.

## Journal isolation

- The original guest SQLite filename remains `BreatheRouteV1.sqlite`; its data is not reset, moved or copied during sign-in.
- Every account has a separate SQLite file, selected using environment, Firebase project and user ID. SHA-256 turns the namespace into a fixed filename; user-controlled separators cannot escape the storage directory. The filename contains no email or literal user ID.
- Display name and walking intensity preferences are scoped to the journal. Motion preference, device lock, local reminders and provider keys remain device preferences.
- On identity change, clear previous journal arrays, route selections, exposure state, Health snapshots and forecast cache before opening the new store. Reset the navigation hierarchy so old details/editors do not remain visible. Never fall back to another account's store if opening the new one fails.
- Late Health/forecast responses are invalidated across account changes. Air-refresh responses also check their initiating scope. No journal, GPS or Health data is uploaded by this account stage.
- Interactive account changes are disabled while a walk/recovery or blocking request is open. An external authentication-state change checkpoints an active walk under its original account, stops recording and switches journals. Returning to the original account can recover its saved portion. Native active-walk/expiry verification remains required.
- Local authentication is separate from the optional Face ID/passcode app lock. Signing out returns to the guest journal while keeping the account journal for a later sign-in. Cloud backup, guest import and account-to-account transfers are not implemented here.

## Local emulator

Install the official Firebase CLI in your development environment, then run from the repository root:

```sh
firebase emulators:start --only auth --project demo-breatheroute --config backend/firebase.json
```

The checked-in configuration binds Auth and its hub to loopback. The project name starts with `demo-`. The emulator does not require creating a cloud project. The emulator UI is disabled. With a Debug build on an isolated simulator, launch the app with the argument `--firebase-auth-emulator`. It uses a named Firebase app and visibly labelled emulator mode. Release builds ignore that argument. Its local journal namespace differs from a real Firebase project's namespace.

With the emulator running:

```sh
node scripts/test-auth-emulator.mjs
```

This uses synthetic `example.test` users, makes only fixed loopback requests and prints assertions without tokens/passwords. Emulator logs are ignored by Git. Native test credentials were not saved to Apple's Passwords app. Stop the emulator with Ctrl-C in its terminal when finished; it is not an automation or a deployed backend.

## Verification

- Debug and Release iOS Simulator builds succeed, with the SwiftUI app delegate attached and Firebase delegate proxy disabled as a Boolean in the built Info.plist. The emulator launch flag is inside a Debug-only compilation block.
- All **45 Swift Testing functions** pass: account validation/namespace policies, a new isolated guest/Alice/Bob SQLite reopen/delete test and all existing calculation/persistence tests. These establish production rules/storage behaviour, not cloud security rules.
- The official Auth emulator accepts two distinct users, sign-in, rejects a wrong password and accepts a reset request through `scripts/test-auth-emulator.mjs`.
- On **BreatheRoute Account QA**, ordinary launch without a configuration preserves local access and displays the setup notice.
- A labelled guest synthetic note was saved. Native sign-in to the pre-created Alice emulator account shows an empty separate journal. Saving an Alice-only synthetic note, terminating and relaunching with emulator mode restores Alice and her note. Sign-out returns only the original guest note. Bob sign-in shows an empty journal containing neither note.
- The native reset form successfully submits an emulator request and shows the generic inbox confirmation. No actual email or password reset was completed. Backend registration was exercised through the emulator API; native registration submission and inbox delivery remain unverified.
- `screenshots/iphone-account-setup.png` shows missing configuration. `screenshots/iphone-account-emulator.png` shows the explicitly labelled synthetic signed-in account. Neither is evidence of a real cloud account or Firestore sync.

Still required: the student's real configuration, native registration, real verification/reset delivery, expired/revoked session transitions, active/recovered walk guards, sign-in failure UI, Health callback isolation on hardware, VoiceOver/large text/iPad checks, and Firestore owner-only sync/consent/retry/conflict/deletion tests. The user's simulator interaction interrupted the final walk-guard check; no result is claimed for it.

## Primary references

- [Firebase Apple setup and SwiftUI app delegate](https://firebase.google.com/docs/ios/setup)
- [Password authentication and password policies](https://firebase.google.com/docs/auth/ios/password-auth)
- [Authentication-state listener](https://firebase.google.com/docs/auth/ios/start)
- [Connecting the Auth emulator](https://firebase.google.com/docs/emulator-suite/connect_auth)
- [SDK release information](https://github.com/firebase/firebase-ios-sdk/releases/tag/13.0.1) — 13.0.1 is a Zip/Carthage release; this project pins the 13.0.0 SPM release.
