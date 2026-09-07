# ShadowSwords

Android app that opens the [ShadowSwords game library](https://shadow-1.tail51f9d6.ts.net/) (self-hosted on the tailnet)
in a fullscreen WebView.

- Immersive fullscreen (status/nav bars hidden)
- Branded splash screen
- Keeps the screen awake while a game is running; unlocks rotation for games (portrait-locked while browsing)
- External links (Movies/Jellyfin, Discord, YouTube) open in your browser
- Long-press the icon for shortcuts: Play · Surprise me · Movies · Search
- Tells you when a new APK is on GitHub
- Loading bar, offline "Retry" screen
- Back navigates web history, then double-press to exit

## Install

Grab the latest `ShadowSwords-*.apk` from [Releases](../../releases) and sideload it
(enable "Install unknown apps" for your browser / file manager).

## Build from source

```
flutter pub get
flutter run                 # debug, on a connected device/emulator
flutter build apk --release # -> build/app/outputs/flutter-apk/app-release.apk
```

Release signing reads `android/key.properties` (not committed); without it the
release build falls back to debug signing.

The site URL lives in `lib/main.dart` as `kSiteUrl`.
