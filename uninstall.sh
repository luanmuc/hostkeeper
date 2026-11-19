#!/system/bin/sh
MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.
HK_RC=0
if [ -f "$MODDIR/hostkeeper.sh" ]; then
  sh "$MODDIR/hostkeeper.sh" _uninstall > /dev/null 2>&1
  HK_RC=$?
else
  echo "HostKeeper: uninstall script not found; keeping /data/adb/hostkeeper for recovery." >&2
  HK_RC=1
fi
if [ "$HK_RC" -eq 0 ]; then
  rm -rf /data/adb/hostkeeper
else
  echo "HostKeeper: hosts restore or cleanup failed; /data/adb/hostkeeper was kept for recovery." >&2
fi
exit "$HK_RC"
