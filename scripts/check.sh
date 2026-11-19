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

printf '\nWebUI control contract\n'
if grep -qE '<button class="switch" id="act-toggle" type="button" role="switch" aria-checked="(true|false)"' webroot/index.html; then
  ok 'hero blocker control is a role=switch button'
else
  bad 'hero blocker control is missing role=switch/aria-checked'
fi
TOGGLE_N=$(grep -c 'id="act-toggle"' webroot/index.html || true)
[ "$TOGGLE_N" -eq 1 ] && ok 'exactly one act-toggle' || bad "index.html has $TOGGLE_N act-toggle elements"
grep -q 'id="toggle-state"' webroot/index.html && ok 'toggle-state exists' || bad 'toggle-state is missing'
if grep -RInE 'toggle-label|toggle-icon|tile-power' webroot >/dev/null 2>&1; then
  bad 'dead/legacy toggle markup still referenced'
else
  ok 'no legacy toggle references'
fi
grep -q "tgl.setAttribute('aria-checked'" webroot/app.js && ok 'renderStatus owns switch state' || bad 'renderStatus does not set aria-checked'

printf '\nManager adaptation contract\n'
if grep -nE '^[[:space:]]*exit([[:space:]]|$)' customize.sh >/dev/null 2>&1; then
  bad 'customize.sh must not call exit (it is sourced by the installer)'
else
  ok 'customize.sh has no direct exit'
fi
grep -qF 'abort "HostKeeper 安装失败' customize.sh && ok 'customize.sh failure uses abort' || bad 'customize.sh failure path is missing abort'
if grep -qF 'Works with or without a metamodule' hostkeeper.sh; then
  bad 'hostkeeper.sh still claims metamodule-free KSU support'
else
  ok 'no unsupported metamodule-free KSU claim'
fi
grep -qF "'apatch'" webroot/app.js && ok 'WebUI bridge detects apatch bridge' || bad 'WebUI bridge is missing apatch detection'
if grep -qF 'umount "$HOSTS"' hostkeeper.sh; then
  bad 'uninstall still umounts the module-side hosts path'
else
  ok 'uninstall only umounts the live mount target'
fi
grep -qF 'metamodule' README.md && ok 'README documents KSU metamodule requirement' || bad 'README is missing the KSU metamodule requirement'
grep -qF '不支持自定义 Recovery' README.md && ok 'README documents manager-only install' || bad 'README is missing the manager-only install warning'

printf '\nChinese UI contract\n'
grep -qF '<html lang="zh-CN"' webroot/index.html && ok 'HTML locale is zh-CN' || bad 'HTML locale is not zh-CN'
grep -qF 'aria-label="开启拦截"' webroot/index.html && ok 'hero switch has Chinese aria-label' || bad 'hero switch aria-label is not Chinese'
grep -qF '>关闭</span>' webroot/index.html && ok 'initial toggle state is 关闭' || bad 'initial toggle state is not 关闭'
grep -qF '健康检查' webroot/index.html && ok 'health check tile is Chinese' || bad 'health check tile is not Chinese'
grep -qF '请先开启拦截' hostkeeper.sh && ok 'backend blocker message is Chinese' || bad 'backend blocker message is not Chinese'
grep -qF 'L_URL_ALT=' hostkeeper.sh && ok 'GitHub list fallback URL field present' || bad 'GitHub list fallback URL field missing'
grep -qF 'cdn.jsdelivr.net' hostkeeper.sh && ok 'jsDelivr fallback present' || bad 'jsDelivr fallback missing'
grep -qF 'dl_fetch_any' hostkeeper.sh && ok 'download fallback helper present' || bad 'download fallback helper missing'
if grep -qF '_mf_urls=$DL_USED_URL' hostkeeper.sh; then
  bad 'meta full download drops mirror fallback after peek'
else
  ok 'meta full download keeps mirror fallback'
fi
grep -qF 'function apiTimeout' webroot/app.js && ok 'UI request timeout helper present' || bad 'UI request timeout helper missing'
grep -qF "apiTimeout('diag', [], 25000)" webroot/app.js && ok 'health check uses 25s timeout' || bad 'health check does not use 25s timeout'
grep -qF 'DL_MAX_TIME=20' hostkeeper.sh && ok 'diag network peek is time-bounded' || bad 'diag network peek is unbounded'
grep -qF 'showDiag.seq' webroot/app.js && ok 'health check has stale-response guard' || bad 'health check has no stale-response guard'
grep -qF 'add.disabled = busy || reached;' webroot/app.js && ok 'custom add re-enables after busy' || bad 'custom add can stay disabled after busy'
grep -qF 'r = await sendImport(p.allow, p.block, mode);' webroot/app.js && ok 'rule import has guarded busy release' || bad 'rule import busy release not guarded'
grep -qF "L_LEVELTXT='均衡'" hostkeeper.sh && ok 'list level text is Chinese' || bad 'list level text is not Chinese'
if grep -RInE 'Disable HostKeeper\?|Enable blocking|Disable blocking|Loading…|Pick a blocklist' webroot >/dev/null 2>&1; then
  bad 'legacy English UI copy is still present'
else
  ok 'no legacy English UI copy'
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
