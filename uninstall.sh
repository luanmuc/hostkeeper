#!/system/bin/sh
MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.
[ -f "$MODDIR/hostkeeper.sh" ] && sh "$MODDIR/hostkeeper.sh" _uninstall > /dev/null 2>&1
rm -rf /data/adb/hostkeeper
