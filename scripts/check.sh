#!/bin/sh
# HostKeeper preflight check: syntax, version consistency, module structure,
# stale internal names, and obvious credential leaks.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

FAIL=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf '  warn  %s\n' "$1"; }

printf 'HostKeeper check: %s\n\n' "$ROOT"

printf 'Shell syntax\n'
for f in hostkeeper.sh customize.sh action.sh service.sh post-mount.sh uninstall.sh \
         META-INF/com/google/android/update-binary; do
  if [ ! -f "$f" ]; then
    bad "missing $f"
  elif sh -n "$f" 2>/dev/null; then
    ok "$f"
  else
    bad "$f has a shell syntax error"
  fi
done

printf '\nJavaScript syntax\n'
if command -v node >/dev/null 2>&1; then
  for f in webroot/app.js webroot/theme.js; do
    if node --check "$f" >/dev/null 2>&1; then
      ok "$f"
    else
      bad "$f has a JavaScript syntax error"
    fi
  done
else
  warn 'node is not installed; skipped JavaScript syntax checks'
fi

printf '\nmodule.prop\n'
if [ ! -f module.prop ]; then
  bad 'module.prop is missing'
else
  ID=$(sed -n 's/^id=//p' module.prop | head -n 1)
  NAME=$(sed -n 's/^name=//p' module.prop | head -n 1)
  VER=$(sed -n 's/^version=//p' module.prop | head -n 1)
  VCODE=$(sed -n 's/^versionCode=//p' module.prop | head -n 1)
  AUTHOR=$(sed -n 's/^author=//p' module.prop | head -n 1)
  [ -n "$ID" ] && ok "id=$ID" || bad 'id is empty'
  [ "$ID" = hostkeeper ] || bad "id must be hostkeeper, got '$ID'"
  [ -n "$NAME" ] && ok "name=$NAME" || bad 'name is empty'
  [ -n "$AUTHOR" ] && ok "author=$AUTHOR" || bad 'author is empty'
  case $VER in
    v[0-9]*.[0-9]*.[0-9]*) ok "version=$VER" ;;
    *) bad "version '$VER' must look like vX.Y.Z" ;;
  esac
  case $VCODE in
    '' | *[!0-9]*) bad "versionCode '$VCODE' must be a number" ;;
    *) ok "versionCode=$VCODE" ;;
  esac
fi

printf '\nVersion consistency\n'
if [ -n "${VER:-}" ] && [ -n "${VCODE:-}" ]; then
  grep -qF "HK_VER=$VER" hostkeeper.sh && ok "hostkeeper.sh HK_VER=$VER" || bad "hostkeeper.sh HK_VER is not $VER"
  grep -qF "HK_VCODE=$VCODE" hostkeeper.sh && ok "hostkeeper.sh HK_VCODE=$VCODE" || bad "hostkeeper.sh HK_VCODE is not $VCODE"
  grep -qF "HK_VER=$VER" customize.sh && ok "customize.sh fallback=$VER" || bad "customize.sh fallback is not $VER"
  grep -qF "const VERSION = '$VER';" webroot/app.js && ok "app.js VERSION=$VER" || bad "app.js VERSION is not $VER"
  grep -qF "const VERSION_CODE = $VCODE;" webroot/app.js && ok "app.js VERSION_CODE=$VCODE" || bad "app.js VERSION_CODE is not $VCODE"

  HTML_V=$(grep -F -c "?v=${VER#v}" webroot/index.html 2>/dev/null || true)
  [ "$HTML_V" -eq 3 ] && ok "index.html has 3 ?v=${VER#v} cache keys" || bad "index.html has $HTML_V/3 ?v=${VER#v} cache keys"
  grep -qF "id=\"ver\">$VER" webroot/index.html && ok "index.html #ver=$VER" || bad "index.html #ver is not $VER"
  grep -qF "id=\"credits-ver\">HostKeeper $VER" webroot/index.html && ok "index.html credits=$VER" || bad "index.html credits are not $VER"
fi

printf '\nModule files\n'
for f in module.prop customize.sh hostkeeper.sh action.sh service.sh post-mount.sh uninstall.sh \
         system/etc/hosts webroot/index.html webroot/app.js webroot/style.css webroot/theme.js \
         META-INF/com/google/android/update-binary META-INF/com/google/android/updater-script; do
  [ -e "$f" ] && ok "$f" || bad "missing $f"
done

printf '\nExecutable bits\n'
for f in hostkeeper.sh customize.sh action.sh service.sh post-mount.sh uninstall.sh \
         META-INF/com/google/android/update-binary; do
  if [ -x "$f" ]; then ok "$f"; else warn "$f is not executable (0644 checkout)"; fi
done

printf '\nStale internal names\n'
STALE='SB_|sb\.sh|sb-[a-z]|hz-[a-z]|Energized|Rasmus|v2\.0|v5\.0'
for f in module.prop hostkeeper.sh customize.sh action.sh service.sh post-mount.sh uninstall.sh \
         webroot/app.js webroot/index.html webroot/theme.js webroot/style.css; do
  if grep -nE "$STALE" "$f" >/dev/null 2>&1; then
    bad "$f contains a stale internal name"
    grep -nE "$STALE" "$f" | sed 's/^/        /'
  else
    ok "$f"
  fi
done

printf '\nCredential scan\n'
if grep -rInE 'ghp_[A-Za-z0-9]{20,}|github_pat_|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' \
     --exclude-dir=.git --exclude-dir=scripts . >/dev/null 2>&1; then
  bad 'possible credential material found in the repo'
else
  ok 'no obvious GitHub token or private key'
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf 'All checks passed.\n'
  exit 0
fi
printf '%s check(s) failed.\n' "$FAIL"
exit 1
