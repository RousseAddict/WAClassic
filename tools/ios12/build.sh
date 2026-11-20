#!/bin/bash
# build.sh: rebuild WA Classic's iPhone app for arm64 / iOS 12, packaged as a .deb
# for a jailbroken iPhone 5s or newer (installs to /Applications, like the original package).
#
# The app is compiled from this repo's app/ folder, unmodified except for one added
# file, WAiOS12Compat.m (asks iOS for notification permission). Optional
# tools/ios12/patches/*.patch are applied to a staged copy, never to app/.
#
# Where things run:
#   build Mac (macOS 11, Xcode 13.2.1, iOS SDK 15.2)  compile, link, stamp the SDK version, sign
#   this Mac                                          app bundle, Info.plist, icon, .deb
#   result                                            packages/<package>_<version>_iphoneos-arm.deb
# This Mac only needs the Command Line Tools (PlistBuddy, sips, python3, sshpass, rsync).
#
# The binary is stamped as "built with SDK 9.3" (LINKED_SDK). iOS keeps the legacy
# VoIP background mode, which WA Classic uses to ring for incoming calls, only for
# apps linked against an SDK older than iOS 10 (Apple QA1938). LINKED_SDK= (empty)
# keeps the real SDK stamp, for an A/B test if 9.3 misbehaves.
#
# Settings come from the environment or from <repo>/.env.local (chmod 600, git-ignored):
#   BUILD_HOST=user@build-mac   the Mac with Xcode
#   BUILD_PASS=...              its ssh password (never put it in this file)
#
# Usage:
#   tools/ios12/build.sh
#   LINKED_SDK= tools/ios12/build.sh          # keep the real SDK stamp
#   BUILD_TAG=ios12.2 tools/ios12/build.sh    # bump the package version
#   ALLOW_UNREVIEWED=1 tools/ios12/build.sh   # app/ differs from the reviewed commit
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SRC="${SRC:-$ROOT}"
# upstream commit whose app/ code was security-reviewed before this build was made
REVIEWED_COMMIT=94f9ca6e38e4408dc17a4ddd79bab40d64dbdd1d

ENV_LOCAL="$ROOT/.env.local"
# shellcheck source=/dev/null
[ -f "$ENV_LOCAL" ] && . "$ENV_LOCAL"

REMOTE_BASE="${REMOTE_BASE:-Documents/waclassic-ios12}" # relative to the build Mac's home; this script owns it
MIN_IOS="${MIN_IOS:-12.0}"
LINKED_SDK="${LINKED_SDK-9.3}"                       # ${VAR-x}: empty is meaningful (= no stamp)
PKG="${PKG:-com.aronsz26.wa4s-ios12}"
BUILD_TAG="${BUILD_TAG:-ios12.1}"
OUT_DIR="${OUT_DIR:-$ROOT/packages}"
WORK="$HERE/build"
SSH_OPTS=(-o IdentitiesOnly=yes -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

die() { echo "ERROR: $*" >&2; exit 1; }

# ── Build Mac + credentials ─────────────────────────────────────────────────
[ -n "${BUILD_HOST:-}" ] || die "BUILD_HOST is not set (user@host of a Mac with Xcode 13). Put BUILD_HOST=… in $ENV_LOCAL (chmod 600) or the environment."
[ -n "${BUILD_PASS:-}" ] || die "BUILD_PASS is not set (the build Mac's ssh password). Put BUILD_PASS=… in $ENV_LOCAL (chmod 600) or the environment."
# attached -eSSHPASS: the password never appears in ps output
export SSHPASS="$BUILD_PASS"
remote() { sshpass -eSSHPASS ssh "${SSH_OPTS[@]}" "$BUILD_HOST" "$@"; }

# ── 1. Preflight ────────────────────────────────────────────────────────────
echo "[1/6] Preflight..."
[ -d "$SRC/app" ] || die "$SRC/app not found"
COMMIT=$(git -C "$SRC" rev-parse HEAD)
git -C "$SRC" cat-file -e "$REVIEWED_COMMIT^{commit}" 2>/dev/null \
  || die "reviewed commit ${REVIEWED_COMMIT:0:7} not in this clone (shallow clone? run git fetch --unshallow)"
# the app's code (and icon) must match the reviewed commit, including local edits and new files
CHANGED=$( { git -C "$SRC" diff --name-only "$REVIEWED_COMMIT" -- app docs/icon.png
             git -C "$SRC" ls-files --others --exclude-standard -- app; } | sort -u)
if [ -n "$CHANGED" ]; then
  echo "      app/ differs from the reviewed commit ${REVIEWED_COMMIT:0:7}:"
  echo "$CHANGED" | sed 's/^/        /' | head -20
  [ "${ALLOW_UNREVIEWED:-0}" = 1 ] || die "review the changes first, then rerun with ALLOW_UNREVIEWED=1"
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$SRC/app/Resources/Info.plist")
DEBVER="$VERSION+$BUILD_TAG"
DEB="${PKG}_${DEBVER}_iphoneos-arm.deb"
echo "      WA Classic $VERSION @ ${COMMIT:0:7} -> $DEB (min iOS $MIN_IOS, SDK stamp ${LINKED_SDK:-real})"

# ── 2. Stage sources (app/ stays untouched) ─────────────────────────────────
echo "[2/6] Staging sources..."
rm -rf "$WORK" && mkdir -p "$WORK/src/compat"
cp -R "$SRC/app" "$WORK/src/app"
cp "$HERE/WAiOS12Compat.m" "$WORK/src/compat/"
cp "$HERE/entitlements.plist" "$WORK/src/"
for p in "$HERE"/patches/*.patch; do
  [ -f "$p" ] || continue
  echo "      patch $(basename "$p")"
  patch -s -d "$WORK/src" -p1 < "$p"
done

# ── 3. Sync to the build Mac ────────────────────────────────────────────────
echo "[3/6] Syncing to $BUILD_HOST:$REMOTE_BASE..."
remote "mkdir -p \"\$HOME/$REMOTE_BASE\""
# --delete is scoped to src/, a folder only this script writes: the compile step
# globs src/app/*.m, so a stale file left there would end up in the binary
rsync -az --delete -e "sshpass -eSSHPASS ssh ${SSH_OPTS[*]}" "$WORK/src/" "$BUILD_HOST:$REMOTE_BASE/src/"

# ── 4. Compile, link, stamp, sign on the build Mac ──────────────────────────
echo "[4/6] Building on the build Mac..."
emit_build_script() {
  printf 'export REMOTE_BASE=%q MIN_IOS=%q LINKED_SDK=%q\n' "$REMOTE_BASE" "$MIN_IOS" "$LINKED_SDK"
  cat <<'BUILD'
set -euo pipefail
cd "$HOME/$REMOTE_BASE"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC=(xcrun -sdk iphoneos clang)
TARGET="arm64-apple-ios$MIN_IOS"
echo "      $(xcodebuild -version | head -1) / SDK $(xcrun --sdk iphoneos --show-sdk-version) / $TARGET"
# same flags as tools/package-app.sh, with the iOS 12 target
FLAGS=(-target "$TARGET" -isysroot "$SDK" -O2 -g0 -fobjc-arc -Wall -Wno-unguarded-availability
       -Wno-deprecated-declarations -Wno-unused-command-line-argument)
rm -rf obj out && mkdir -p obj out
n=0
for f in src/app/*.m src/compat/*.m; do
  o="obj/$(basename "$f")"
  if ! "${CC[@]}" "${FLAGS[@]}" -c "$f" -o "$o.o" 2> "$o.log"; then
    cat "$o.log"; echo "ERROR: compiling $f failed"; exit 1
  fi
  n=$((n + 1))
done
echo "      compiled $n files, $(cat obj/*.log | grep -c 'warning:' || true) warnings (logs: ~/$REMOTE_BASE/obj/*.log)"
# tools/package-app.sh's link line minus its iOS 6 workarounds (-flat_namespace, -U for the NSURL classes)
"${CC[@]}" -target "$TARGET" -isysroot "$SDK" -o out/WA4S.unsigned obj/*.o \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework AVFoundation \
  -framework AudioToolbox -framework Security -framework SystemConfiguration -framework CFNetwork \
  -framework MediaPlayer -framework MobileCoreServices -framework CoreMedia -framework CoreVideo \
  -framework ImageIO -framework CoreText -lobjc -Wl,-dead_strip
if [ -n "$LINKED_SDK" ]; then
  xcrun vtool -set-build-version ios "$MIN_IOS" "$LINKED_SDK" -replace -output out/WA4S out/WA4S.unsigned
else
  cp out/WA4S.unsigned out/WA4S
fi
# binary-only ad-hoc signature with entitlements, the codesign equivalent of package-app.sh's ldid -S
codesign --force --sign - --identifier com.aronsz26.wa4s --entitlements src/entitlements.plist out/WA4S
echo "      $(lipo -info out/WA4S | sed 's/.*: //') | $(otool -l out/WA4S | grep -A4 LC_BUILD_VERSION | grep -E 'minos|sdk' | xargs)"
BUILD
}
emit_build_script | remote bash
sshpass -eSSHPASS scp -q "${SSH_OPTS[@]}" "$BUILD_HOST:$REMOTE_BASE/out/WA4S" "$WORK/WA4S"

# ── 5. App bundle + Info.plist ──────────────────────────────────────────────
echo "[5/6] Assembling WA4S.app..."
L="$WORK/layout"
APP="$L/Applications/WA4S.app"
mkdir -p "$APP" "$L/DEBIAN"
cp -R "$SRC/app/Resources/." "$APP/"
# translations: english text -> text, json in the repo, binary plist in the app (as package-app.sh)
for f in "$SRC"/app/i18n/*.json; do
  [ -f "$f" ] || continue
  l=$(basename "$f" .json)
  mkdir -p "$APP/$l.lproj"
  python3 -I -c 'import json,plistlib,sys; plistlib.dump(json.load(open(sys.argv[1])),open(sys.argv[2],"wb"),fmt=plistlib.FMT_BINARY)' \
    "$f" "$APP/$l.lproj/WAClassic.strings"
done
# launch images; sounds are empty placeholders the app fills from the bridge (no WhatsApp files shipped)
cp "$SRC"/app/Launch/Default.png "$SRC"/app/Launch/Default@2x.png "$SRC"/app/Launch/Default-568h@2x.png "$APP/"
for f in Tri-tone.caf Ringtone.caf Xylophone.caf Bell.caf Boing.caf Glass.caf Harp.caf TimePassing.caf; do
  : > "$APP/$f"
done
cp "$WORK/WA4S" "$APP/WA4S"
chmod 755 "$APP/WA4S"
# iOS 7+ home-screen icon for a @2x iPhone: 120 px (the repo's icons are 57/114 px for iOS 6)
sips -z 120 120 "$SRC/docs/icon.png" --out "$APP/Icon-60@2x.png" >/dev/null
P="$APP/Info.plist"
PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :MinimumOSVersion $MIN_IOS" "$P"
"$PB" -c "Delete :UIRequiredDeviceCapabilities" -c "Add :UIRequiredDeviceCapabilities array" \
      -c "Add :UIRequiredDeviceCapabilities:0 string arm64" "$P"
"$PB" -c "Add :CFBundleIconFiles:0 string Icon-60@2x.png" "$P"
"$PB" -c "Add :CFBundleIcons dict" -c "Add :CFBundleIcons:CFBundlePrimaryIcon dict" \
      -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles array" \
      -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles:0 string Icon-60" \
      -c "Add :CFBundleIcons:CFBundlePrimaryIcon:UIPrerenderedIcon bool true" "$P"
plutil -lint "$P" >/dev/null
find "$L" -name .DS_Store -delete

# ── 6. .deb ─────────────────────────────────────────────────────────────────
echo "[6/6] Packaging..."
cat > "$L/DEBIAN/control" <<CTRL
Package: $PKG
Name: WA Classic (iOS 12 test build)
Version: $DEBVER
Architecture: iphoneos-arm
Description: Unofficial arm64 rebuild of WA Classic $VERSION (source ${COMMIT:0:7}) for iOS 12, through your own WA Classic bridge. Not affiliated with WhatsApp, Meta or the WA Classic author.
Maintainer: local build
Author: aronsz26
Section: Social
Depends: firmware (>= $MIN_IOS)
Conflicts: com.aronsz26.wa4s, com.aronsz26.wa4s-ios4, com.aronsz26.wa4s-dev, com.aronsz26.wa4s-dev-ios4
Replaces: com.aronsz26.wa4s, com.aronsz26.wa4s-ios4, com.aronsz26.wa4s-dev, com.aronsz26.wa4s-dev-ios4
CTRL
cp "$HERE/postinst" "$HERE/postrm" "$L/DEBIAN/"
chmod 755 "$L/DEBIAN/postinst" "$L/DEBIAN/postrm"
mkdir -p "$OUT_DIR"
python3 -I "$HERE/make-deb.py" "$L" "$OUT_DIR/$DEB"
echo "==> Done: $OUT_DIR/$DEB"
echo "    sha256 $(shasum -a 256 "$OUT_DIR/$DEB" | cut -d' ' -f1)"
