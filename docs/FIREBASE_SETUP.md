# Firebase setup for BreatheRoute

Firebase is the next external setup dependency. The current app has a local profile, device authentication and a local journal. Firebase account sign-in and cloud sync are not implemented or verified yet.

## Your next setup step

1. Open the [Firebase console](https://console.firebase.google.com/) and sign in to your Google account.
2. Create a project called **BreatheRoute**. Google Analytics is optional and is not needed for the proposed account and journal-summary integration. Review any terms yourself.
3. Add an **iOS app**. Use this exact, case-sensitive bundle identifier: **`MANKumara.BreathRoute`**. App nickname: **BreatheRoute iOS**. An App Store ID can be left blank for this development app.
4. Download **`GoogleService-Info.plist`**. Keep its filename unchanged and place it in the local `BreathRoute/` source folder. The repository ignores this configuration file. It contains project/app identifiers; a service-account private key is a different file and is not needed in the iOS app.
5. Under **Authentication → Sign-in method**, enable **Email/Password**.
6. Create a **Cloud Firestore** database using production mode. Choose a suitable available region for the project. Production mode initially denies client access; owner-only rules will be added and tested with the sync implementation.

After these steps, tell me the project is ready and where the downloaded configuration file is saved. Do not provide a Google password or a service-account private key.

## Development still required after setup

- Add the Firebase Auth and Firestore SDK products and configure the app using the downloaded file.
- Build registration, sign-in, sign-out, password reset and session restoration.
- Keep each account's local and remote records isolated, including when users sign out or switch accounts.
- Sync only the agreed trip/journal summaries; raw HealthKit samples and GPS tracks remain local.
- Add owner-only rules, explicit sync consent/status, an offline retry policy, conflict handling and deletion propagation.
- Verify two-account isolation, offline/retry behaviour, relaunch and denied-access states before claiming the backend is complete.

Do not enable public database access to make the development app appear to work. The rules and account-scoped data model are part of the implementation.

## Official references

- [Firebase Apple project setup](https://firebase.google.com/docs/ios/setup)
- [Firebase Authentication for Apple platforms](https://firebase.google.com/docs/auth/ios/start)
- [Cloud Firestore setup](https://firebase.google.com/docs/firestore/quickstart)

Checked against the official documentation on 7 October 2026.
