
## App updater handoff (2026-09-11)

The updater downloads the latest GitHub release APK and invokes Android package installation. It now retains the downloaded APK path when Android requests unknown-app installation permission and retries when the app resumes. Release APKs must use the same production keystore as the installed app; a debug-signed APK cannot be updated by a release-signed APK. Netplay browser controls are fixed in `shadowswords-gamelib` commit `a8aac2f` plus the follow-up browser visibility fix.
