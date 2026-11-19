#!/system/bin/sh

HK_VER=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
[ -n "$HK_VER" ] || HK_VER=v1.0.2

ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  🛡️ HostKeeper $HK_VER"
ui_print "  The Zero-Bloat Digital Guardian"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "

for HK_FILE in hostkeeper.sh action.sh service.sh post-mount.sh uninstall.sh; do
  set_perm "$MODPATH/$HK_FILE" 0 0 0755
done

HK_MODDIR="$MODPATH" BOOTMODE="${BOOTMODE:-true}" \
  KSU="${KSU:-}" KSU_VER="${KSU_VER:-}" \
  APATCH="${APATCH:-}" APATCH_VER="${APATCH_VER:-}" \
  MAGISK_VER="${MAGISK_VER:-}" \
  sh "$MODPATH/hostkeeper.sh" _install 2>&1 | while IFS= read -r HK_LINE; do ui_print "$HK_LINE"; done

set_perm "$MODPATH/system/etc/hosts" 0 0 0644 u:object_r:system_file:s0
rm -f "$MODPATH/CHANGELOG.md" 2>/dev/null
unset HK_FILE HK_LINE HK_VER
ui_print " "
