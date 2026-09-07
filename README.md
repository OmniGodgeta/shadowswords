# ShadowSwords

Android app that opens the [ShadowSwords game library](https://omnigodgeta.github.io/shadowswords-gamelib/)
in a fullscreen WebView.

- Immersive fullscreen (status/nav bars hidden)
- Loading bar, pull-to-refresh
- Offline "Retry" screen
- Back button navigates web history, then double-press to exit

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
