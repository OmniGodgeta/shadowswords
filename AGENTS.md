
## Mic permission race + Live TV VLC intent bug (2026-09-16, v1.6.11)

Two bugs found from owner reports the same day as v1.6.10.

- **Mic permission race**: owner's exact words were the tell — "I see the
  popup, I allow every time, and then it tells me permissions denied."
  `MainActivity.kt`'s native `requestMic` method has two independent call
  sites (the WebView's own `onPlatformPermissionRequest`, triggered by
  `getUserMedia()`; and a fire-and-forget `SSNotify{mic:true}` ping the site
  sends to nudge the OS dialog open early) sharing one `pendingMicResult`
  slot with no queueing — whichever call registered second resolved the
  *first* with `success(false)` before the user had answered anything, so
  the dialog the user actually saw and allowed belonged to whichever call
  registered last, while the call that actually decided `request.grant()`/
  `deny()` was often already dead. Fixed: queue every pending result
  (`pendingMicResults: MutableList<MethodChannel.Result>`), resolve all of
  them with the real answer once the user actually responds. `flutter build
  apk --release` compiles clean; **not yet confirmed fixed on a real
  device** — next session should verify, not just trust the race theory.
- **Live TV: VLC said "Multiple media cannot be played"**: `_openLiveTv`
  built `Uri.parse('vlc://$url')` — literally prefixing `vlc://` onto the
  channel's own `https://` URL, a malformed nested URI. Fixed: just call the
  existing `_openExternal(url)` helper (same one every other external link
  on the site uses) with the raw stream URL; Android's app-chooser routes it
  to VLC correctly without any scheme trickery.

`pubspec.yaml` → `1.6.11+22`.

## Watch-party video wouldn't play in WebView (2026-09-16, v1.6.10)

Owner: pressed Watch on Android, saw a blank/placeholder player instead of the
host's stream (screenshot showed the native unstarted-`<video>` icon).

- Android WebView's documented default is `mediaPlaybackRequiresUserGesture =
  true` — it blocks **all** `<video>` playback, muted/autoplay included, until
  a user gesture. `main.dart` never called the setter, so the default stood.
  Netplay's own in-game video (`#np-video`) gets away with it because the user
  has already tapped through several screens by the time it needs to
  autoplay; the watch page's video is populated asynchronously off a WebRTC
  track event, which the WebView doesn't count as a gesture.
- Fix: `AndroidWebViewController.setMediaPlaybackRequiresUserGesture(false)`
  in `_initWebView()`, next to the existing mic-permission handler (same
  `if (platform is AndroidWebViewController)` block). `webview_flutter_android`
  exposes it (`lib/src/android_webview_controller.dart`); confirmed via
  `flutter analyze` only — **not yet verified on a real device**.
- Companion site fix (same session, `shadowswords-gamelib` 3.17): the watch
  page's own JS had a fallback-display bug that meant even a failed stream
  showed nothing recoverable. See that repo's `AGENT-MEMORY.md` 2026-09-16
  entry for the full diagnosis — this app-side fix alone may not be sufficient
  without it.
- `pubspec.yaml` → `1.6.10+21`.

## Party calls — foreground service + overlay bubble (2026-09-13, v1.6.7)

Owner asked for Discord-like party calls that survive leaving the app, with a
floating bubble over other apps. Also see the **netplay invite fixes (v1.6.9)**
at the bottom of this section: cold-start invites and URL-encoded join links.

- **Site (game library ≥3.0)** runs the call: room on `arcade-server.mjs`
  (`/party*`) + a WebRTC mesh in `PARTY` (`docs/assets/app.js`). It tells the
  app through `SSNotify` and exposes `window.__sswPartyAction`.
- **`SSNotify` contract** now also carries `{party:boolean, muted:boolean}` (in
  addition to `{cid,origin,on,mic}`). `party:true` → start `PartyService`;
  `party:false` → stop. Only sent for transmitting members (`!PARTY.watcher`),
  because an Android 14 microphone-type FGS is rejected when the mic isn't in
  use. Do not send `party:true` for listeners.
- **`PartyService.kt`**: foreground service (type `microphone`) + a draggable
  `TYPE_APPLICATION_OVERLAY` bubble (long-press mutes). `actionSink` sends
  `"mute"|"unmute"|"leave"` back to Dart, which calls `window.__sswPartyAction`.
- **`MainActivity.kt`**: methods `partyStart {muted}`, `partyStop`, `partyMute`,
  `canOverlay`, `requestOverlay`; forwards `partyAction` to Dart.
- Manifest adds `FOREGROUND_SERVICE_MICROPHONE` + `SYSTEM_ALERT_WINDOW` and the
  `<service android:name=".PartyService" ... foregroundServiceType="microphone">`.
- **Limitation**: the call engine is still the Activity's WebView. While a party
  is active, the back button backgrounds the app (`backgroundApp` →
  `moveTaskToBack`) instead of exiting, so the call + bubble survive; swiping the
  app away still ends it. To finish true persistence after swipe-away, host the
  call in a headless WebView owned by the service and hand it over on
  background. Tracked in `shadowswords-gamelib/FEATURE-BACKLOG.md` §A.
- **Microphone handshake**: the WebView permission handler now waits for the
  native `RECORD_AUDIO` result and dispatches `ssw-mic` `{granted}` so the site
  stops retrying. `npGetMic()` retries while the dialog is open.

## Netplay invite fixes (2026-09-13, v1.6.9)

- **Cold-start join**: `MainActivity.configureFlutterEngine` now reads the launch
  `joinUrl` extra and forwards it to Dart, because `onNewIntent` is not called
  when Android starts the process from the notification. Dart stores it in
  `_pendingInviteUrl` and loads it after the first page finishes.
- **Join URL encoding**: `startInviteWatch` URL-encodes each `sys`/`file`
  segment (ROM names have spaces/brackets/sub-dirs).
- Netplay **lag** is mostly decided by the site (`npMode`, default input/state
  sync). Android should rarely need changes for that.

## Native netplay invite notifications (2026-09-12)

## Android reliability handoff (2026-09-13)

- WebView microphone requests now wait for the native `RECORD_AUDIO` runtime
  result before calling `grant()`. This avoids the prior race where Android
  showed approval but WebView still received a denied capture request.
- Returning from the package installer or Settings rechecks GitHub Releases,
  and the updater always resolves the latest release asset rather than
  stepping through intermediate versions. Release APK for this change is
  `v1.6.6`; keep production signing consistent with `android/key.properties`.

The WebView is throttled while the app is backgrounded, so the site's 3 s
`/play/invites` poll misses invites. Fix: the site posts its presence id to the
app's `SSNotify` JS channel (`notifyApp()` in the site's `app.js`); Dart stores
it and, **only while backgrounded**, tells Kotlin to poll.

- `lib/main.dart`: `SSNotify` channel handler → `_notifyCid/_notifyOrigin/_notifyOn`;
  `_syncInviteWatch()` starts/stops the native watch from
  `didChangeAppLifecycleState` (plus when the site (re)registers). Native method
  `openInvite` loads the join URL in the WebView.
- `MainActivity.kt`: `startInviteWatch(cid, origin)` polls
  `<origin>/play/invites?cid=` every 25 s on a background thread and, on a new
  invite, posts a high-priority notification on channel `retroverse_invites`.
  Tapping it launches MainActivity with a `joinUrl` extra → `onNewIntent` →
  `_native.invokeMethod("openInvite", url)`.
- Contract: the `SSNotify` payload is `{cid, origin, on}`; `/play/invites`
  returns `{invites:[{id,fromName,name,room,sys,file}]}`. Changing either means
  changing both repos.
- **Needs an APK build** (Dart/Kotlin changed). Android 13+ requires the
  `POST_NOTIFICATIONS` runtime grant (declared in the manifest) or notifications
  are silently dropped. Only polls while the process is alive in the background —
  a killed app gets nothing (that would need FCM).

## Native netplay voice permission (2026-09-12)

Android WebView does not automatically approve `getUserMedia()`. The wrapper
therefore declares `RECORD_AUDIO`, handles the WebView platform permission
request in Dart, and asks Android for the runtime microphone grant when the
site sends `SSNotify` with `{mic:true}`. The site retries its mic request after
that prompt. Keep this bridge in sync with `npGetMic()` in the game library.

---

## App updater handoff (2026-09-11)

The updater downloads the latest GitHub release APK and invokes Android package installation. It now retains the downloaded APK path when Android requests unknown-app installation permission and retries when the app resumes. Release APKs must use the same production keystore as the installed app; a debug-signed APK cannot be updated by a release-signed APK. Netplay browser controls are fixed in `shadowswords-gamelib` commit `a8aac2f` plus the follow-up browser visibility fix.

---

## App Updater Fix Summary (2026-09-11)

**Problem:** Tapping "Install" when an update is available appears to do nothing.

**Root causes:**

1. **Two-step permission flow is invisible:**
   - User taps Install → Android requires "Install unknown apps" permission → settings page opens
   - App returns "needPermission" from native code, banner shows "Allow in Settings"
   - User grants permission in Settings, presses back
   - **App does nothing — the user must manually tap Install again**

2. **Installer failures are hidden behind generic message:**
   - FileProvider URI creation fails → silently caught
   - startActivity(intent) fails → silently caught
   - Banner always says "Couldn't download" even if the problem is the package installer

**Fixes applied:**

1. **Retain APK path** (`_pendingUpdatePath` field):
   - Store the downloaded APK file path when installation is initiated
   - Don't delete the file even if permission is denied

2. **Resume on app resume:**
   - Hook `didChangeAppLifecycleState(AppLifecycleState.resumed)`
   - If there's a pending APK path and we're not already busy, retry `installApk()`
   - User grants permission in Settings → taps back → app automatically resumes install

3. **Structured error codes from native:**
   - Kotlin's `installApk()` now returns:
     - `"ok"` → success
     - `"needPermission"` → permission required (as before)
     - `"missing"` → file not found
     - `"provider: FileNotFoundException"` → FileProvider failed
     - `"installer: ActivityNotFoundException"` → no package installer
     - `"installer: SecurityException"` → other security error
   - Dart handles these and displays specific errors (not generic "couldn't download")

**Files changed:**

- `lib/main.dart`: Added `_pendingUpdatePath`, `_resumePendingUpdate()`, and lifecycle hook
- `android/app/src/main/kotlin/com/shadowswords/shadowswords/MainActivity.kt`: Structured error codes with try-catch

**Testing:**

On an Android device:

```bash
# 1. Build and install debug APK
flutter build apk --debug
adb install -r build/app/outputs/apk/debug/app-debug.apk

# 2. Settings → Apps → RetroVerse → Permissions → Install unknown apps → OFF

# 3. In-app: Settings → Check for app updates → Install
#    → Banner shows "Allow RetroVerse to install updates, then tap Install again"

# 4. Tap notification or go to Android Settings → Apps → Special app access → Install unknown apps
#    → Toggle RetroVerse ON

# 5. Return to app (press back or switch apps)
#    → App should automatically resume install without another tap
#    → Banner updates to "Downloading 100%" → "Opening installer…"

# 6. Package installer opens; approve the update
```

**Known limitation:**

The APK file remains in `/data/local/tmp/` (temp dir) until it is installed or the app is uninstalled. This is acceptable; temp files are normal and are eventually cleaned up by the OS.

**Not yet addressed (for next agent):**

- Release keystore signing: the build can silently fall back to debug key if `android/key.properties` is missing. This makes release APKs uninstallable on devices with the previous key. The next agent should either:
  - Fail the release build with a clear error if the keystore is missing
  - Or document the requirement prominently and include setup instructions in the README
- Logcat integration: installer errors are currently only visible in-app. For debugging on real devices, run `adb logcat | grep -Ei 'PackageInstaller|RetroVerse|shadowswords'`

All changes committed and pushed as of 2026-09-11.
