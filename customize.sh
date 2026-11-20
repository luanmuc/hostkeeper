#!/system/bin/sh

HK_VER=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
[ -n "$HK_VER" ] || HK_VER=v1.1.0

ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  🛡️ HostKeeper $HK_VER"
ui_print "  轻量无负担的数字守护者"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "

for HK_FILE in hostkeeper.sh action.sh service.sh post-mount.sh uninstall.sh; do
  set_perm "$MODPATH/$HK_FILE" 0 0 0755
done

HK_INSTALL_LOG="$MODPATH/.install.log"
: > "$HK_INSTALL_LOG" 2>/dev/null
HK_MODDIR="$MODPATH" BOOTMODE="${BOOTMODE:-true}" \
  KSU="${KSU:-}" KSU_VER="${KSU_VER:-}" \
  APATCH="${APATCH:-}" APATCH_VER="${APATCH_VER:-}" \
  MAGISK_VER="${MAGISK_VER:-}" \
  sh "$MODPATH/hostkeeper.sh" _install > "$HK_INSTALL_LOG" 2>&1
HK_RC=$?
if [ -f "$HK_INSTALL_LOG" ]; then
  while IFS= read -r HK_LINE; do ui_print "$HK_LINE"; done < "$HK_INSTALL_LOG"
  rm -f "$HK_INSTALL_LOG"
fi
if [ "$HK_RC" -ne 0 ]; then
  ui_print " "
  ui_print "❌ HostKeeper 安装失败（退出码 $HK_RC）。"
  ui_print "   模块未激活，请检查上方安装日志。"
  abort "HostKeeper 安装失败（退出码 $HK_RC）。"
fi

set_perm "$MODPATH/system/etc/hosts" 0 0 0644 u:object_r:system_file:s0
rm -f "$MODPATH/CHANGELOG.md" 2>/dev/null
unset HK_FILE HK_LINE HK_VER HK_RC
ui_print " "
