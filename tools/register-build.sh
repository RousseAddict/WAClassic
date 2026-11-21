#!/bin/bash
# registers released debs as official builds for the diagnostics (update.waclassic.com, table official_builds).
# reports whose app binary isn't in there show up as "modified" on stats.waclassic.com.
# run for every deb that goes public (release and beta):  tools/register-build.sh packages/com.aronsz26.wa4s_1.0.5_iphoneos-arm.deb ...
# LOCAL=1 writes to the local wrangler db instead (testing)
set -euo pipefail
SITE=${SITE:-$HOME/website-waclassic}
[ $# -gt 0 ] || { echo "usage: $0 deb..." >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sql=""
for deb in "$@"; do
  deb=$(cd "$(dirname "$deb")" && pwd)/$(basename "$deb")
  x="$tmp/x"; rm -rf "$x"; mkdir -p "$x/c"
  (cd "$x" && ar x "$deb")
  tar -xf "$x"/data.tar.* -C "$x"
  tar -xf "$x"/control.tar.* -C "$x/c"
  app=$(sed -n 's/^Version: //p' "$x/c/control"); pkg=$(sed -n 's/^Package: //p' "$x/c/control")
  [[ $app =~ ^[0-9A-Za-z.+~-]+$ && $pkg =~ ^[0-9a-z.+-]+$ ]] || { echo "odd control file in $deb" >&2; exit 1; }
  found=0
  for plist in "$x"/Applications/*.app/Info.plist; do
    bin="$(dirname "$plist")/$(plutil -extract CFBundleExecutable raw "$plist")"
    [ -f "$bin" ] || continue
    sha=$(shasum -a 256 "$bin" | cut -d' ' -f1)
    echo "$pkg $app $sha"
    sql+="INSERT OR IGNORE INTO official_builds (sha, app, pkg, added) VALUES ('$sha', '$app', '$pkg', strftime('%s','now'));"
    found=1
  done
  [ $found = 1 ] || { echo "no app binary in $deb" >&2; exit 1; }
done
cd "$SITE/update"
npx wrangler@4 d1 execute waclassic-stats $([ "${LOCAL:-0}" = 1 ] && echo --local || echo --remote) --command "$sql"
