# Firebase setup for BreatheRoute

Updated 16 October 2026. The app now includes Firebase Authentication SDK integration, account forms and separate local journals. Native sign-in, session restoration, sign-out, reset requests and guest/two-account isolation have been verified against the local Auth emulator. **A real Firebase project is still required for cloud account verification. Firestore journal sync is the next implementation stage.**

## Your next setup step

1. Open the [Firebase console](https://console.firebase.google.com/) and sign in to your Google account.
2. Create a project called **BreatheRoute**. Google Analytics is optional and is not needed for the proposed account and journal-summary integration. Review any terms yourself.
3. Add an **iOS app**. Use this exact, case-sensitive bundle identifier: **`MANKumara.BreathRoute`**. App nickname: **BreatheRoute iOS**. An App Store ID can be left blank for this development app.
4. Download **`GoogleService-Info.plist`**. Keep its filename unchanged and place it in the local `BreathRoute/` source folder. The repository ignores this configuration file. It contains project/app identifiers; a service-account private key is a different file and is not needed in the iOS app.
5. Under **Authentication → Sign-in method**, enable **Email/Password**.
6. Rebuild and run the app. **You → Your account** should offer sign-in instead of the missing-configuration notice. Create a real test account yourself and verify its email, sign-out, sign-in and reset inbox delivery with the developer.

Firestore can follow after account verification. Create its database in production mode when beginning sync; keep access denied until owner-only rules and the client are implemented and tested.

After these steps, tell me the project is ready and where the downloaded configuration file is saved. Do not provide a Google password or a service-account private key.

## Implemented account stage

- FirebaseCore/FirebaseAuth Swift Package products; Firebase SDK 13.0.0 is pinned for SPM with a resolved dependency file. Analytics and Firestore products are not linked in this stage.
- Configuration is validated against the app bundle identifier. Without it, local features remain usable and the account screen explains that cloud sign-in is unavailable.
- Registration, sign-in, reset and verification requests, sign-out and authentication-state restoration code.
- Account-specific SQLite journals and profile preferences. The legacy guest journal stays intact, and records are not silently imported into an account or uploaded.
- Explicitly labelled Debug-only local Auth emulator support for development, separate from real project/account namespaces. See `AUTHENTICATION.md` for commands and evidence.

## Development and verification still required

- Verify real-project registration, password policy, email verification/reset delivery, restoration and error paths. The local emulator does not send real email.
- Add Firestore and the consented sync workflow after this account stage is connected.
- Sync only the agreed trip/journal summaries; raw HealthKit samples and GPS tracks remain local.
- Add owner-only rules, explicit sync consent/status, an offline retry policy, conflict handling and deletion propagation.
- Verify two-account isolation, offline/retry behaviour, relaunch and denied-access states before claiming the backend is complete.

Do not enable public database access to make the development app appear to work. The rules and account-scoped data model are part of the implementation.

## Official references

- [Firebase Apple project setup](https://firebase.google.com/docs/ios/setup)
- [Firebase Authentication for Apple platforms](https://firebase.google.com/docs/auth/ios/start)
- [Cloud Firestore setup](https://firebase.google.com/docs/firestore/quickstart)

Checked against the official setup/auth documentation on 16 October 2026.
