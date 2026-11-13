# Octria

A free, cross-platform app that turns any task into a classroom with a roadmap of phases and steps, shown as an interactive node graph called Flowspace.

Phases 1 and 2, the Flowspace prototype and the core app, are complete. Phase 3 is done: collaboration, chats, handovers, practice links, in-app notifications with a count on the app icon, Kanvas (with image, PDF and video cards) and file libraries in each person's own Google Drive. Phase 4 has started: Ofy drafts and adds to plans, and the Ofy assistant is on every screen, answering questions, showing how on screen and doing things after approval, by text or voice. Mock tests and Kanvas AI helpers come next.

## Run it

Needs [Flutter](https://flutter.dev). This repository holds no keys, so a fresh copy needs one placeholder file before it will compile:

```bash
cp lib/firebase_options.example.dart lib/firebase_options.dart
```

```bash
flutter pub get
```

Then, in Chrome, try the sample plans:

```bash
flutter run -d chrome
```

Or try the real screens with nothing saved:

```bash
flutter run -d chrome --dart-define=OCTRIA_BACKEND=local
```

Android won't build until you've connected your own Firebase project, because it needs `google-services.json`.

## Your own keys and secrets

None of the original project's keys or secrets are in this repository, and they aren't shared. To run Octria for real, create your own of everything below. The files are in `.gitignore`, so keep them there.

| What | Where it goes | How to create it |
| --- | --- | --- |
| Firebase settings for the app | `lib/firebase_options.dart` | `flutterfire configure` (step 3) |
| Firebase settings for Android | `android/app/google-services.json` | `flutterfire configure` (step 3) |
| Firebase settings for iOS or macOS, if you add them | `GoogleService-Info.plist` | `flutterfire configure` (step 3) |
| GitHub sign-in client ID and secret | Firebase console only, never in a file here | A GitHub OAuth app (step 5) |
| Android signing key and its passwords | `key.properties` and a `.jks` file, outside git | `keytool` (step 6) |

### 1. Create a Firebase project

In the [Firebase console](https://console.firebase.google.com), create a project and a Firestore database. Your project's data is entirely separate from anyone else's.

### 2. Install the tools

```bash
npm install -g firebase-tools
```

```bash
dart pub global activate flutterfire_cli
```

```bash
firebase login
```

### 3. Generate your settings files

This writes the files in the table, replacing the placeholder:

```bash
flutterfire configure --project=YOUR_PROJECT_ID
```

It also adds a `flutter` section to `firebase.json` holding your project's IDs. Delete that section before you commit.

### 4. Publish the security rules and indexes

```bash
firebase deploy --only firestore --project YOUR_PROJECT_ID
```

### 5. Turn on sign-in

In the console under Authentication, enable Email/Password and Google. For GitHub:

1. Enable GitHub in Firebase and copy the callback URL it shows.
2. On GitHub, go to Settings, Developer settings, OAuth Apps, and create an app with that callback URL.
3. Paste the app's client ID and client secret into Firebase.

The client secret stays in Firebase. Don't put it in code, in a file here or in a chat.

### 6. Turn on Google Drive for file libraries

Files people add go in their own Google Drive, through the Google sign-in Firebase already uses, asking only for the `drive.file` scope (Octria sees just the files it put there). In the [Google Cloud console](https://console.cloud.google.com/apis/library/drive.googleapis.com), pick your Firebase project and enable the Google Drive API. Without it, adding a file says Drive isn't switched on. No key or client ID is needed in this repository.

### 7. Turn on Ofy (Gemini through Firebase AI Logic)

Ofy, the AI, calls Gemini through Firebase AI Logic, so no Gemini key is in the app or this repository. It runs on the free Gemini Developer API without billing.

1. In the Firebase console, open **AI Logic**, press **Get started** and choose the **Gemini Developer API**.
2. Firebase requires **App Check** before AI Logic will answer. For the website, create a **reCAPTCHA v3** key at [google.com/recaptcha/admin](https://www.google.com/recaptcha/admin) for your site's domain, then in the Firebase console under **App Check**, register your web app with the reCAPTCHA v3 provider and paste in the key's secret. Build the site with the site key:

```bash
flutter build web --no-web-resources-cdn --dart-define=OCTRIA_RECAPTCHA_KEY=YOUR_SITE_KEY
```

3. For Android builds that aren't on Google Play yet, add a **debug token** under App Check, Apps, your Android app, Manage debug tokens, and build with it. Keep it out of git; anyone with it can pass App Check.

```bash
flutter build apk --release --dart-define=OCTRIA_APPCHECK_DEBUG_TOKEN=YOUR_DEBUG_TOKEN
```

Each person can ask Ofy 40 times a day, enforced by the rules. The model is `gemini-3.5-flash-lite`; change it with `--dart-define=OCTRIA_AI_MODEL=...`.

### 8. Android: sign-in and signing

Create your own signing key, keep it and its passwords outside git, and back them up. Lose it and you can't update your app on the Play Store.

```bash
keytool -genkey -v -keystore ~/octria-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias octria
```

Show the key's SHA-1 and SHA-256 fingerprints, then add both to your Android app in the Firebase project settings. Google sign-in fails without them:

```bash
keytool -list -v -keystore ~/octria-release.jks -alias octria
```

Debug and release builds sign with Flutter's debug key until you [set up release signing](https://docs.flutter.dev/deployment/android#sign-the-app). If you use that key for now, add its fingerprints as well.

### 9. Host it and point invite links at your site

Invite links use the original site unless you set your own address when you build:

```bash
flutter build web --no-web-resources-cdn --dart-define=OCTRIA_APP_URL=https://YOUR_PROJECT_ID.web.app
```

```bash
firebase deploy --only hosting --project YOUR_PROJECT_ID
```

### If something leaks

- **A GitHub client secret, signing password or service account key:** treat it as stolen. Replace it straight away, because deleting it from git doesn't undo the leak.
- **Firebase settings for the app:** these aren't passwords. Every visitor's browser receives them to talk to Firebase, so they can't be hidden in a published app. What protects your data is `firestore.rules`. Also restrict the API key to your app and site in the Google Cloud console.

## Test

```bash
flutter test
```

The security rules are tested on the Firestore emulator, which needs Java 21 or newer:

```bash
cd tool/rules_test && npm install && npm test
```

## More

- [Product](PRODUCT.md): who it's for and what's in scope
- [Design system](DESIGN.md): the glass look, colours and rules
- [Planning document](docs/Octria_Planning_Document.pdf): features, data model and build phases
