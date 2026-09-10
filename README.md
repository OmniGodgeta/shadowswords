# RetroVerse

*(repo & package id stay `shadowswords`; the app is branded **RetroVerse**.)*

Android app that opens the [RetroVerse game library](https://shadow-1.tail51f9d6.ts.net/) (self-hosted on the tailnet)
in a fullscreen WebView.

- Immersive fullscreen (status/nav bars hidden)
- Branded splash screen
- Keeps the screen awake during games; unlocks rotation for games (portrait for browsing)
- Music keeps playing in the background, with real lock-screen / Bluetooth / car controls (title, artist, album, art, prev/play/next/seek)
- External links (Movies/Jellyfin, Discord, YouTube) open in your browser
- **Settings**: library URL, Wake-on-LAN, keep-screen-on, haptics, clear cache, update check
- **Wake-on-LAN** — wakes the home server on launch / Retry (home Wi-Fi only)
- Auto-retries when the network comes back; error screen has Retry / Tailscale / Settings
- Open a ROM file ("Open with" / share sheet)
- Deep links: `shadowswords://play`, `shadowswords://play/random`, `shadowswords://movies`
- Home-screen widget (Play / Surprise me / Movies)
- Long-press the icon: Play / Surprise me / Movies / Settings
- Update notice when a new APK is on GitHub
- Bluetooth controllers work (menu + in-game)

**Gestures:** two-finger long-press = Settings · three-finger tap = screenshot to Pictures/RetroVerse



## Install

Grab the latest `RetroVerse-*.apk` from [Releases](../../releases) and sideload it
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
