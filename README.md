# Octria

A free, cross-platform app that turns any task into a classroom with a roadmap of phases and steps, shown as an interactive node graph called Flowspace. Its AI helper, Ofy, drafts the plan, answers questions about the app and does things for you once you approve.

**Status:** phases 1 to 4 are complete (version 0.15.1). Phase 5, active-time tracking and the growth map, is next.

## What it does

- **Classrooms** for one person or a group of up to 10, with a master, co-masters, invite codes and join requests.
- **Flowspace**, a custom-drawn node graph: a lane per person, phases as columns, dependency arrows, three zoom levels, the critical path, focus on me, a timeline view and a list view.
- **Ofy**, on every screen, by text or voice: it answers questions, shows you where things are, and does things after you approve. It also drafts plans (and fits new steps into an existing one), re-plans when you fall behind, shares work out by skills, finds study material for a step, writes mock tests and interviews, helps with Kanvas boards, and explains a screenshot or picture.
- **Mock tests and checklists** after each phase, with levels, mock interviews and saved results.
- **Collaboration:** private comments, suggestions, class and group chats, handovers, an activity log and a "Since you were away" view.
- **Kanvas:** personal whiteboards with drawing, notes, checklists, connectors and image, PDF and video cards.
- **Files** in each person's own Google Drive.
- **Reminders** for due steps, calendar export, Done and Deleted tabs, and light and dark themes.

It runs on the web, Android and desktop from one Flutter codebase, on Firebase (Auth, Firestore, Hosting, AI Logic and App Check) and Google's Gemini models.

## Try it in two minutes, with no accounts or keys

You need [Flutter](https://flutter.dev) 3.47 or newer (Dart 3.13). This repository holds no keys, so a fresh copy needs one placeholder file before it compiles:

```bash
cp lib/firebase_options.example.dart lib/firebase_options.dart
```

```bash
flutter pub get
```

Then choose how much you want to see:

| Command | What you get |
| --- | --- |
| `flutter run -d chrome` | The sample plans: Flowspace on made-up data |
| `flutter run -d chrome --dart-define=OCTRIA_BACKEND=demo` | A ready-made classroom with people, chats, boards and requests, all in memory |
| `flutter run -d chrome --dart-define=OCTRIA_BACKEND=local` | The real screens, starting empty; sign up with any email, nothing is saved |

In all three, Ofy uses a stand-in that answers instantly without any AI, so every screen can be tried. Nothing is sent anywhere.

To use it for real (accounts that last, data that syncs, files in Drive, the real Ofy), connect your own Firebase project as below.

## What's kept out of this repository, and why

None of the original project's keys or settings are here, and they aren't shared. Each person who runs Octria creates their own. The files are listed in `.gitignore`; keep them there.

| What | Where it goes | Needed for | How to get it |
| --- | --- | --- | --- |
| Firebase settings for the app | `lib/firebase_options.dart` | Everything except the three try-it modes | `flutterfire configure` (step 3) |
| Firebase settings for Android | `android/app/google-services.json` | Building for Android at all | `flutterfire configure` (step 3) |
| Firebase settings for iOS or macOS, if you add them | `GoogleService-Info.plist` | Building for Apple platforms | `flutterfire configure` (step 3) |
| reCAPTCHA Enterprise site key | `dart_defines.json` (`OCTRIA_RECAPTCHA_KEY`) | Ofy on the website | Google Cloud console (step 7) |
| App Check debug token | `dart_defines.json` (`OCTRIA_APPCHECK_DEBUG_TOKEN`) | Ofy in Android builds not yet on Google Play | Firebase console (step 7) |
| GitHub sign-in client ID and secret | The Firebase console only, never a file here | Signing in with GitHub | A GitHub OAuth app (step 5) |
| Android signing key and its passwords | `key.properties` and a `.jks` file, outside git | Publishing to Google Play | `keytool` (step 8) |

`dart_defines.example.json` shows the shape of `dart_defines.json`. Copy it and fill in your own values once you have them:

```bash
cp dart_defines.example.json dart_defines.json
```

Every build command below then reads both values from it with `--dart-define-from-file=dart_defines.json`.

## Connect your own Firebase project

Besides Flutter you need [Node.js](https://nodejs.org) 20 or newer for the Firebase tools. For Android you also need the Android SDK with **SDK Platform 37** installed (the reminders library compiles against it; the app still runs on older phones).

### 1. Create a Firebase project

In the [Firebase console](https://console.firebase.google.com), create a project. Then add a **Cloud Firestore** database to it (production mode is fine: the rules in this repository decide who can do what). Your project's data is entirely separate from anyone else's.

The free Spark plan is enough for everything in this repository.

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

### 3. Generate your Firebase settings files

This creates your own `lib/firebase_options.dart` (replacing the placeholder) and `android/app/google-services.json`:

```bash
flutterfire configure --project=YOUR_PROJECT_ID
```

Pick the platforms you want, such as web and Android. It also adds a `flutter` section to `firebase.json` holding your project's IDs: delete that section before you commit, so the repository stays free of them.

### 4. Publish the security rules and indexes

```bash
firebase deploy --only firestore --project YOUR_PROJECT_ID
```

Do this before anyone signs in. Without the rules, every read and write is refused; without the indexes, some lists don't load.

### 5. Turn on sign-in

In the console under **Authentication**, enable **Email/Password** and **Google**. Under **Settings, Authorised domains**, make sure `localhost` and any domain you'll host on are listed.

For GitHub sign-in:

1. Enable GitHub in Firebase and copy the callback URL it shows.
2. On GitHub, go to Settings, Developer settings, OAuth Apps, and create an app with that callback URL.
3. Paste the app's client ID and client secret into Firebase.

The client secret stays in Firebase. Don't put it in code, in a file here or in a chat.

### 6. Turn on Google Drive for file libraries

Files people add go in their own Google Drive, through the Google sign-in Firebase already uses, asking only for the `drive.file` scope (Octria sees just the files it put there). In the [Google Cloud console](https://console.cloud.google.com/apis/library/drive.googleapis.com), pick your Firebase project and enable the **Google Drive API**.

While your app is unverified, Google shows an "unverified app" warning and only lets in the test users listed under **Google Auth Platform, Audience**. Add yourself and your testers there. No key or client ID is needed in this repository. Without the API switched on, adding a file says Google Drive isn’t switched on.

### 7. Turn on Ofy (Gemini through Firebase AI Logic)

Ofy calls Gemini through Firebase AI Logic, so no Gemini key is in the app or this repository. It runs on the free Gemini Developer API without billing.

1. In the Firebase console, open **AI Logic**, press **Get started** and choose the **Gemini Developer API**.
2. Firebase only lets Ofy answer requests that pass **App Check**, which proves they come from your copy of the app.

**For the website,** App Check uses reCAPTCHA Enterprise:

1. In the [Google Cloud console](https://console.cloud.google.com/security/recaptcha), under **Security, reCAPTCHA**, create a key of type **Website** and add your domains (for example `localhost` and `YOUR_PROJECT_ID.web.app`).
2. In the Firebase console under **App Check, Apps**, register your web app with the **reCAPTCHA Enterprise** provider and paste in that key.
3. Put the key in `dart_defines.json` as `OCTRIA_RECAPTCHA_KEY`. It's a public site key, not a password, but it's yours, so it stays out of the repository.

**For Android,** builds that aren't on Google Play yet use a debug token:

1. In the Firebase console under **App Check, Apps**, open your Android app's menu, choose **Manage debug tokens** and add one.
2. Put it in `dart_defines.json` as `OCTRIA_APPCHECK_DEBUG_TOKEN`. Keep it secret: anyone with it can pass App Check as your app.

A debug build run from your computer without a token prints one in the log (look for "debug token"); add that one instead. Once the app is on Google Play, it uses Play Integrity and needs no token.

Each person can ask Ofy 40 times a day, enforced by the security rules. The model is `gemini-3.5-flash-lite`; to change it, add `--dart-define=OCTRIA_AI_MODEL=...` to a build.

### 8. Android: sign-in and signing

Google sign-in on Android only works for apps whose signing fingerprints Firebase knows. Show the fingerprints of Flutter's debug key:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Add both the SHA-1 and SHA-256 to your Android app in the Firebase project settings, then download `google-services.json` again (or rerun step 3).

To publish on Google Play, create your own release key, keep it and its passwords outside git, and back them up; lose it and you can't update your app. Add its fingerprints too, and [set up release signing](https://docs.flutter.dev/deployment/android#sign-the-app):

```bash
keytool -genkey -v -keystore ~/octria-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias octria
```

### 9. Run, build and host

Run it on your own project:

```bash
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

Build the website and host it on Firebase. `OCTRIA_APP_URL` makes invite links point at your site rather than the original one:

```bash
flutter build web --no-web-resources-cdn --dart-define-from-file=dart_defines.json --dart-define=OCTRIA_APP_URL=https://YOUR_PROJECT_ID.web.app
```

```bash
firebase deploy --only hosting --project YOUR_PROJECT_ID
```

Build the Android app:

```bash
flutter build apk --release --dart-define-from-file=dart_defines.json
```

### Check it works

| You see | It means |
| --- | --- |
| The sample plans instead of a sign-in screen | `lib/firebase_options.dart` is still the placeholder: rerun step 3 |
| "You don’t have permission to do that", or empty lists, after signing in | The rules or indexes weren't published: rerun step 4 |
| Google sign-in fails on Android | The SHA fingerprints are missing: step 8 |
| "Google Drive isn’t switched on for Octria yet" when adding a file | The Google Drive API isn't enabled: step 6 |
| "Ofy isn’t switched on for this Octria yet" | AI Logic isn't set up: step 7.1 |
| "This device isn’t verified for Ofy yet (App Check)" | The site key or debug token is missing or not registered: step 7 |
| "Ofy is busy right now" | The free Gemini quota is used up for the minute; wait and try again |

### If something leaks

- **A GitHub client secret, App Check debug token, signing password or service account key:** treat it as stolen. Replace it straight away, because deleting it from git doesn't undo the leak.
- **Firebase settings for the app:** these aren't passwords. Every visitor's browser receives them to talk to Firebase, so they can't be hidden in a published app. What protects your data is `firestore.rules`. Also restrict the API key to your app and site in the Google Cloud console.

## Test

```bash
flutter test
```

The security rules are tested on the Firestore emulator, which needs Java 21 or newer:

```bash
cd tool/rules_test && npm install && npm test
```

## Where things are

| Folder | What's in it |
| --- | --- |
| `lib/graph` | Flowspace: layout, drawing, camera and gestures |
| `lib/screens` | Every screen and sheet |
| `lib/ai` | Ofy's model layer: prompts, the offline stand-in, scheduling, re-planning, splitting work |
| `lib/ofy` | Ofy's chat, on-screen guides and actions |
| `lib/data` | The backend interface, its Firebase and in-memory versions, and the data models |
| `lib/kanvas` | Kanvas boards |
| `lib/model` | The plan model, calendar files and reminders |
| `lib/platform` | Web and phone differences: badges, reminders, saving files, pictures |
| `firestore.rules` | Who can read and change what |
| `test`, `tool/rules_test` | App tests and security rule tests |

## More

- [Product](PRODUCT.md): who it's for and what's in scope
- [Design system](DESIGN.md): the glass look, colours and rules
- [Planning document](docs/Octria_Planning_Document.pdf): features, data model and build phases
