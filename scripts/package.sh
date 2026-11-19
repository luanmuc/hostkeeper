#!/bin/sh
# Build a clean flashable HostKeeper module zip.
# Usage: sh scripts/package.sh
# Output: ../out/HostKeeper-<version>.zip (override with OUT_DIR).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

[ -f module.prop ] || { printf 'module.prop is missing\n' >&2; exit 1; }
VERSION=$(sed -n 's/^version=//p' module.prop | head -n 1)
[ -n "$VERSION" ] || { printf 'version is empty in module.prop\n' >&2; exit 1; }
case $VERSION in
  *[!A-Za-z0-9._-]*) printf 'unsafe version string: %s\n' "$VERSION" >&2; exit 1 ;;
esac

command -v zip >/dev/null 2>&1 || { printf 'zip is not installed\n' >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { printf 'unzip is not installed\n' >&2; exit 1; }

DEFAULT_OUT=$(CDPATH= cd -- "$ROOT/.." && pwd)/out
OUT_DIR=${OUT_DIR:-$DEFAULT_OUT}
mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/HostKeeper-$VERSION.zip"

STAGE=$(mktemp -d "$OUT_DIR/.stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM

for f in module.prop customize.sh hostkeeper.sh action.sh service.sh post-mount.sh uninstall.sh LICENSE; do
  [ -f "$f" ] || { printf 'missing %s\n' "$f" >&2; exit 1; }
  cp -p "$f" "$STAGE/$f"
done
for d in META-INF system webroot; do
  [ -d "$d" ] || { printf 'missing %s/\n' "$d" >&2; exit 1; }
  cp -a "$d" "$STAGE/$d"
done

find "$STAGE" -type f -name '*.sh' -exec chmod 0755 {} +
chmod 0755 "$STAGE/META-INF/com/google/android/update-binary"

for f in module.prop hostkeeper.sh customize.sh system/etc/hosts webroot/index.html \
         META-INF/com/google/android/update-binary; do
  [ -e "$STAGE/$f" ] || { printf 'staged package is missing %s\n' "$f" >&2; exit 1; }
done
[ ! -e "$STAGE/.git" ] || { printf 'staged package contains .git\n' >&2; exit 1; }
[ ! -e "$STAGE/scripts" ] || { printf 'staged package contains scripts/\n' >&2; exit 1; }

rm -f "$ZIP"
( cd "$STAGE" && zip -qr -X "$ZIP" . )

printf 'Built: %s\n' "$ZIP"
printf 'Size:  %s bytes\n' "$(wc -c < "$ZIP")"
if command -v sha256sum >/dev/null 2>&1; then
  printf 'SHA256: %s\n' "$(sha256sum "$ZIP" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  printf 'SHA256: %s\n' "$(shasum -a 256 "$ZIP" | awk '{print $1}')"
fi
printf '\nTop-level contents:\n'
unzip -l "$ZIP" | sed -n '4,20p'
