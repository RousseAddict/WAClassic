# WA Classic for iOS 12 (arm64)

An unofficial **arm64 / iOS 12** build of the WA Classic app, for a **jailbroken iPhone 5s** or newer. The official app is 32-bit only (iOS 4–6).

**Based on [WA Classic by aronsz26](https://github.com/aronsz26/WAClassic), modified.** This is not the official WA Classic and is not made or supported by its author. GPLv3 with attribution terms, see [LICENSE](../../LICENSE) and [NOTICE](../../NOTICE).

The app's code in `app/` is **not modified**. `build.sh` compiles it for a new target, adds one small file and repackages it.

## Status on an iPhone 5s (iOS 12.5.8)

Tested with the 1.0.4.1 build on 2026-11-20. The 1.0.5 build (2026-11-21) is not tested on the phone yet.

| Test | Result |
|---|---|
| Install the `.deb`, open the app | ✅ |
| Connect to the bridge (address + setup code) | ✅ |
| Echo test call (`/api/debug/call`): rings, voice comes back | ✅ |
| Messages | Not tested yet |
| Real WhatsApp calls, both directions | Not tested yet |
| Ringing while the phone is locked | Not tested yet |

## What the build changes

| Change | Why |
|---|---|
| Compiled for `arm64-apple-ios12.0` with Xcode 13.2.1 / iOS SDK 15.2, same flags as `tools/package-app.sh` | The 5s and newer need arm64. The link line drops the iOS 6 workarounds (`-flat_namespace`, `-U` for the NSURL classes). |
| Adds `WAiOS12Compat.m` | iOS 8+ shows notifications only after the app calls `registerUserNotificationSettings:`, which doesn't exist on iOS 4–6. Without it, incoming calls and messages would be silent. |
| Binary stamped as **built with SDK 9.3** (`vtool`) | iOS keeps the legacy VoIP background mode, which WA Classic uses to ring, only for apps linked against an SDK older than iOS 10 ([Apple QA1938](https://developer.apple.com/library/archive/qa/qa1938/_index.html)). `LINKED_SDK=` keeps the real stamp, for comparison. |
| Ad-hoc `codesign` with `platform-application` and `no-container` entitlements | The jailbreak equivalent of `package-app.sh`'s `ldid -S`. |
| `Info.plist`: `MinimumOSVersion` 12.0, `arm64` capability, 120 px icon | iOS 12 refuses the iOS 4 values and has no icon size for iOS 7+. |
| Package `com.aronsz26.wa4s-ios12`, installs to `/Applications/WA4S.app` | Conflicts with and replaces the official packages, so only one copy is installed. |

## Building

Needs:
- **A build Mac** with **Xcode 13.2.1** (iOS SDK 15.2), reachable over SSH with a password.
- **This Mac:** the Command Line Tools, `sshpass` and `rsync`.

Create `.env.local` at the repo root (git-ignored), then run the script:
```sh
cat > .env.local <<'EOF'
BUILD_HOST=user@build-mac
BUILD_PASS=...
EOF
chmod 600 .env.local

tools/ios12/build.sh                 # → packages/com.aronsz26.wa4s-ios12_<version>+ios12.1_iphoneos-arm.deb
LINKED_SDK= tools/ios12/build.sh     # without the SDK 9.3 stamp
```
The script stops if `app/` differs from the commit that was security-reviewed (`bb21206`, v1.0.5). After reviewing newer code, rerun with `ALLOW_UNREVIEWED=1`.

## Installing

- **Filza:** open the `.deb`, then *Install*.
- **SSH:** `dpkg -i <deb>`.
- **From the bridge:** copy the `.deb` into the bridge's debs folder (`/usr/share/wa-classic/debs` in the container). Then add `http://<bridge>:8097/repo/` as a source in Sileo.

Don't add the official Cydia source, and ignore the app's update prompts: they point to the 32-bit package.

**Uninstall:** `apt remove com.aronsz26.wa4s-ios12`, or use Sileo. The app's data in `/var/mobile/Library/WA4S` is kept.

## Echo test call

The bridge image has no `curl`, so trigger the test call from inside the container with bash:
```sh
podman exec wa-classic bash -c 'exec 3<>/dev/tcp/127.0.0.1/8097; printf "GET /api/debug/call HTTP/1.0\r\nHost: localhost\r\nX-WA4S-Token: %s\r\n\r\n" "$(cat /data/token)" >&3; cat <&3'
```
Use `docker exec` instead of `podman exec` if the bridge runs in Docker.

Answer on the iPhone and you should hear yourself after about 0.3 s. Add `?state=ended` after `/api/debug/call` to hang up, or `?video=1` to echo the camera too.
