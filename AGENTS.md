
## Native netplay invite notifications (2026-09-12)

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
