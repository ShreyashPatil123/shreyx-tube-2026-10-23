# ShreyX Tube

An Android video application built with Flutter, Provider and native AndroidX Media3, with local personalization and transcript-based study tools.

## Publication and provenance

This repository was first published on **23 October 2026** as a clean snapshot of an existing project. Development predates this publication. Its single initial commit records publication, **not the original authorship or development dates of every file**. Earlier history remains in the [original repository](https://github.com/ShreyashPatil123/shreyx-tube), which was not modified. The snapshot includes current working code and previously uncommitted improvements. See [PUBLICATION.md](PUBLICATION.md).

## Features and architecture

- Flutter/Provider UI with native Kotlin Media3 playback, fullscreen/gestures, background playback and a floating mini-player.
- Home/search, Shorts, channel pages, local profile/preferences, history, playlists and downloads.
- Android sharing and supported YouTube links, subject to Android defaults and domain-verification rules.
- Transcript study tools: summaries, questions, supporting excerpts, reliable cue-time navigation, editable saved notes, search, copy/export and privacy controls.

Open **You > Video intelligence** or **Understand** on a watch page. Select a supported video and import an authorized transcript or supported caption track. The default engine extracts and searches source text; it is **not generative AI**. The original sample demo works offline and is explicitly labelled. Plain text receives no invented timestamps, and unavailable content receives no fabricated transcript.

Optional Gemini processing uses a separately operated authenticated HTTPS gateway, saved consent and a separate workbench switch. Only the selected transcript, title/ID and current question are sent, excluding YouTube cookies and history. Review generated statements against their excerpts. **No live Gemini deployment is included or claimed.**

Source layout: `lib/` application and study tools; `android/` native player/integration; `test/` Flutter tests; `integration_test/` device journeys; `server/` optional dependency-free Node gateway. SQLite/SharedPreferences retain local data, and Android secure storage protects session/gateway tokens. Existing playback/account systems were preserved, not rebuilt.

## Requirements and setup

- Flutter 3.47.5 / Dart 3.13.4 (CI pins Flutter 3.47.5; SDK constraints require Dart 3.13+).
- Android SDK platform 36, a compatible JDK and Android Studio/toolchain.
- Android 7.0/API 24 or later on the device.
- Node.js 22+ only for the optional gateway.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Build an ARM64 APK:

```sh
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Run Flutter commands sequentially in a checkout. When switching from integration/debug builds to release, use the normal release command without `--no-pub` so Flutter regenerates the release plugin registrant. Do not edit generated Java or force test plugins into production.

The existing release configuration uses a local **development signing certificate**. Keystores, passwords, machine-specific `local.properties` and builds are excluded. Configure managed production signing before store distribution. A fresh workstation generates its own development certificate and cannot automatically update an installation signed by a different certificate.

## Optional configuration and privacy

Guest/local study features need no sign-in. Account-related features have separate setup requirements; `oauth_config.example.json` is an empty template, not a credential. Browser sign-in cannot simply transfer another browser's private session. Account synchronization and playback availability are not guaranteed.

For external analysis, configure the server's `GEMINI_API_KEY` and private per-user `AI_ACCESS_TOKENS` outside version control. The Android app receives a **gateway token**, never the provider key. See [server/README.md](server/README.md) for TLS, limits, terms and deployment. No provider key, cloud project, billing or subscription is supplied.

Playback, searches and caption loading contact YouTube. Preferences/history and explicitly saved study text use app-private storage; study text has no extra database encryption. Existing Android backup exclusions apply. Incognito hides saved materials and disables saving/external AI. Privacy controls delete notes/responses or viewing history; full reset includes AI settings and account state.

The gateway never fetches user URLs, executes model tools or retains transcript/response history. Hosting providers and Google still process requests. Unpaid Gemini terms may permit product improvement and human review; do not submit sensitive text. [Terms](https://ai.google.dev/gemini-api/terms), [pricing](https://ai.google.dev/gemini-api/docs/pricing) and [quotas](https://ai.google.dev/gemini-api/docs/rate-limits) vary; free access is not unlimited.

Current gateway counters are memory-only and require one replica. Public deployment needs private token enrollment/rotation, ingress protection, persistent shared quotas when applicable and verified hosting/provider eligibility. Live Gemini, a public backend and all-device reliability remain unverified. Existing third-party playback/extraction behavior is preserved; respect content rights and platform access requirements.

## Tests and validation

The [Tests workflow](.github/workflows/ci.yml) runs on every push and pull request,
and can also be started manually. It uses Flutter 3.47.5, Node.js 22, JDK 21 and
Gradle 9.3.1, resolves the committed dependency lockfile, runs analysis, all Flutter
unit/widget tests with coverage, the Node server tests, and the Android JVM unit-test
task. It uploads `coverage/lcov.info` as the `flutter-coverage` artifact (7-day
retention). Actions are pinned to commit SHAs, checkout credentials are not retained,
and the workflow token has read-only repository access. No deployment runs in CI.

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --coverage
npm --prefix server test
# Requires JDK 21, Gradle 9.3.1, Android SDK 36 and local.properties:
gradle --no-daemon --console=plain -p android :app:testDebugUnitTest
```

Automated AI tests inject synthetic responses/HTTP clients. They cover the
sample-transcript study journey, notes/save/reset, missing content, malformed or
unsubstantiated AI output, provider failures/quotas, cancellation and privacy changes.
No API keys, paid APIs or live Gemini calls are required. Dependencies still need
normal package downloads. No new journey tests were needed for this CI change.

Local verification on **2026-10-23**: locked dependency resolution succeeded;
Flutter analysis reported no issues; **293 Flutter tests passed** with an LCOV
report generated; **16 Node tests passed on Node.js 22.23.4**; and the Android
Gradle task completed successfully. `:app:testDebugUnitTest` reported **NO-SOURCE**:
this project currently has Android instrumentation tests, but no app-level JVM unit
test sources. That task success is not a claim that device tests ran. The workflow
also passed local `actionlint` validation; a hosted GitHub Actions run remains
unverified until these changes are pushed. No coverage percentage is claimed.

Device integration/instrumentation tests are separate and require an owned device
or emulator; they are not part of this workflow and were not rerun for the CI change:

```sh
flutter test integration_test/tube_intelligence_flow_test.dart -d emulator-5554
# With an owned emulator connected and Gradle/SDK configured:
gradle --no-daemon -p android :app:connectedDebugAndroidTest
```

Before publication, the project passed 293 Flutter tests, 16 gateway tests with a mocked provider, 18 native Android tests and the Android study journey. Production APKs built and the x86_64 release passed an Android 16/API 36 sample-summary smoke test. The clean publication copy is checked separately before pushing; [PUBLICATION.md](PUBLICATION.md) records results. Tests do not establish live Gemini operation or factual accuracy for every generated answer.

## Attribution

Existing project author: **Shreyash Patil / ShreyX Studio**. This snapshot does not create a new license grant or change dependency licenses. No API keys, private credentials, environment files, runtime account data, caches or compiled application artifacts are intentionally included.
