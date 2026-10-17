# Daily Thesis

![Banner](/assets/social_banner.png)

A Flutter app that delivers one relevant research paper a day, picked to match your interests.

On first launch you pick the subjects you care about (Computer Science, Medicine, Biology, Physics, and more). From then on, the app surfaces a matching paper each day — sourced from arXiv and OpenAlex via a Cloudflare Worker backend — with the abstract, a link to the full paper, and tools like citation copying and reading history.

The app is free to use, supported by AdMob ads.

## Tech stack

- **Flutter / Dart** — see `pubspec.yaml` for exact SDK and package versions
- **Backend**: a Cloudflare Worker that queries arXiv and OpenAlex and returns matched papers
- **Local storage and personalization**: `shared_preferences` stores the user profile, subjects, reading history, and the on-device recommendation events used by the local ranker — no account or server-side user data
- **Ads**: `google_mobile_ads` (AdMob), configured via `.env` (see Setup below)

Ads currently run on Android/iOS only; the app also builds for web and desktop via Flutter's standard multi-platform support.

## Getting started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed and on your `PATH`
- An emulator, simulator, or physical device (`flutter devices` to check what's available)

### Setup

1. Install dependencies:
   ```bash
   flutter pub get
   ```

2. Create a `.env` file in the project root (see `.env.example` for the exact keys needed) with your AdMob credentials. The App ID also needs to be set as `com.google.android.gms.ads.APPLICATION_ID` in `android/app/src/main/AndroidManifest.xml` — that value is baked in at build time and can't be read from `.env`.

   While developing, use [Google's official test ad unit IDs](https://developers.google.com/admob/android/test-ads) instead of real ones to avoid triggering invalid traffic on your AdMob account.

3. Run it:
   ```bash
   flutter run
   ```

### Building a release APK
```bash
flutter build apk --release
```
Output lands at `build/app/outputs/flutter-apk/app-release.apk`.

## Project layout

Code follows a standard Flutter convention:
- `lib/screens/` — one file per app screen (onboarding, main paper view, history, settings)
- `lib/services/` — data fetching and local persistence (papers, user profile, ad loading, etc.)
- `lib/widgets/` — reusable UI pieces shared across screens
- `lib/models/` — data classes

The recommendation flow fetches a candidate pool from the Worker, ranks it
locally using explicit interests plus learned likes and dismissals, and keeps
those learning events on the device. The model is intentionally small and
explainable so it can personalize without uploading reading behavior.

For what's actually in each folder today, just look — this list is deliberately not itemized further so it doesn't go stale as files get added.

## Notes for contributors

- `.env` is gitignored — never commit real AdMob IDs. Use `.env.example` as the template.
- Android signing keys (`key.properties`, `*.jks`/`*.keystore`) are also gitignored; keep them out of version control.
  