#!/system/bin/sh
MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.
HK_RC=0
if [ -f "$MODDIR/hostkeeper.sh" ]; then
  sh "$MODDIR/hostkeeper.sh" _uninstall > /dev/null 2>&1
  HK_RC=$?
else
  echo "HostKeeper：未找到卸载脚本，已保留 /data/adb/hostkeeper 以便恢复。" >&2
  HK_RC=1
fi
if [ "$HK_RC" -eq 0 ]; then
  rm -rf /data/adb/hostkeeper
else
  echo "HostKeeper：hosts 恢复或清理失败，已保留 /data/adb/hostkeeper 以便恢复。" >&2
fi
exit "$HK_RC"
