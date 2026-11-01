# Platform Checklists

Status: Draft v0.1
Last updated: 2026-10-31
Related: [`platforms.md`](platforms.md), [`testing-ci.md`](testing-ci.md)

Manual checks for platform integration. Record the date, device/OS, build, and result for each run.
`Pending` means not executed; implementation does not imply verification. Current automated baseline:
`flutter analyze` clean, 269 passed, 2 native skips (without DLLs).

## Android

| ID | Check | Expected | Result |
|---|---|---|---|
| A1 | Fresh install, connect, albums, slideshow | Setup completes and slideshow plays | Pending |
| A2 | Night mode brightness | Window brightness is `1 - dimOpacity`; overlay dims, slideshow pauses, overlays hide; brightness restores when night mode ends and when the slideshow closes | Pending; unit/widget tested |
| A3 | Biometric media selection | Prompt when a device lock exists; fail-open without a lock | Pending |
| A4 | API-key reveal/copy gate | Prompt before reveal/copy; cancel leaves the key hidden/uncopied | Pending; widget tested |
| A5 | HOME role | App is selectable as home and opens the slideshow | Pending; manifest only, Home app row opens system settings |
| A6 | Start on boot | Reboot with `start_on_boot=true` and battery optimization exempt launches the app | **Fail** on Xiaomi/MIUI Android 12. Log: `BroadcastQueueInjector: Unable to launch app com.rincew1nd.photoframe/10006 for broadcast ... BOOT_COMPLETED: process is not permitted to auto start`. MIUI autostart permission is required; shell broadcasts are blocked on this non-rooted device. Battery optimization is also not exempt, so start-on-boot is disabled. Code/prefs verified. |
| A7 | Split APK packaging | `scripts/package-android.sh` produces split release APKs and `sha256sums.txt` | Verified; arm64 release APK installed and launched (hash in recorded results) |
| A8 | Release signing | APK uses a release key, not the debug key | Blocked; release builds use debug signing |
| A9 | WebView baseline | Supported WebView enables plugins; old WebView disables plugins (and therefore all overlays) with a message | Blocked; Phase 4 not started |
| A10 | Audio focus | Video/Live Photo audio takes and releases focus correctly; transient loss pauses and gain resumes | Implemented; unit/widget tested; on-device verification pending |
| A11 | Battery optimization exemption | Status loads and refreshes on resume; **Grant** requests the exemption; start-on-boot is disabled until exempt and auto-disabled when absent | Partial; UI/gating verified, device **not exempt** |
| A12 | OEM autostart settings | **Open** launches the OEM autostart settings; permission can be granted there | Partial; UI present, MIUI permission still required |
| A13 | Home app selection | **Open** launches the system Home app settings; Photo Frame can be selected as home | Partial; UI present, selection not verified |

After granting the battery-optimization exemption and the MIUI autostart permission, repeat A6 and
record the result. Do not treat the current boot test as a pass.

## Windows

| ID | Check | Expected | Result |
|---|---|---|---|
| W1 | Release build and ZIP | `scripts/package-windows.sh` writes `dist/photo-frame-windows-x64.zip` | Verified; latest ZIP is `dist/photo-frame-windows-x64.zip` (36,767,671 bytes) and the release build launches |
| W2 | Run-key autostart | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` contains `PhotoFrame`; sign-in starts the app | Pending; entry implemented, sign-in not verified |
| W3 | Kiosk controls | Fullscreen, always-on-top, skip taskbar, no resize/move/minimize/maximize, cursor hidden | Implemented with Win32 `WS_POPUP` fullscreen, monitor bounds, native foreground focus, and topmost kiosk handling. Launch verified; a manual Win32 check hid the taskbar. Final app-level taskbar/cursor check pending. |
| W4 | Kiosk gaps | Close/alt-tab suppressed; configured monitor used | Pending; not implemented |
| W5 | Keep-awake | System and display stay awake while the frame is active | Pending |
| W6 | Second instance | A second launch focuses the existing window | Pending |
| W7 | DPI/scaling | Layout is correct at 125%, 150%, and 200% scaling | Pending |
| W8 | Update flow | Check, download, and install/open a release | Blocked; no release channel or keystore |

## Linux

| ID | Check | Expected | Result |
|---|---|---|---|
| L1 | Release build and tar.gz | `scripts/package-linux.sh` writes `dist/photo-frame-linux-x64.tar.gz` | Pending; no Linux host available |
| L2 | XDG autostart | `.desktop` entry starts the app at login | Pending; no Linux host available |
| L3 | Kiosk/fullscreen | `window_manager` kiosk and fullscreen behave correctly on X11 | Pending; no Linux host available |
| L4 | Sleep inhibit | `systemd-inhibit sleep:idle` blocks idle sleep; `wakelock_plus` fallback works when unavailable | Pending; no Linux host available |
| L5 | Second instance | A second launch focuses the existing window | Pending; no Linux host available |
| L6 | Night overlay | Overlay dims, slideshow pauses, overlays hide | Pending; no Linux host available |
| L7 | X11/Wayland | Record compositor/version and behavior | Pending; Wayland unvalidated |
| L8 | AppImage/.deb | Packages build and launch | Not implemented |
| L9 | Update flow | Check, download, and install/open a release | Blocked; no release channel or keystore |

## Recorded results

| Date | Platform | Device/OS | Build | Check | Result |
|---|---|---|---|---|---|
| 2026-10-31 | Android | Xiaomi/MIUI, Android 12 | Debug APK | Permissions and launch | All declared permissions (`WAKE_LOCK`, `USE_BIOMETRIC`, `USE_FINGERPRINT`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `RECEIVE_BOOT_COMPLETED`) granted at install per `dumpsys`; no runtime permissions requested. Android debug APK builds and MainActivity is resumed. Battery optimization is **not exempt**. |
| 2026-10-31 | Android | Xiaomi/MIUI, Android 12 | Local build | A6 | Fail: `BOOT_COMPLETED` did not launch the app; MIUI autostart permission required. Code/prefs verified; shell broadcasts blocked. |
| 2026-10-31 | Android | Xiaomi/MIUI, Android 12 | Release arm64 APK | A7 + launch | `dist/photo-frame-android/app-arm64-v8a-release.apk` (35,950,837 bytes, SHA-256 `ABB3A20EFD63127CC98C73A9860ABCBA48395534AF6D090E3C4C4D37DC7DA3E0`) installed and launched successfully; all five declared permissions remained granted. |
| 2026-10-31 | Windows | Windows 10/11 x64 | Local release build | W1 + W3 | Latest release ZIP is `dist/photo-frame-windows-x64.zip` (36,767,671 bytes). `kiosk=true`/`fullscreen=true` launches stay alive after the `waitUntilReadyToShow()` fix. Fullscreen now uses a Win32 popup style with monitor bounds and native focus; a manual Win32 check hid the taskbar. Final app-level taskbar/cursor confirmation pending. |
