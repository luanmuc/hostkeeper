#!/system/bin/sh

if [ "${HK_EXEC:-}" != "$$" ]; then
  for _bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
    if [ -x "$_bb" ]; then
      HK_BB=$_bb
      HK_EXEC=$$
      ASH_STANDALONE=1
      export HK_BB HK_EXEC ASH_STANDALONE
      exec "$_bb" sh "$0" "$@"
    fi
  done
  HK_BB=none
  HK_EXEC=$$
  export HK_BB HK_EXEC
fi

umask 022
PATH=/system/bin:/system/xbin:/vendor/bin:${PATH:-/bin}
export PATH

HK_VER=v1.1.4
HK_VCODE=15
SELF=$0
case $SELF in /*) ;; *) SELF=$(pwd)/$SELF ;; esac
MODDIR=${HK_MODDIR:-${SELF%/*}}
MODROOT=/data/adb/modules
DATA=/data/adb/hostkeeper
CFG=$DATA/config
SEQF=$DATA/seq
PENDF=$DATA/reboot.pending
LOGF=$DATA/hostkeeper.log
SRCF=$DATA/sources
SUMF=$DATA/hosts.sum
STATF=$DATA/stats
RULESD=$DATA/rules
ALLOWF=$RULESD/allow.list
ALLOWD=$MODDIR/allow-default.list
BLOCKD=$MODDIR/block-default.list
BLOCKD2=$MODDIR/block-default-adn.list
BLOCKF=$RULESD/block.list
CACHED=$DATA/cache
LISTSD=$CACHED/lists
METAD=$CACHED/meta
OLDCACHE=$CACHED/list.domains
BACKUPD=$DATA/backup
ORIGHOSTS=$BACKUPD/hosts.original
RUND=$DATA/run
TMPD=$DATA/tmp
STAGED=$TMPD/stage
LOCKD=$RUND/lock
METALOCK=$RUND/meta.lock
DIAGLOCK=$RUND/diag.lock
OPF=$RUND/op
SCHEDPID=$RUND/sched.pid
SCHEDRETRY=$RUND/sched.retry
DLPART=$TMPD/download.part
DLHDR=$TMPD/download.hdr
HOSTSD=$MODDIR/system/etc
HOSTS=$HOSTSD/hosts
PROP=$MODDIR/module.prop
# module.prop is the single source of truth for the version; HK_VER/HK_VCODE above are fallbacks only.
if [ -f "$PROP" ]; then
  _hk_ver=$(sed -n 's/^version=//p' "$PROP" 2>/dev/null | head -n 1)
  _hk_vcode=$(sed -n 's/^versionCode=//p' "$PROP" 2>/dev/null | head -n 1)
  [ -n "$_hk_ver" ] && HK_VER=$_hk_ver
  case $_hk_vcode in '' | *[!0-9]*) ;; *) HK_VCODE=$_hk_vcode ;; esac
  unset _hk_ver _hk_vcode
fi
SYS_HOSTS=/system/etc/hosts
INIT_HOSTS=/proc/1/root/system/etc/hosts
INIT_NS=/proc/1/ns/mnt
MOUNT_TARGET=/system/etc/hosts
MOUNTF=$RUND/mount
PORT=9090
IDLE_LIMIT=600
MAX_BYTES=67108864
RULE_MAX=1000
CUSTOM_MAX=8
LOG_MAX=500
STALE_DAYS=7
SCHED_TICK=900
UA="HostKeeper/${HK_VER#v}"
BASE_IDS="stevenblack hblock hagezi-light hagezi-normal hagezi-pro hagezi-proplus hagezi-ultimate"
ADDON_IDS="stevenblack-fakenews stevenblack-gambling stevenblack-adult stevenblack-social hagezi-doh hagezi-tif hagezi-xiaomi hagezi-samsung hagezi-huawei hagezi-oppo hagezi-vivo hagezi-amazon hagezi-tiktok hagezi-microsoft"
LOCAL_LINE='127.0.0.1 localhost'
LOCAL6_LINE='::1 localhost ip6-localhost'
MODE=cli
DL_TOOL=
DL_GZ=0
DL_MAX_REDIR=5
DL_GUARD_PRIVATE=0
DL_PIDF=
NL='
'
CR=$(printf '\r')
TAB=$(printf '\t')
STEVENBLACK_RAW=https://raw.githubusercontent.com/StevenBlack/hosts/refs/heads/master
HAGEZI_RAW=https://raw.githubusercontent.com/hagezi/dns-blocklists-legacy/refs/heads/main/hosts

list_info() {
  L_KIND=base; L_GROUP=; L_LEVEL=; L_LEVELTXT=; L_ICON=; L_WARN=; L_MIN=1000; L_CUSTOM=0; L_URL_ALT=
  case $1 in
    stevenblack)
      L_NAME='StevenBlack Main'; L_GROUP=unified; L_LEVEL=green; L_LEVELTXT='均衡'
      L_URL="$STEVENBLACK_RAW/hosts"
      L_DESC='经典综合列表，拦截广告和恶意软件，误报非常少。' ;;
    hblock)
      L_NAME='hBlock'; L_GROUP=unified; L_LEVEL=blue; L_LEVELTXT='混合'
      L_URL='https://hblock.molinero.dev/hosts'
      L_DESC='合并数十个公共拦截列表，形成一份覆盖面广的通用列表。' ;;
    hagezi-light)
      L_NAME='HaGeZi Light'; L_GROUP=hagezi; L_LEVEL=green; L_LEVELTXT='基础'
      L_URL="$HAGEZI_RAW/light.txt"
      L_DESC='基础防护，拦截广告、追踪和遥测，尽量不影响正常使用。' ;;
    hagezi-normal)
      L_NAME='HaGeZi Normal'; L_GROUP=hagezi; L_LEVEL=blue; L_LEVELTXT='全能'
      L_URL="$HAGEZI_RAW/multi.txt"
      L_DESC='全能防护，拦截广告、追踪、钓鱼、恶意软件和诈骗。' ;;
    hagezi-pro)
      L_NAME='HaGeZi Pro'; L_GROUP=hagezi; L_LEVEL=yellow; L_LEVELTXT='增强'
      L_URL="$HAGEZI_RAW/pro.txt"
      L_DESC='增强防护，覆盖更多追踪器，可能需要添加放行规则。' ;;
    hagezi-proplus)
      L_NAME='HaGeZi Pro++'; L_GROUP=hagezi; L_LEVEL=orange; L_LEVELTXT='激进'
      L_URL="$HAGEZI_RAW/pro.plus.txt"
      L_DESC='激进拦截，部分正常网站或应用功能可能受影响。' ;;
    hagezi-ultimate)
      L_NAME='HaGeZi Ultimate'; L_GROUP=hagezi; L_LEVEL=red; L_LEVELTXT='极限'
      L_URL="$HAGEZI_RAW/ultimate.txt"
      L_DESC='最严格的列表，可能限制应用和网站功能。' ;;
    stevenblack-fakenews)
      L_KIND=addon; L_GROUP=content; L_ICON='🗞️'; L_MIN=100; L_NAME='虚假新闻'
      L_URL="$STEVENBLACK_RAW/alternates/fakenews-only/hosts"
      L_DESC='已知发布虚假新闻内容的网站。' ;;
    stevenblack-gambling)
      L_KIND=addon; L_GROUP=content; L_ICON='🎰'; L_MIN=100; L_NAME='赌博'
      L_URL="$STEVENBLACK_RAW/alternates/gambling-only/hosts"
      L_DESC='在线赌场、博彩和彩票网站。' ;;
    stevenblack-adult)
      L_KIND=addon; L_GROUP=content; L_ICON='🔞'; L_MIN=1000; L_NAME='成人内容'
      L_URL="$STEVENBLACK_RAW/alternates/porn-only/hosts"
      L_DESC='色情及其他成人网站，适合作为家庭安全设备的基础拦截。' ;;
    stevenblack-social)
      L_KIND=addon; L_GROUP=content; L_ICON='👥'; L_MIN=100; L_WARN=breaks; L_NAME='社交网络'
      L_URL="$STEVENBLACK_RAW/alternates/social-only/hosts"
      L_DESC='拦截社交网络本身，例如 Facebook、Instagram 和 X。' ;;
    hagezi-doh)
      L_KIND=addon; L_GROUP=security; L_ICON='🔐'; L_MIN=100; L_WARN=dns; L_NAME='加密 DNS 绕过'
      L_URL="$HAGEZI_RAW/doh.txt"
      L_DESC='拦截公共 DNS-over-HTTPS 服务器，防止应用绕过 hosts 文件。' ;;
    hagezi-tif)
      L_KIND=addon; L_GROUP=security; L_ICON='🦠'; L_MIN=1000; L_WARN=heavy; L_NAME='威胁情报'
      L_URL="$HAGEZI_RAW/tif.txt"
      L_DESC='恶意软件、钓鱼和诈骗域名，体积很大，超过一百万条。' ;;
    hagezi-xiaomi)
      L_KIND=addon; L_GROUP=tracker; L_ICON='📱'; L_MIN=20; L_NAME='Xiaomi'
      L_URL="$HAGEZI_RAW/native.xiaomi.txt"
      L_DESC='小米、Redmi 和 POCO 设备内置的遥测与广告域名。' ;;
    hagezi-samsung)
      L_KIND=addon; L_GROUP=tracker; L_ICON='📱'; L_MIN=20; L_NAME='Samsung'
      L_URL="$HAGEZI_RAW/native.samsung.txt"
      L_DESC='三星设备内置的遥测与广告域名。' ;;
    hagezi-huawei)
      L_KIND=addon; L_GROUP=tracker; L_ICON='📱'; L_MIN=20; L_NAME='Huawei'
      L_URL="$HAGEZI_RAW/native.huawei.txt"
      L_DESC='华为和荣耀设备内置的遥测与广告域名。' ;;
    hagezi-oppo)
      L_KIND=addon; L_GROUP=tracker; L_ICON='📱'; L_MIN=20; L_NAME='OPPO & Realme'
      L_URL="$HAGEZI_RAW/native.oppo-realme.txt"
      L_DESC='OPPO、Realme 和一加设备内置的遥测与广告域名。' ;;
    hagezi-vivo)
      L_KIND=addon; L_GROUP=tracker; L_ICON='📱'; L_MIN=20; L_NAME='Vivo'
      L_URL="$HAGEZI_RAW/native.vivo.txt"
      L_DESC='Vivo 和 iQOO 设备内置的遥测与广告域名。' ;;
    hagezi-amazon)
      L_KIND=addon; L_GROUP=tracker; L_ICON='📦'; L_MIN=20; L_NAME='Amazon'
      L_URL="$HAGEZI_RAW/native.amazon.txt"
      L_DESC='亚马逊设备和应用内置的追踪。' ;;
    hagezi-tiktok)
      L_KIND=addon; L_GROUP=tracker; L_ICON='🎵'; L_MIN=20; L_NAME='TikTok'
      L_URL="$HAGEZI_RAW/native.tiktok.txt"
      L_DESC='TikTok 使用的追踪和指纹识别域名。' ;;
    hagezi-microsoft)
      L_KIND=addon; L_GROUP=tracker; L_ICON='🪟'; L_MIN=20; L_NAME='Microsoft'
      L_URL="$HAGEZI_RAW/native.winoffice.txt"
      L_DESC='Windows、Office 及其他微软应用的遥测。' ;;
    c-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
      custom_info "$1" || return 1 ;;
    *) return 1 ;;
  esac
  L_URL_ALT=
  case $L_URL in
    https://raw.githubusercontent.com/*)
      _lu_rest=${L_URL#https://raw.githubusercontent.com/}
      _lu_repo=${_lu_rest%%/refs/heads/*}
      _lu_rest=${_lu_rest#*/refs/heads/}
      _lu_branch=${_lu_rest%%/*}
      _lu_path=${_lu_rest#*/}
      [ -n "$_lu_repo" ] && [ -n "$_lu_branch" ] && [ -n "$_lu_path" ] && \
        L_URL_ALT="https://cdn.jsdelivr.net/gh/$_lu_repo@$_lu_branch/$_lu_path"
      ;;
  esac
  return 0
}

custom_info() {
  [ -f "$SRCF" ] || return 1
  while IFS='|' read -r _cu_i _cu_u _cu_n; do
    [ "$_cu_i" = "$1" ] || continue
    L_KIND=addon; L_GROUP=custom; L_ICON='🔗'; L_MIN=1; L_CUSTOM=1; L_URL_ALT=
    L_URL=$_cu_u
    L_NAME=$_cu_n
    L_DESC=${_cu_u#https://}
    return 0
  done < "$SRCF"
  return 1
}

custom_ids() {
  R_CUSTOM=
  [ -f "$SRCF" ] || return 0
  while IFS='|' read -r _ci_i _ci_u _ci_n; do
    case $_ci_i in c-????????) R_CUSTOM="$R_CUSTOM $_ci_i" ;; esac
  done < "$SRCF"
  R_CUSTOM=${R_CUSTOM# }
}

AWK_JESC='
BEGIN {
  ORS = ""; printf "\""
  for (i = 1; i < 32; i++) {
    c = sprintf("%c", i)
    if (c != "\n" && c != "\r" && c != "\t") C0[c] = sprintf("\\u%04x", i)
  }
}
{
  if (NR > 1) printf "\\n"
  s = $0; o = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\") o = o "\\\\"
    else if (c == "\"") o = o "\\\""
    else if (c == "\t") o = o " "
    else if (c in C0) o = o C0[c]
    else if (c != "\r") o = o c
  }
  printf "%s", o
}
END { printf "\"" }'

AWK_ESC='
function esc(s,   o, i, c, n) {
  o = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "\\") o = o "\\\\"
    else if (c == "\"") o = o "\\\""
    else if (c >= " ") o = o c
  }
  return o
}'

AWK_RDOM='
function rdom(d,   n, i, L) {
  if (length(d) < 1 || length(d) > 253) return 0
  n = split(d, L, ".")
  if (n < 2) return 0
  for (i = 1; i <= n; i++) {
    if (length(L[i]) < 1 || length(L[i]) > 63) return 0
    if (i < n) { if (L[i] !~ /^[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?$/) return 0 }
    else if (L[i] !~ /^[a-z][a-z]+$/ && L[i] !~ /^xn--[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) return 0
  }
  return 1
}'

AWK_VALID="$AWK_RDOM"'
{ exit rdom($0) ? 0 : 1 }'

AWK_NORM='
function toolong(d,   n, i, L) {
  if (length(d) > 253) return 1
  n = split(d, L, ".")
  for (i = 1; i <= n; i++) if (length(L[i]) > 63) return 1
  return 0
}
{
  if (index($0, "\r")) gsub(/\r/, "")
  c = index($0, "#")
  if (c) $0 = substr($0, 1, c - 1)
  if (NF < 2) {
    if (NF == 0) next
    s = 1
    if (substr($1, 1, 2) == "||") {
      d = $1
      if (d !~ /^\|\|[^\/^$*|]+\^$/) next
      $1 = substr(d, 3, length(d) - 3)
    }
  } else if ($1 == "0.0.0.0" || $1 == "127.0.0.1" || index($1, ":") || $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) s = 2
  else next
  for (f = s; f <= NF; f++) {
    d = tolower($f)
    if (d !~ /^([a-z0-9_]([a-z0-9_-]*[a-z0-9_])?\.)+([a-z][a-z]+|xn--[a-z0-9]([a-z0-9-]*[a-z0-9])?)$/) {
      if (substr(d, length(d)) != ".") continue
      d = substr(d, 1, length(d) - 1)
      if (d !~ /^([a-z0-9_]([a-z0-9_-]*[a-z0-9_])?\.)+([a-z][a-z]+|xn--[a-z0-9]([a-z0-9-]*[a-z0-9])?)$/) continue
    }
    if (seen[d]++) continue
    if (toolong(d)) continue
    if (d == "localhost.localdomain") continue
    print d
    n++
  }
}
END { print n + 0 > cntf }'

AWK_COMPILE='
function guarded(d,   n) {
  n = length(G)
  if (d == G) return 1
  if (n > 0 && length(d) > n && substr(d, length(d) - n) == "." G) return 1
  return 0
}
BEGIN {
  while ((getline l < allowf) > 0) {
    if (l == "") continue
    if (substr(l, 1, 2) == "*.") {
      l = substr(l, 3)
      AW[l] = 1
      naw++
      t = l
      while ((i = index(t, ".")) > 0) t = substr(t, i + 1)
      TL[t] = 1
    } else {
      A[l] = 1
      nae++
    }
  }
  close(allowf)
  while ((getline l < blockf) > 0) if (l != "" && !(l in B)) { B[l] = 1; BO[++nb] = l }
  close(blockf)
  G = ""
  if (guard != "" && !(guard in B)) G = guard
  plain = (G == "" && !nae && !naw && !nb)
  print local4
  print local6
}
plain {
  print "0.0.0.0 " $0
  n++
  next
}
{
  d = $0
  if (guarded(d)) { g = 1; next }
  if (nae && (d in A)) { na++; next }
  if (naw && ($NF in TL)) {
    s = d
    hit = 0
    while (1) {
      if (s in AW) { hit = 1; break }
      i = index(s, ".")
      if (!i) break
      s = substr(s, i + 1)
    }
    if (hit) { na++; next }
  }
  if (nb && (d in B)) BS[d] = 1
  print "0.0.0.0 " d
  n++
}
END {
  for (i = 1; i <= nb; i++) {
    if (BO[i] in BS) continue
    print "0.0.0.0 " BO[i]
    n++
    nbr++
  }
  printf "TOTAL=%d\nALLOWED=%d\nBLOCKED=%d\nGUARDED=%d\n", n, na, nbr, g > statf
}'

AWK_MERGE='
BEGIN {
  ns = split(addons, SF, " ")
  for (i = 1; i <= ns; i++) {
    while ((getline l < SF[i]) > 0) if (l != "" && !(l in X)) X[l] = i
    close(SF[i])
  }
}
{
  nbase++
  if ($0 in X) X[$0] = 0
}
END {
  printf "" > outf
  for (i = 1; i <= ns; i++) {
    while ((getline l < SF[i]) > 0) {
      if (l == "" || X[l] != i) continue
      print l > outf
      X[l] = -1
      C[i]++
    }
    close(SF[i])
  }
  printf "BASE=%d\n", nbase > statf
  for (i = 1; i <= ns; i++) printf "ADDON%d=%d\n", i, C[i] + 0 > statf
}'

AWK_VERIFY='
NR == 1 { if ($0 != local4) { bad = 1; exit } next }
NR == 2 { if ($0 != local6) { bad = 1; exit } next }
{ if (NF != 2 || $1 != "0.0.0.0") { bad = 1; exit } }
END { exit (bad || NR != want + 2) ? 1 : 0 }'

AWK_RULES="$AWK_RDOM"'
function covered(d,   i, s) {
  s = d
  while (1) {
    if (s in AW) return s
    i = index(s, ".")
    if (!i) return ""
    s = substr(s, i + 1)
  }
}
function blockunder(b,   k, n) {
  n = length(b)
  for (k in B) if (k == b || (length(k) > n && substr(k, length(k) - n) == "." b)) return k
  return ""
}
function rej(why, ref) { lastrej = why; lastref = ref }
BEGIN {
  if (mode != "replace") {
    while ((getline l < allowf) > 0) {
      if (l == "" || (l in A)) continue
      A[l] = 1; AO[++na] = l
      if (substr(l, 1, 2) == "*.") AW[substr(l, 3)] = 1
    }
    close(allowf)
    while ((getline l < blockf) > 0) {
      if (l == "" || (l in B)) continue
      B[l] = 1; BO[++nb] = l
    }
    close(blockf)
  }
}
{
  t = $1
  d = tolower($2)
  if (NF != 2 || (t != "a" && t != "b")) { invalid++; rej("invalid", ""); next }
  if (substr(d, length(d)) == ".") d = substr(d, 1, length(d) - 1)
  w = (substr(d, 1, 2) == "*.")
  base = w ? substr(d, 3) : d
  if (!rdom(base) || (w && t == "b")) { invalid++; rej("invalid", d); next }
  if (t == "a") {
    if (d in A) { dup++; rej("exists", d); next }
    if (!w) {
      c = covered(base)
      if (c != "") { dup++; rej("covered", "*." c); next }
      if (d in B) { conflict++; rej("conflict", d); next }
    } else {
      c = blockunder(base)
      if (c != "") { conflict++; rej("covers", c); next }
    }
    if (na >= max) { limit++; rej("limit", d); next }
    A[d] = 1; AO[++na] = d; adda++
    if (w) AW[base] = 1
  } else {
    if (d in B) { dup++; rej("exists", d); next }
    if (d in A) { conflict++; rej("conflict", d); next }
    c = covered(d)
    if (c != "") { conflict++; rej("blocked_by_wildcard", "*." c); next }
    if (nb >= max) { limit++; rej("limit", d); next }
    B[d] = 1; BO[++nb] = d; addb++
  }
}
END {
  printf "" > outa
  printf "" > outb
  for (i = 1; i <= na; i++) print AO[i] > outa
  for (i = 1; i <= nb; i++) print BO[i] > outb
  printf "ADDED_A=%d\nADDED_B=%d\nINVALID=%d\nDUP=%d\nCONFLICT=%d\nLIMIT=%d\nLASTREJ=%s\nLASTREF=%s\n", adda, addb, invalid, dup, conflict, limit, lastrej, lastref
}'

AWK_HEAD='
{ l = $0; sub(/\r$/, "", l) }
l !~ /^[ \t]*[#!]/ { next }
{ x = tolower(l) }
cnt == "" && x ~ /(number of (unique )?(domains|entries)|blocked domains|total (domains|entries)|entries)[ \t]*:/ {
  v = l; sub(/^[^:]*:[ \t]*/, "", v); gsub(/[,. _]/, "", v)
  if (v ~ /^[0-9]+$/) cnt = v
}
dt == "" && x ~ /^[ \t]*[#!][ \t]*(date|last[ -]modified|last updated|updated)[ \t]*:/ {
  v = l; sub(/^[^:]*:[ \t]*/, "", v); dt = v
}
END { print cnt; print dt }'

AWK_DATE='
function dim(y, m) {
  if (m == 2) return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28
  if (m == 4 || m == 6 || m == 9 || m == 11) return 30
  return 31
}
function civ(y, m, d,   era, yoe, doy, doe) {
  y -= (m <= 2)
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
BEGIN {
  split("jan feb mar apr may jun jul aug sep oct nov dec", MN, " ")
  for (i = 1; i <= 12; i++) MI[MN[i]] = i
}
NR == 1 {
  s = tolower($0)
  gsub(/[(),]/, " ", s)
  y = 0; m = 0; d = 0; hh = 0; mm = 0; ss = 0; off = 0
  if (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) {
    y = substr(s, RSTART, 4) + 0; m = substr(s, RSTART + 5, 2) + 0; d = substr(s, RSTART + 8, 2) + 0
    s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + 10)
  }
  n = split(s, T, /[ \t]+/)
  for (i = 1; i <= n; i++) {
    t = T[i]
    sub(/^t/, "", t)
    if (t == "") continue
    if (t ~ /^[0-9]+:[0-9]+/) {
      split(t, P, ":"); hh = P[1] + 0; mm = P[2] + 0; ss = (P[3] ~ /^[0-9]/) ? int(P[3]) : 0
      if (match(t, /[+-][0-9][0-9]:?[0-9][0-9]$/)) {
        o = substr(t, RSTART); gsub(/:/, "", o)
        off = (substr(o, 2, 2) * 3600 + substr(o, 4, 2) * 60) * (substr(o, 1, 1) == "-" ? -1 : 1)
      }
    }
    else if (t ~ /^[0-9][0-9][0-9][0-9]$/ && !y) y = t + 0
    else if (t ~ /^[0-9][0-9]?$/ && !d) d = t + 0
    else if ((substr(t, 1, 3) in MI) && !m) m = MI[substr(t, 1, 3)]
    else if (t ~ /^[+-][0-9][0-9][0-9][0-9]$/) off = (substr(t, 2, 2) * 3600 + substr(t, 4, 2) * 60) * (substr(t, 1, 1) == "-" ? -1 : 1)
  }
  if (y < 1990 || m < 1 || m > 12 || d < 1 || d > dim(y, m) || hh > 23 || mm > 59 || ss > 59) exit
  printf "%.0f\n", civ(y, m, d) * 86400 + hh * 3600 + mm * 60 + ss - off
  exit
}'

AWK_HDR='
{ l = $0; sub(/\r$/, "", l); sub(/^[ \t]+/, "", l); x = tolower(l) }
x ~ /^http\/[0-9.]+[ \t]+[0-9][0-9][0-9]/ { split(l, p, /[ \t]+/); code = p[2]; cl = ""; tot = ""; et = ""; lm = ""; enc = ""; next }
x ~ /^content-length:/ { v = l; sub(/^[^:]*:[ \t]*/, "", v); if (v ~ /^[0-9]+$/) cl = v; next }
x ~ /^content-range:/ { v = l; sub(/^.*\//, "", v); if (v ~ /^[0-9]+$/) tot = v; next }
x ~ /^content-encoding:/ { v = x; sub(/^[^:]*:[ \t]*/, "", v); if (v != "identity") enc = v; next }
x ~ /^etag:/ { v = l; sub(/^[^:]*:[ \t]*/, "", v); sub(/^[Ww]\//, "", v); et = v; next }
x ~ /^last-modified:/ { v = l; sub(/^[^:]*:[ \t]*/, "", v); lm = v; next }
END { if (tot == "" && code == "200" && enc == "") tot = cl; print code; print cl; print tot; print et; print lm; print enc }'

AWK_OPJSON="$AWK_ESC"'
{ i = index($0, "="); if (i) O[substr($0, 1, i - 1)] = substr($0, i + 1) }
END {
  while ((getline l < hdr) > 0) {
    sub(/\r$/, "", l); sub(/^[ \t]+/, "", l); x = tolower(l)
    if (x ~ /^http\/[0-9.]+[ \t]+[0-9]/) { cl = ""; enc = "" }
    else if (x ~ /^content-length:/) { v = l; sub(/^[^:]*:[ \t]*/, "", v); if (v ~ /^[0-9]+$/) cl = v }
    else if (x ~ /^content-encoding:/) { v = x; sub(/^[^:]*:[ \t]*/, "", v); if (v != "identity") enc = v }
  }
  st = O["STATE"]; run = 0
  if (st == "running") { if (alive == 1) run = 1; else st = "interrupted" }
  ph = O["PHASE"]
  tot = O["TOTAL"] + 0
  if (!tot && cl != "" && enc == "") tot = cl + 0
  can = "false"
  if (run && (ph == "prepare" || ph == "check" || ph == "download" || ph == "verify" || ph == "optimize")) can = "true"
  printf "{\"running\":%s,\"state\":\"%s\",\"kind\":\"%s\",\"list\":\"%s\",\"phase\":\"%s\",\"code\":\"%s\",\"message\":\"%s\",\"seq\":%.0f,\"bytes\":%.0f,\"total\":%.0f,\"domains\":%.0f,\"reboot\":%s,\"live\":%s,\"started\":%.0f,\"ended\":%.0f,\"cancellable\":%s,\"cancelling\":%s,\"item\":%d,\"items\":%d,\"source\":\"%s\",\"sourceName\":\"%s\",\"warn\":%d}", (run ? "true" : "false"), esc(st), esc(O["KIND"]), esc(O["LIST"]), esc(ph), esc(O["CODE"]), esc(O["MSG"]), O["SEQ"] + 0, (run ? bytes + 0 : 0), tot, O["DOMAINS"] + 0, (O["REBOOT"] == "1" ? "true" : "false"), (O["LIVE"] == "1" ? "true" : "false"), O["START"] + 0, O["END"] + 0, can, (cancelling == 1 && run ? "true" : "false"), O["ITEM"] + 0, O["ITEMS"] + 0, esc(O["SRC"]), esc(O["SRCNAME"]), O["WARN"] + 0
}'

AWK_LOGS="$AWK_ESC"'
BEGIN { ORS = ""; printf "[" }
{
  i = index($0, "|"); if (!i) next
  t = substr($0, 1, i - 1); r = substr($0, i + 1)
  j = index(r, "|"); if (!j) next
  lv = substr(r, 1, j - 1); m = substr(r, j + 1)
  if (t !~ /^[0-9]+$/) next
  if (lv != "INFO" && lv != "WARN" && lv != "ERROR") lv = "INFO"
  printf "%s{\"t\":%s,\"l\":\"%s\",\"m\":\"%s\"}", (n++ ? "," : ""), t, lv, esc(m)
}
END { printf "]" }'

AWK_QUERY='
BEGIN { for (i = 32; i < 127; i++) H[sprintf("%02x", i)] = sprintf("%c", i) }
function dec(s,   o, i, c, h) {
  o = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "%") {
      h = tolower(substr(s, i + 1, 2))
      if (!(h in H)) return "\001"
      c = H[h]; i += 2
    } else if (c == "+") c = " "
    o = o c
  }
  return o
}
{
  n = split($0, P, "&")
  for (i = 1; i <= n; i++) {
    k = P[i]; v = ""
    j = index(k, "=")
    if (j) { v = substr(k, j + 1); k = substr(k, 1, j - 1) }
    if (k == "t" || k == "c" || k == "a" || k == "b" || k == "d") V[k] = dec(v)
  }
}
END { print V["t"]; print V["c"]; print V["a"]; print V["b"]; print V["d"] }'

AWK_JARR='
BEGIN { ORS = ""; printf "[" }
NF { printf "%s\"%s\"", (n++ ? "," : ""), $1 }
END { printf "]" }'

now() { date +%s; }
nap() { sleep "$1" 2>/dev/null || sleep 1; }
is_num() { case $1 in '' | *[!0-9]*) return 1 ;; esac; return 0; }
has() { command -v "$1" >/dev/null 2>&1; }
say() { [ "$MODE" = install ] && printf '%s\n' "$1"; return 0; }
fsize() { _fs=$(stat -c %s "$1" 2>/dev/null); is_num "$_fs" || _fs=0; printf '%s' "$_fs"; }
fmt_num() { printf '%s\n' "${1:-0}" | awk '{ n = $1 ""; o = ""; while (length(n) > 3) { o = "," substr(n, length(n) - 2) o; n = substr(n, 1, length(n) - 3) } print n o }'; }
fmt_mb() { awk -v b="${1:-0}" 'BEGIN { printf "%.1f MB", b / 1048576 }'; }
clean_val() { printf '%s' "$1" | tr -d '\000-\037\134\177' | cut -c1-200; }
boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null; }
plural() { if [ "$1" = 1 ]; then printf '%s' "$2"; else printf '%s' "$3"; fi; }

count_lines() {
  R_LINES=0
  [ -s "$1" ] || return 0
  R_LINES=$(grep -c . "$1" 2>/dev/null)
  is_num "$R_LINES" || R_LINES=0
}

word_in() {
  case " $2 " in *" $1 "*) return 0 ;; esac
  return 1
}

ensure_dirs() {
  mkdir -p "$RULESD" "$METAD" "$LISTSD" "$BACKUPD" "$RUND" "$TMPD" 2>/dev/null
  chmod 0700 "$DATA" 2>/dev/null
  [ -f "$ALLOWF" ] || : > "$ALLOWF"
  [ -f "$BLOCKF" ] || : > "$BLOCKF"
  allow_seed
  block_seed
}

block_seed_one() {
  # 单份内置拦截清单合并。只写入精确域名规则行，注释/空行/通配不进入 block.list；
  # 空文件补齐全部规则，已有内容只补缺失条目，用户自定义规则永远保留。
  _bs_list=$1
  _bs_mig=$2
  [ -f "$_bs_list" ] || return 0
  [ -f "$_bs_mig" ] && return 0
  _bs_n=0
  _bs_fail=0
  while IFS= read -r _bs_l; do
    case $_bs_l in '' | '#'*) continue ;; esac
    case $_bs_l in *'*'*) continue ;; esac
    if ! grep -qxF -- "$_bs_l" "$BLOCKF" 2>/dev/null; then
      if [ -s "$BLOCKF" ] && [ -n "$(tail -c 1 "$BLOCKF" 2>/dev/null)" ]; then
        printf '\n' >> "$BLOCKF" 2>/dev/null || _bs_fail=1
      fi
      if printf '%s\n' "$_bs_l" >> "$BLOCKF" 2>/dev/null; then
        _bs_n=$((_bs_n + 1))
      else
        _bs_fail=1
      fi
    fi
  done < "$_bs_list"
  if [ "$_bs_fail" = 0 ]; then
    : > "$_bs_mig" 2>/dev/null || _bs_fail=1
  fi
  if [ "$_bs_fail" = 0 ] && [ "$_bs_n" -gt 0 ] && command -v log >/dev/null 2>&1; then
    log I "block_seed: 补入 $_bs_n 条内置拦截"
  fi
  return 0
}

block_seed() {
  # v1.1.3 基础集 + v1.1.4 ADN 补充集。两份 marker 独立，
  # 旧 seed-v1 不会阻止新版 ADN 规则写入；任一份失败可下次重试。
  [ -f "$BLOCKF" ] || : > "$BLOCKF" 2>/dev/null
  block_seed_one "$BLOCKD" "$BLOCKF.seed-v1"
  block_seed_one "$BLOCKD2" "$BLOCKF.seed-v2"
  return 0
}

allow_seed() {
  # 内置放行清单合并。只写入域名规则行，注释/空行不进入 allow.list；
  # 空文件补齐全部规则，已有内容只补缺失条目，用户自定义规则永远保留。
  [ -f "$ALLOWD" ] || return 0
  [ -f "$ALLOWF" ] || : > "$ALLOWF" 2>/dev/null
  # v1.1.2 迁移：v1.1.1 的整域放行项会连广告域一起放行，首次运行清理一次。
  _as_mig=$ALLOWF.seed-v2
  if [ ! -f "$_as_mig" ]; then
    _as_tmp=$ALLOWF.seedtmp.$$
    if grep -vxF -e '*.qq.com' -e '*.163.com' "$ALLOWF" > "$_as_tmp" 2>/dev/null; then
      _as_rc=0
    else
      _as_rc=$?
    fi
    if [ "$_as_rc" -eq 0 ] || [ "$_as_rc" -eq 1 ]; then
      if mv -f "$_as_tmp" "$ALLOWF" 2>/dev/null; then
        : > "$_as_mig" 2>/dev/null
      else
        rm -f "$_as_tmp" 2>/dev/null
      fi
    else
      rm -f "$_as_tmp" 2>/dev/null
    fi
  fi
  _as_n=0
  while IFS= read -r _as_l; do
    case $_as_l in '' | '#'*) continue ;; esac
    if ! grep -qxF -- "$_as_l" "$ALLOWF" 2>/dev/null; then
      if [ -s "$ALLOWF" ] && [ -n "$(tail -c 1 "$ALLOWF" 2>/dev/null)" ]; then
        printf '\n' >> "$ALLOWF" 2>/dev/null
      fi
      printf '%s\n' "$_as_l" >> "$ALLOWF" 2>/dev/null && _as_n=$((_as_n + 1))
    fi
  done < "$ALLOWD"
  if [ "$_as_n" -gt 0 ] && command -v log >/dev/null 2>&1; then
    log I "allow_seed: 补入 $_as_n 条内置放行"
  fi
  return 0
}

log() {
  _lg_m=$2
  case $_lg_m in *"$NL"* | *"$CR"* | *"$TAB"*) _lg_m=$(printf '%s' "$_lg_m" | tr '\r\n\t' '   ') ;; esac
  [ -d "$DATA" ] || return 0
  printf '%s|%s|%s\n' "$(date +%s)" "$1" "$_lg_m" >> "$LOGF" 2>/dev/null || return 0
  _lg_n=$(wc -l < "$LOGF" 2>/dev/null)
  if is_num "$_lg_n" && [ "$_lg_n" -gt "$LOG_MAX" ]; then
    tail -n "$LOG_MAX" "$LOGF" > "$LOGF.trim.$$" 2>/dev/null && mv -f "$LOGF.trim.$$" "$LOGF"
    rm -f "$LOGF.trim.$$" 2>/dev/null
  fi
  return 0
}

js() {
  case $1 in
    *\\* | *\"* | *"$NL"* | *"$CR"* | *"$TAB"* | *[[:cntrl:]]*) JS=$(printf '%s' "$1" | awk "$AWK_JESC") ;;
    *) JS="\"$1\"" ;;
  esac
}

jnum() { if is_num "$1"; then JN=$1; else JN=null; fi; }
jbool() { if [ "$1" = 1 ] || [ "$1" = true ]; then JB=true; else JB=false; fi; }

reply() {
  _rp_d=${4:-}
  [ -n "$_rp_d" ] || _rp_d='{}'
  js "$3"
  [ "$1" = true ] || HK_RC=1
  printf '{"ok":%s,"code":"%s","message":%s,"data":%s}\n' "$1" "$2" "$JS" "$_rp_d"
}

addons_clean() {
  R_ADDONS=
  for _ac in $1; do
    word_in "$_ac" "$R_ADDONS" && continue
    list_info "$_ac" || continue
    [ "$L_KIND" = addon ] || continue
    R_ADDONS="$R_ADDONS $_ac"
  done
  R_ADDONS=${R_ADDONS# }
}

cfg_load() {
  C_LIST=; C_ADDONS=; C_ENABLED=1; C_SETUP=; C_UPDATED=0; C_CHECKED=0; C_COUNT=0; C_DOMAINS=0
  C_LIVE=1; C_AUTO=0; C_GUARD=; C_ETAG=; C_SRCDATE=
  if [ -f "$CFG" ]; then
    while IFS= read -r _cf_l || [ -n "$_cf_l" ]; do
      _cf_v=${_cf_l#*=}
      case ${_cf_l%%=*} in
        LIST) C_LIST=$_cf_v ;;
        ADDONS) C_ADDONS=$_cf_v ;;
        ENABLED) C_ENABLED=$_cf_v ;;
        SETUP) C_SETUP=$_cf_v ;;
        UPDATED) C_UPDATED=$_cf_v ;;
        CHECKED) C_CHECKED=$_cf_v ;;
        COUNT) C_COUNT=$_cf_v ;;
        DOMAINS) C_DOMAINS=$_cf_v ;;
        LIVE) C_LIVE=$_cf_v ;;
        AUTO) C_AUTO=$_cf_v ;;
        GUARD) C_GUARD=$_cf_v ;;
        ETAG) C_ETAG=$_cf_v ;;
        SRCDATE) C_SRCDATE=$_cf_v ;;
      esac
    done < "$CFG"
  fi
  [ "$C_ENABLED" = 0 ] || C_ENABLED=1
  [ "$C_LIVE" = 0 ] || C_LIVE=1
  is_num "$C_UPDATED" || C_UPDATED=0
  is_num "$C_CHECKED" || C_CHECKED=0
  is_num "$C_COUNT" || C_COUNT=0
  is_num "$C_DOMAINS" || C_DOMAINS=0
  case $C_AUTO in 0 | 1 | 3 | 7) ;; *) C_AUTO=0 ;; esac
  case $C_SETUP in ready | pending | failed) ;; *) C_SETUP=ready ;; esac
  case $C_GUARD in *[!a-z0-9._-]*) C_GUARD= ;; esac
  addons_clean "$C_ADDONS"
  C_ADDONS=$R_ADDONS
  if ! list_info "$C_LIST" || [ "$L_KIND" != base ]; then
    C_LIST=stevenblack
    list_info "$C_LIST"
  fi
  return 0
}

cfg_save() {
  {
    printf 'LIST=%s\nADDONS=%s\nENABLED=%s\nSETUP=%s\n' "$C_LIST" "$C_ADDONS" "$C_ENABLED" "$C_SETUP"
    printf 'UPDATED=%s\nCHECKED=%s\nCOUNT=%s\nDOMAINS=%s\n' "$C_UPDATED" "$C_CHECKED" "$C_COUNT" "$C_DOMAINS"
    printf 'LIVE=%s\nAUTO=%s\nGUARD=%s\n' "$C_LIVE" "$C_AUTO" "$C_GUARD"
  } > "$CFG.tmp.$$" 2>/dev/null && mv -f "$CFG.tmp.$$" "$CFG"
}

src_load() {
  S_ETAG=; S_SRCDATE=; S_COUNT=0; S_SIZE=0; S_FETCHED=0
  [ -f "$LISTSD/$1.info" ] || return 1
  while IFS= read -r _sl_l || [ -n "$_sl_l" ]; do
    _sl_v=${_sl_l#*=}
    case ${_sl_l%%=*} in
      ETAG) S_ETAG=$_sl_v ;;
      SRCDATE) S_SRCDATE=$_sl_v ;;
      COUNT) S_COUNT=$_sl_v ;;
      SIZE) S_SIZE=$_sl_v ;;
      FETCHED) S_FETCHED=$_sl_v ;;
    esac
  done < "$LISTSD/$1.info"
  is_num "$S_COUNT" || S_COUNT=0
  is_num "$S_SIZE" || S_SIZE=0
  is_num "$S_FETCHED" || S_FETCHED=0
  return 0
}

src_write() {
  _sw_tmp="$1.tmp.$$"
  rm -f "$_sw_tmp"
  if printf 'ETAG=%s\nSRCDATE=%s\nCOUNT=%s\nSIZE=%s\nFETCHED=%s\n' "$2" "$3" "$4" "$5" "$(now)" > "$_sw_tmp" 2>/dev/null && mv -f "$_sw_tmp" "$1" 2>/dev/null; then
    return 0
  fi
  rm -f "$_sw_tmp" 2>/dev/null
  return 1
}

src_ready() {
  [ -s "$LISTSD/$1.domains" ] || return 1
  [ -f "$LISTSD/$1.info" ] || return 1
  src_load "$1" || return 1
  is_num "$S_COUNT" && [ "$S_COUNT" -gt 0 ]
}

src_file() {
  if [ -s "$STAGED/$1.domains" ]; then
    R_FILE=$STAGED/$1.domains
  elif [ -s "$LISTSD/$1.domains" ]; then
    R_FILE=$LISTSD/$1.domains
  else
    R_FILE=
    return 1
  fi
  return 0
}

sources_ready() {
  src_ready "$C_LIST" || return 1
  for _sr in $C_ADDONS; do src_ready "$_sr" || return 1; done
  return 0
}

migrate_data() {
  [ -f "$OLDCACHE" ] || return 0
  mkdir -p "$LISTSD" 2>/dev/null
  cfg_load
  if [ -s "$OLDCACHE" ] && [ ! -s "$LISTSD/$C_LIST.domains" ]; then
    ln "$OLDCACHE" "$LISTSD/$C_LIST.domains" 2>/dev/null || cp -f "$OLDCACHE" "$LISTSD/$C_LIST.domains" 2>/dev/null
    if [ -s "$LISTSD/$C_LIST.domains" ]; then
      src_write "$LISTSD/$C_LIST.info" "${C_ETAG#W/}" "$C_SRCDATE" "$C_COUNT" 0
      log INFO "已将缓存列表从 v1 布局迁移完成"
    fi
  fi
  [ "${1:-}" = keep ] || rm -f "$OLDCACHE"
  return 0
}

lock_pid() { _lp=; [ -f "$1/pid" ] && read -r _lp < "$1/pid"; printf '%s' "$_lp"; }

lock_alive() {
  [ -d "$1" ] || return 1
  _la=$(lock_pid "$1")
  if [ -z "$_la" ]; then
    _la_m=$(stat -c %Y "$1" 2>/dev/null)
    is_num "$_la_m" || return 1
    [ $(($(date +%s) - _la_m)) -lt 20 ]
    return
  fi
  [ -d "/proc/$_la" ] || return 1
  grep -q 'hostkeeper\.sh' "/proc/$_la/cmdline" 2>/dev/null || return 1
  return 0
}

lock_take() {
  if mkdir "$1" 2>/dev/null; then
    if printf '%s\n' "$$" > "$1/pid" 2>/dev/null && [ "$(lock_pid "$1")" = "$$" ]; then
      return 0
    fi
    [ -d "$1" ] && [ -z "$(lock_pid "$1")" ] && rm -rf "$1" 2>/dev/null
    return 1
  fi
  lock_alive "$1" && return 1
  _lt_stale="$1.stale.$$"
  if mv -f "$1" "$_lt_stale" 2>/dev/null; then
    if lock_alive "$_lt_stale"; then
      mv -f "$_lt_stale" "$1" 2>/dev/null
      rm -rf "$_lt_stale" 2>/dev/null
      return 1
    fi
    rm -rf "$_lt_stale" 2>/dev/null
  fi
  if mkdir "$1" 2>/dev/null; then
    if printf '%s\n' "$$" > "$1/pid" 2>/dev/null && [ "$(lock_pid "$1")" = "$$" ]; then
      return 0
    fi
    [ -d "$1" ] && [ -z "$(lock_pid "$1")" ] && rm -rf "$1" 2>/dev/null
    return 1
  fi
  return 1
}

lock_wait() {
  _lw=0
  while ! lock_take "$1"; do
    op_running && return 1
    [ "$_lw" -ge "${2:-12}" ] && return 1
    nap 0.25
    _lw=$((_lw + 1))
  done
  return 0
}

lock_drop_if_mine() { [ "$(lock_pid "$1")" = "$$" ] && rm -rf "$1" 2>/dev/null; return 0; }
lock_drop() { lock_drop_if_mine "$1"; }
lock_clear_stale() { lock_alive "$1" || rm -rf "$1" 2>/dev/null; return 0; }

busy_reply() { reply false busy '⏳ 另一个任务仍在运行，请等待它完成。'; }

op_load() {
  OP_KIND=; OP_LIST=; OP_PHASE=; OP_STATE=; OP_CODE=; OP_MSG=; OP_SEQ=0; OP_START=0; OP_END=0; OP_TOTAL=0
  OP_DOMAINS=0; OP_REBOOT=0; OP_LIVE=0; OP_ITEM=0; OP_ITEMS=0; OP_SRC=; OP_SRCNAME=; OP_WARN=0
  [ -f "$OPF" ] || return 0
  while IFS= read -r _ol_l || [ -n "$_ol_l" ]; do
    _ol_v=${_ol_l#*=}
    case ${_ol_l%%=*} in
      KIND) OP_KIND=$_ol_v ;;
      LIST) OP_LIST=$_ol_v ;;
      PHASE) OP_PHASE=$_ol_v ;;
      STATE) OP_STATE=$_ol_v ;;
      CODE) OP_CODE=$_ol_v ;;
      MSG) OP_MSG=$_ol_v ;;
      SEQ) OP_SEQ=$_ol_v ;;
      START) OP_START=$_ol_v ;;
      END) OP_END=$_ol_v ;;
      TOTAL) OP_TOTAL=$_ol_v ;;
      DOMAINS) OP_DOMAINS=$_ol_v ;;
      REBOOT) OP_REBOOT=$_ol_v ;;
      LIVE) OP_LIVE=$_ol_v ;;
      ITEM) OP_ITEM=$_ol_v ;;
      ITEMS) OP_ITEMS=$_ol_v ;;
      SRC) OP_SRC=$_ol_v ;;
      SRCNAME) OP_SRCNAME=$_ol_v ;;
      WARN) OP_WARN=$_ol_v ;;
    esac
  done < "$OPF"
}

op_save() {
  [ "$MODE" = install ] && return 0
  {
    printf 'KIND=%s\nLIST=%s\nPHASE=%s\nSTATE=%s\nCODE=%s\n' "$OP_KIND" "$OP_LIST" "$OP_PHASE" "$OP_STATE" "$OP_CODE"
    printf 'MSG=%s\nSEQ=%s\nSTART=%s\nEND=%s\nTOTAL=%s\n' "$OP_MSG" "$OP_SEQ" "$OP_START" "$OP_END" "$OP_TOTAL"
    printf 'DOMAINS=%s\nREBOOT=%s\nLIVE=%s\nITEM=%s\nITEMS=%s\n' "$OP_DOMAINS" "$OP_REBOOT" "$OP_LIVE" "$OP_ITEM" "$OP_ITEMS"
    printf 'SRC=%s\nSRCNAME=%s\nWARN=%s\n' "$OP_SRC" "$OP_SRCNAME" "$OP_WARN"
  } > "$OPF.tmp.$$" 2>/dev/null && mv -f "$OPF.tmp.$$" "$OPF"
}

op_begin() {
  _ob=0
  [ -f "$SEQF" ] && read -r _ob < "$SEQF"
  is_num "$_ob" || _ob=0
  _ob_n=$(now)
  if [ "$_ob_n" -gt "$_ob" ]; then _ob=$_ob_n; else _ob=$((_ob + 1)); fi
  echo "$_ob" > "$SEQF"
  OP_KIND=$1; OP_LIST=$2; OP_PHASE=prepare; OP_STATE=running; OP_CODE=; OP_MSG=
  OP_SEQ=$_ob; OP_START=$(now); OP_END=0; OP_TOTAL=0; OP_DOMAINS=0; OP_REBOOT=0; OP_LIVE=0
  OP_ITEM=0; OP_ITEMS=0; OP_SRC=; OP_SRCNAME=; OP_WARN=0
  rm -f "$DLPART" "$DLHDR" "$RUND/cancel"
  op_save
}

op_phase() { OP_PHASE=$1; op_save; }

op_finish() {
  OP_STATE=$1; OP_CODE=$2; OP_MSG=$3; OP_END=$(now)
  op_save
}

op_running() { [ -f "$OPF" ] && grep -q '^STATE=running$' "$OPF" 2>/dev/null; }

op_interrupt() {
  op_load
  OP_PHASE=; OP_STATE=error; OP_CODE=interrupted; OP_END=$(now); OP_MSG=$1
  op_save
}

op_reconcile() {
  op_running || return 0
  lock_alive "$LOCKD" && return 0
  op_interrupt '⚠️ The last task was interrupted. Your hosts file is intact — run it again to finish.'
  lock_clear_stale "$LOCKD"
  log WARN "后台任务意外停止，状态已重置"
}

op_json() {
  op_reconcile
  if [ ! -f "$OPF" ]; then
    R_OP='{"running":false,"state":"idle","seq":0}'
    return 0
  fi
  _oj_b=0
  [ -f "$DLPART" ] && _oj_b=$(fsize "$DLPART")
  _oj_a=0
  lock_alive "$LOCKD" && _oj_a=1
  _oj_c=0
  [ -f "$RUND/cancel" ] && _oj_c=1
  R_OP=$(awk -v bytes="$_oj_b" -v alive="$_oj_a" -v cancelling="$_oj_c" -v hdr="$DLHDR" "$AWK_OPJSON" "$OPF" 2>/dev/null)
  case $R_OP in
    '{'*'}') ;;
    *)
      if [ "$_oj_a" = 1 ]; then R_OP='{"running":true,"state":"running","seq":0}'; else R_OP='{"running":false,"state":"idle","seq":0}'; fi
      ;;
  esac
}

cancel_requested() { [ -f "$RUND/cancel" ]; }

kill_tree() {
  is_num "$1" || return 0
  has pkill && pkill -P "$1" 2>/dev/null
  kill "$1" 2>/dev/null
  return 0
}

spawn() {
  _sp_out=$1
  shift
  _sp_mark=$RUND/spawn.$$.$(date +%s)
  rm -f "$_sp_mark"
  if has setsid; then
    HK_SPAWN_MARK=$_sp_mark setsid sh "$SELF" "$@" < /dev/null > "$_sp_out" 2>&1 &
  else
    HK_SPAWN_MARK=$_sp_mark nohup sh "$SELF" "$@" < /dev/null > "$_sp_out" 2>&1 &
  fi
  _sp_p=$!
  _sp_i=0
  while [ "$_sp_i" -lt 50 ]; do
    if [ -f "$_sp_mark" ]; then
      rm -f "$_sp_mark"
      return 0
    fi
    nap 0.1
    _sp_i=$((_sp_i + 1))
  done
  kill_tree "$_sp_p"
  wait "$_sp_p" 2>/dev/null
  rm -f "$_sp_mark"
  log ERROR "后台工作进程 $* 未报告就绪，已终止进程 $_sp_p"
  return 1
}

spawned() { [ -n "${HK_SPAWN_MARK:-}" ] && : > "$HK_SPAWN_MARK"; unset HK_SPAWN_MARK; return 0; }

dl_detect() {
  [ -n "$DL_TOOL" ] && [ "$DL_TOOL" != none ] && return 0
  DL_GZ=0
  if has curl && _dd=$(curl --version 2>/dev/null) && [ -n "$_dd" ]; then
    DL_TOOL=curl
    case $_dd in *libz* | *zlib*) DL_GZ=1 ;; esac
  elif wget --help 2>&1 | grep -qi -e '--header'; then
    DL_TOOL=wget
  else
    DL_TOOL=none
    return 1
  fi
  return 0
}

hdr_parse() {
  _hp=$(awk "$AWK_HDR" "$1" 2>/dev/null)
  { read -r DL_CODE; read -r DL_CL; read -r DL_TOTAL; read -r DL_ETAG; read -r DL_LASTMOD; read -r DL_ENC; } << EOF
$_hp
EOF
  is_num "$DL_CODE" || DL_CODE=
  is_num "$DL_CL" || DL_CL=
  is_num "$DL_TOTAL" || DL_TOTAL=
  DL_ETAG=$(clean_val "$DL_ETAG")
  DL_LASTMOD=$(clean_val "$DL_LASTMOD")
  case $DL_ENC in *[!a-z0-9-]*) DL_ENC=other ;; esac
}

dl_get() {
  _dg_u=$1; _dg_o=$2; _dg_h=$3; _dg_m=$4
  rm -f "$_dg_o" "$_dg_h.err"
  : > "$_dg_h"
  DL_FAIL=; DL_ERR=; DL_CODE=; DL_CL=; DL_TOTAL=; DL_ETAG=; DL_LASTMOD=; DL_ENC=
  if [ "$DL_GUARD_PRIVATE" = 1 ]; then
    _dg_gh=${_dg_u#*://}
    _dg_gh=${_dg_gh%%/*}
    _dg_gh=${_dg_gh%%:*}
    if host_resolves_private "$_dg_gh"; then
      DL_FAIL=private_host
      DL_ERR="resolved to private address"
      return 1
    fi
    if [ "$DL_TOOL" != curl ]; then
      DL_FAIL=redirect_guard
      DL_ERR="wget cannot enforce custom-list redirect policy"
      return 1
    fi
  fi
  case $DL_TOOL in
    curl)
      set -- -sS -L -g --proto '=https' --proto-redir '=https' --max-redirs "${DL_MAX_REDIR:-5}" --connect-timeout 15 --speed-limit 1024 --speed-time 30 --max-filesize "$MAX_BYTES" -A "$UA" -D "$_dg_h" -o "$_dg_o"
      if [ "$_dg_m" = peek ]; then
        set -- "$@" -r 0-8191
        [ -n "${DL_MAX_TIME:-}" ] && set -- "$@" --max-time "$DL_MAX_TIME"
      elif [ "$DL_GZ" = 1 ]; then
        set -- "$@" --compressed
      fi
      curl "$@" "$_dg_u" 2> "$_dg_h.err" &
      ;;
    wget)
      if [ "$_dg_m" = peek ]; then
        sh -c 'wget -q -S -T 15 -U "$1" -O - "$2" 2> "$3" | head -c 8192 > "$4"' hostkeeper-peek "$UA" "$_dg_u" "$_dg_h" "$_dg_o" &
      else
        wget -q -S -T 15 -U "$UA" -O "$_dg_o" "$_dg_u" 2> "$_dg_h" &
      fi
      ;;
    *)
      DL_FAIL=network
      DL_ERR='no downloader available'
      return 1
      ;;
  esac
  _dg_p=$!
  [ -n "$DL_PIDF" ] && echo "$_dg_p" > "$DL_PIDF"
  if [ "$_dg_m" = full ] || [ "$DL_TOOL" = curl ]; then
    _dg_k=0
    while kill -0 "$_dg_p" 2>/dev/null; do
      if [ "$(fsize "$_dg_o")" -gt "$MAX_BYTES" ]; then
        kill_tree "$_dg_p"
        DL_FAIL=toolarge
        break
      fi
      if [ "$_dg_k" -lt 8 ]; then
        nap 0.05
        _dg_k=$((_dg_k + 1))
      else
        nap 0.2
      fi
    done
  fi
  wait "$_dg_p"
  _dg_rc=$?
  [ -n "$DL_PIDF" ] && rm -f "$DL_PIDF"
  if [ -z "$DL_FAIL" ] && [ "$DL_TOOL" = wget ] &&
     grep -qiE '^[[:space:]]*location:[[:space:]]*(http|ftp)://' "$_dg_h" 2>/dev/null; then
    DL_FAIL=insecure
  fi
  if [ -z "$DL_FAIL" ] && [ "$(fsize "$_dg_o")" -gt "$MAX_BYTES" ]; then
    DL_FAIL=toolarge
  fi
  hdr_parse "$_dg_h"
  if [ "$DL_TOOL" = curl ]; then
    DL_ERR=$(head -n 1 "$_dg_h.err" 2>/dev/null)
  else
    DL_ERR=$(grep '^wget:' "$_dg_h" 2>/dev/null | grep -v 'certificate validation' | head -n 1)
  fi
  DL_ERR=$(clean_val "$DL_ERR")
  rm -f "$_dg_h.err"
  if [ -z "$DL_FAIL" ]; then
    if [ "$_dg_rc" = 63 ] && [ "$DL_TOOL" = curl ]; then
      DL_FAIL=toolarge
    elif [ -z "$DL_CODE" ]; then
      DL_FAIL=network
    elif [ "$_dg_rc" -eq 47 ] && [ "$DL_MAX_REDIR" = 0 ]; then
      DL_FAIL=redirect
    elif [ "$DL_CODE" != 200 ] && [ "$DL_CODE" != 206 ]; then
      DL_FAIL=http
    elif [ "$_dg_rc" -ne 0 ] && [ "$_dg_m" = full ]; then
      DL_FAIL=incomplete
    fi
  fi
  [ -z "$DL_FAIL" ]
}

dl_reason() {
  case $DL_FAIL in
    http) printf 'HTTP %s' "$DL_CODE" ;;
    insecure) printf '拒绝了不安全的跳转' ;;
    redirect) printf '自定义列表不允许跳转，请填写最终地址' ;;
    private_host) printf '域名解析到了本地或私有地址' ;;
    redirect_guard) printf '设备下载工具无法安全校验自定义列表跳转' ;;
    toolarge) printf '文件超过 %s MB' "$((MAX_BYTES / 1048576))" ;;
    incomplete) printf '传输中断%s' "${DL_ERR:+ ($DL_ERR)}" ;;
    *) printf '无法连接%s' "${DL_ERR:+ ($DL_ERR)}" ;;
  esac
}

source_error_text() {
  case $1 in
    network) printf '网络连接失败' ;;
    http) printf '源站返回异常状态' ;;
    insecure) printf '下载跳转到了非 HTTPS 地址' ;;
    redirect) printf '自定义列表不允许跳转，请填写最终地址' ;;
    private_host) printf '域名解析到了本地或私有地址' ;;
    redirect_guard) printf '设备下载工具不支持自定义列表安全校验' ;;
    toolarge) printf '文件超过体积上限' ;;
    incomplete) printf '下载传输中断' ;;
    count_unavailable) printf '已下载，但无法识别条目数量' ;;
    no_downloader) printf '设备上没有可用的下载工具' ;;
    *) printf '获取失败' ;;
  esac
}

dl_fetch_any() {
  _dfa_o=$1; _dfa_h=$2; _dfa_m=$3
  shift 3
  _dfa_n=0
  for _dfa_u in "$@"; do
    [ -n "$_dfa_u" ] || continue
    _dfa_n=$((_dfa_n + 1))
    if [ "$_dfa_n" -eq 1 ]; then
      _dfa_retry=2
    else
      _dfa_retry=1
      log WARN "主源失败，尝试备用源：$_dfa_u"
    fi
    if dl_fetch "$_dfa_u" "$_dfa_o" "$_dfa_h" "$_dfa_m" "$_dfa_retry"; then
      DL_USED_URL=$_dfa_u
      return 0
    fi
  done
  return 1
}

dl_fetch() {
  _df_t=1
  _df_max=${5:-3}
  while :; do
    dl_get "$1" "$2" "$3" "$4" && return 0
    case $DL_FAIL in
      toolarge) return 1 ;;
      insecure) return 1 ;;
      http) case $DL_CODE in 408 | 425 | 429 | 5??) ;; *) return 1 ;; esac ;;
    esac
    [ "$_df_t" -ge "$_df_max" ] && return 1
    cancel_requested && return 1
    [ "$MODE" = install ] || log WARN "第 $_df_t 次下载尝试失败：$(dl_reason)，正在重试"
    nap $((_df_t * 2))
    cancel_requested && return 1
    _df_t=$((_df_t + 1))
  done
}

looks_html() {
  head -c 4096 "$1" 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -q -e '<!doctype' -e '<html' -e '<head' -e '<body' -e '<title'
}

head_info() {
  _hi=$(head -c 8192 "$1" 2>/dev/null | awk "$AWK_HEAD")
  { read -r HI_COUNT; read -r HI_DATE; } << EOF
$_hi
EOF
  is_num "$HI_COUNT" || HI_COUNT=
  HI_DATE=$(clean_val "$HI_DATE")
}

date_epoch() { [ -n "$1" ] && printf '%s\n' "$1" | awk "$AWK_DATE"; return 0; }

free_kb() { df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $4 }'; }

set_hosts_perm() {
  chmod 0644 "$1" 2>/dev/null
  chown 0:0 "$1" 2>/dev/null
  chcon u:object_r:system_file:s0 "$1" 2>/dev/null
  return 0
}

hosts_sane() {
  [ -s "$1" ] || return 1
  _hs_a=; _hs_b=
  { IFS= read -r _hs_a; IFS= read -r _hs_b; } < "$1"
  [ "$_hs_a" = "$LOCAL_LINE" ] && [ "$_hs_b" = "$LOCAL6_LINE" ]
}

sum_calc() {
  R_SUM=
  if has cksum; then
    R_SUM=$(cksum < "$1" 2>/dev/null)
    R_SUM=cksum:${R_SUM%% *}
  elif has md5sum; then
    R_SUM=$(md5sum < "$1" 2>/dev/null)
    R_SUM=md5:${R_SUM%% *}
  else
    R_SUM=size:$(fsize "$1")
  fi
  case $R_SUM in *:) R_SUM= ;; esac
}

sum_record() {
  sum_calc "$HOSTS"
  [ -n "$R_SUM" ] || { rm -f "$SUMF"; return 0; }
  printf 'SUM=%s\nCOUNT=%s\nSIZE=%s\n' "$R_SUM" "$1" "$(fsize "$HOSTS")" > "$SUMF.tmp.$$" 2>/dev/null && mv -f "$SUMF.tmp.$$" "$SUMF"
  return 0
}

sum_check() {
  _sc_s=; _sc_z=
  [ -f "$SUMF" ] || return 2
  while IFS= read -r _sc_l || [ -n "$_sc_l" ]; do
    case ${_sc_l%%=*} in
      SUM) _sc_s=${_sc_l#*=} ;;
      SIZE) _sc_z=${_sc_l#*=} ;;
    esac
  done < "$SUMF"
  [ -n "$_sc_s" ] || return 2
  [ "$(fsize "$HOSTS")" = "$_sc_z" ] || return 1
  case $_sc_s in
    cksum:*) has cksum || return 2 ;;
    md5:*) has md5sum || return 2 ;;
    size:*) return 0 ;;
    *) return 2 ;;
  esac
  sum_calc "$HOSTS"
  case $R_SUM in "${_sc_s%%:*}":*) ;; *) return 2 ;; esac
  [ "$R_SUM" = "$_sc_s" ]
}

stats_read() {
  ST_TOTAL=0; ST_BASE=0; ST_ALLOWED=0; ST_BLOCKED=0; ST_GUARDED=0; ST_ADDONS=; ST_IDS=; ST_LIST=
  for _st_f in "$CACHED/merge.info" "$STATF"; do
    [ -f "$_st_f" ] || continue
    while IFS= read -r _st_l || [ -n "$_st_l" ]; do
      _st_v=${_st_l#*=}
      case ${_st_l%%=*} in
        TOTAL) ST_TOTAL=$_st_v ;;
        BASE) ST_BASE=$_st_v ;;
        ALLOWED) ST_ALLOWED=$_st_v ;;
        BLOCKED) ST_BLOCKED=$_st_v ;;
        GUARDED) ST_GUARDED=$_st_v ;;
        ADDON[0-9]*) ST_ADDONS="$ST_ADDONS $_st_v" ;;
        IDS) ST_IDS=$_st_v ;;
        LIST) ST_LIST=$_st_v ;;
      esac
    done < "$_st_f"
  done
  ST_ADDONS=${ST_ADDONS# }
  is_num "$ST_TOTAL" || ST_TOTAL=0
  is_num "$ST_BASE" || ST_BASE=0
  is_num "$ST_ALLOWED" || ST_ALLOWED=0
  is_num "$ST_BLOCKED" || ST_BLOCKED=0
  is_num "$ST_GUARDED" || ST_GUARDED=0
  return 0
}

guard_detect() {
  R_GUARD=
  [ -x /system/bin/settings ] || return 0
  _gd_m=$(timeout 3 /system/bin/settings get global private_dns_mode 2>/dev/null)
  [ "$_gd_m" = hostname ] || return 0
  _gd_h=$(timeout 3 /system/bin/settings get global private_dns_specifier 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' \r\n')
  case $_gd_h in '' | null | *[!a-z0-9._-]*) return 0 ;; esac
  printf '%s\n' "$_gd_h" | awk "$AWK_VALID" && R_GUARD=$_gd_h
  return 0
}

merge_fresh() {
  _mg_l=; _mg_i=
  [ -f "$1/merge.info" ] || return 1
  while IFS= read -r _mg_r || [ -n "$_mg_r" ]; do
    case ${_mg_r%%=*} in
      LIST) _mg_l=${_mg_r#*=} ;;
      IDS) _mg_i=${_mg_r#*=} ;;
    esac
  done < "$1/merge.info"
  [ "$_mg_l" = "$C_LIST" ] && [ "$_mg_i" = "$C_ADDONS" ] || return 1
  [ -z "$C_ADDONS" ] || [ -f "$1/extras.domains" ]
}

merge_sources() {
  _mg_d=$1
  src_file "$C_LIST" || return 1
  _mg_b=$R_FILE
  rm -f "$_mg_d/extras.domains" "$_mg_d/merge.info" "$_mg_d/merge.tmp"
  if [ -z "$C_ADDONS" ]; then
    _mg_n=$(grep -c . "$_mg_b" 2>/dev/null)
    is_num "$_mg_n" || return 1
    printf 'BASE=%s\nLIST=%s\nIDS=\n' "$_mg_n" "$C_LIST" > "$_mg_d/merge.info" 2>/dev/null || return 1
    return 0
  fi
  _mg_a=
  for _mg_x in $C_ADDONS; do
    src_file "$_mg_x" || return 1
    _mg_a="$_mg_a $R_FILE"
  done
  awk -v addons="${_mg_a# }" -v outf="$_mg_d/extras.domains" -v statf="$_mg_d/merge.tmp" "$AWK_MERGE" "$_mg_b" 2>/dev/null || { rm -f "$_mg_d/extras.domains" "$_mg_d/merge.tmp"; return 1; }
  [ -f "$_mg_d/extras.domains" ] || : > "$_mg_d/extras.domains" 2>/dev/null || return 1
  [ -f "$_mg_d/extras.domains" ] && [ -s "$_mg_d/merge.tmp" ] || return 1
  printf 'LIST=%s\nIDS=%s\n' "$C_LIST" "$C_ADDONS" >> "$_mg_d/merge.tmp" 2>/dev/null || return 1
  mv -f "$_mg_d/merge.tmp" "$_mg_d/merge.info"
}

stage_commit() {
  _stc_prev="$CACHED.prev.$$"
  _stc_ok=1
  rm -rf "$_stc_prev"
  mkdir -p "$_stc_prev" || return 1
  if [ -d "$CACHED" ]; then
    cp -r "$CACHED/." "$_stc_prev/" 2>/dev/null || { rm -rf "$_stc_prev"; return 1; }
  fi
  for _stc_f in "$STAGED"/*.domains; do
    [ -f "$_stc_f" ] || continue
    [ "$_stc_f" = "$STAGED/extras.domains" ] && continue
    _stc_id=${_stc_f##*/}
    _stc_id=${_stc_id%.domains}
    mv -f "$_stc_f" "$LISTSD/$_stc_id.domains" || _stc_ok=0
    if [ -f "$STAGED/$_stc_id.info" ]; then
      mv -f "$STAGED/$_stc_id.info" "$LISTSD/$_stc_id.info" || _stc_ok=0
    else
      _stc_ok=0
    fi
  done
  rm -f "$CACHED/extras.domains"
  [ -f "$STAGED/extras.domains" ] && { mv -f "$STAGED/extras.domains" "$CACHED/extras.domains" || _stc_ok=0; }
  if [ -f "$STAGED/merge.info" ]; then
    mv -f "$STAGED/merge.info" "$CACHED/merge.info" || _stc_ok=0
  else
    _stc_ok=0
  fi
  if [ "$_stc_ok" != 1 ]; then
    rm -rf "$CACHED"
    if ! mv -f "$_stc_prev" "$CACHED" 2>/dev/null; then
      log ERROR "缓存回滚失败，已保留之前的缓存于 $_stc_prev"
      return 1
    fi
    return 1
  fi
  rm -rf "$_stc_prev"
  for _stc_f in "$LISTSD"/*.domains; do
    [ -f "$_stc_f" ] || continue
    _stc_id=${_stc_f##*/}
    _stc_id=${_stc_id%.domains}
    word_in "$_stc_id" "$PL_BASE $PL_ADDONS" && continue
    rm -f "$_stc_f" "$LISTSD/$_stc_id.info" 2>/dev/null
  done
  return 0
}

compile_into() {
  _ci_o=$1
  CH_COUNT=0
  rm -f "$TMPD/compile.stats"
  if [ "$2" != 1 ]; then
    printf '%s\n%s\n' "$LOCAL_LINE" "$LOCAL6_LINE" > "$_ci_o" 2>/dev/null || return 1
    return 0
  fi
  src_file "$C_LIST" || return 1
  _ci_b=$R_FILE
  _ci_x=
  if merge_fresh "$STAGED"; then
    _ci_x=$STAGED/extras.domains
  else
    merge_fresh "$CACHED" || merge_sources "$CACHED" || return 1
    _ci_x=$CACHED/extras.domains
  fi
  [ -n "$C_ADDONS" ] || _ci_x=
  case $MODE in
    boot) ;;
    *) guard_detect; C_GUARD=$R_GUARD ;;
  esac
  if [ -n "$_ci_x" ]; then
    awk -F. -v allowf="$ALLOWF" -v blockf="$BLOCKF" -v statf="$TMPD/compile.stats" -v guard="$C_GUARD" -v local4="$LOCAL_LINE" -v local6="$LOCAL6_LINE" "$AWK_COMPILE" "$_ci_b" "$_ci_x" > "$_ci_o" 2>/dev/null || return 1
  else
    awk -F. -v allowf="$ALLOWF" -v blockf="$BLOCKF" -v statf="$TMPD/compile.stats" -v guard="$C_GUARD" -v local4="$LOCAL_LINE" -v local6="$LOCAL6_LINE" "$AWK_COMPILE" "$_ci_b" > "$_ci_o" 2>/dev/null || return 1
  fi
  CH_COUNT=$(sed -n 's/^TOTAL=//p' "$TMPD/compile.stats" 2>/dev/null)
  is_num "$CH_COUNT" || return 1
  return 0
}

stats_commit() {
  if [ -f "$TMPD/compile.stats" ]; then
    mv -f "$TMPD/compile.stats" "$STATF" 2>/dev/null
  else
    rm -f "$STATF"
  fi
  return 0
}

put_hosts() {
  if [ "${2:-}" = inplace ] && [ "$MODE" != install ] && [ -f "$HOSTS" ]; then
    _ph_tmp="$HOSTS.hkinplace.$$"
    rm -f "$_ph_tmp"
    if cp -f "$1" "$_ph_tmp" 2>/dev/null && cmp -s "$1" "$_ph_tmp" && set_hosts_perm "$_ph_tmp" && mv -f "$_ph_tmp" "$HOSTS"; then
      rm -f "$1"
      set_hosts_perm "$HOSTS"
      return 0
    fi
    rm -f "$_ph_tmp"
    return 1
  fi
  set_hosts_perm "$1"
  if mv -f "$1" "$HOSTS"; then
    set_hosts_perm "$HOSTS"
    return 0
  fi
  rm -f "$1"
  return 1
}

write_clean_hosts() {
  mkdir -p "$HOSTSD"
  printf '%s\n%s\n' "$LOCAL_LINE" "$LOCAL6_LINE" > "$HOSTSD/.hosts.hkclean" && put_hosts "$HOSTSD/.hosts.hkclean" inplace && sum_record 0
}

backup_hosts() {
  hosts_sane "$HOSTS" || return 0
  rm -f "$BACKUPD/hosts.3" "$BACKUPD/hosts.3.gz"
  for _bk in 2 1; do
    for _bk_e in '' .gz; do
      [ -f "$BACKUPD/hosts.$_bk$_bk_e" ] && mv -f "$BACKUPD/hosts.$_bk$_bk_e" "$BACKUPD/hosts.$((_bk + 1))$_bk_e"
    done
  done
  if has gzip && gzip -c "$HOSTS" > "$BACKUPD/hosts.1.gz" 2>/dev/null && [ -s "$BACKUPD/hosts.1.gz" ]; then
    return 0
  fi
  rm -f "$BACKUPD/hosts.1.gz"
  cp -f "$HOSTS" "$BACKUPD/hosts.1" 2>/dev/null || rm -f "$BACKUPD/hosts.1"
  return 0
}

restore_backup() {
  for _rb in 1 2 3; do
    rm -f "$HOSTSD/.hosts.hkrestore"
    if [ -f "$BACKUPD/hosts.$_rb.gz" ]; then
      gzip -dc "$BACKUPD/hosts.$_rb.gz" > "$HOSTSD/.hosts.hkrestore" 2>/dev/null || continue
    elif [ -f "$BACKUPD/hosts.$_rb" ]; then
      cp -f "$BACKUPD/hosts.$_rb" "$HOSTSD/.hosts.hkrestore" 2>/dev/null || continue
    else
      continue
    fi
    hosts_sane "$HOSTSD/.hosts.hkrestore" || continue
    if put_hosts "$HOSTSD/.hosts.hkrestore" inplace; then
      rm -f "$SUMF"
      log WARN "已从备份 $_rb 恢复之前的 hosts 文件"
      return 0
    fi
  done
  rm -f "$HOSTSD/.hosts.hkrestore"
  write_clean_hosts
  log ERROR "未找到可用备份，已写入仅含 localhost 的干净 hosts 文件"
  return 1
}

verify_hosts() {
  hosts_sane "$HOSTS" || return 1
  _vh=$(wc -l < "$HOSTS" 2>/dev/null)
  is_num "$_vh" && [ "$_vh" -eq $(($1 + 2)) ]
}

verify_hosts_file() {
  [ -s "$1" ] || return 1
  awk -v want="$2" -v local4="$LOCAL_LINE" -v local6="$LOCAL6_LINE" "$AWK_VERIFY" "$1" 2>/dev/null
}

verify_hosts_deep() { verify_hosts_file "$HOSTS" "$1"; }

install_hosts() {
  IH_CHANGED=1
  mkdir -p "$HOSTSD"
  if [ -f "$HOSTS" ] && [ "$(fsize "$1")" = "$(fsize "$HOSTS")" ] && cmp -s "$1" "$HOSTS"; then
    rm -f "$1"
    IH_CHANGED=0
    if [ -f "$SUMF" ]; then
      sum_check || sum_record "$2"
    else
      sum_record "$2"
    fi
    return 0
  fi
  [ "${3:-}" = backup ] && backup_hosts
  _ih=
  [ "$C_LIVE" = 1 ] && _ih=inplace
  if ! put_hosts "$1" "$_ih"; then
    restore_backup
    return 1
  fi
  if ! verify_hosts "$2"; then
    log ERROR "新的 hosts 文件校验失败"
    restore_backup
    return 2
  fi
  sum_record "$2"
  return 0
}

live_hosts() {
  if head -c 1 "$INIT_HOSTS" > /dev/null 2>&1; then R_LIVE=$INIT_HOSTS; else R_LIVE=$SYS_HOSTS; fi
}

hosts_live() {
  [ -f "$HOSTS" ] || return 1
  live_hosts
  [ "$R_LIVE" -ef "$HOSTS" ] && return 0
  cmp -s "$R_LIVE" "$HOSTS"
}

mark_pending() { boot_id > "$PENDF.tmp" 2>/dev/null && mv -f "$PENDF.tmp" "$PENDF"; return 0; }

pending_flag() {
  [ -f "$PENDF" ] || return 1
  [ "$(cat "$PENDF" 2>/dev/null)" = "$(boot_id)" ]
}

repair_hosts() {
  if hosts_sane "$HOSTS"; then
    [ "${1:-}" = deep ] || return 0
    cfg_load
    sum_check
    if [ $? -eq 0 ] && verify_hosts_deep "$C_DOMAINS"; then
      return 0
    fi
    log WARN "hosts 文件不完整或校验和不匹配，正在重建"
  fi
  mkdir -p "$HOSTSD"
  rm -f "$HOSTSD/.hosts.hknew"
  cfg_load
  _rh=0
  if [ "$C_ENABLED" != 1 ]; then
    compile_into "$HOSTSD/.hosts.hknew" 0 && _rh=1
  elif [ "$C_SETUP" = ready ] && sources_ready; then
    compile_into "$HOSTSD/.hosts.hknew" 1 && _rh=1
  fi
  if [ "$_rh" = 1 ] && hosts_sane "$HOSTSD/.hosts.hknew" && verify_hosts_file "$HOSTSD/.hosts.hknew" "$CH_COUNT"; then
    if put_hosts "$HOSTSD/.hosts.hknew" inplace; then
      C_DOMAINS=$CH_COUNT
      cfg_save
      stats_commit
      sum_record "$CH_COUNT"
      log WARN "hosts 文件缺失或损坏，已使用缓存列表重建"
      return 0
    fi
  fi
  rm -f "$HOSTSD/.hosts.hknew"
  if write_clean_hosts; then
    C_DOMAINS=0
    [ "$C_ENABLED" = 1 ] && C_SETUP=pending
    cfg_save
    log WARN "hosts 文件缺失或损坏，已写入仅含 localhost 的干净文件"
    return 0
  fi
  C_DOMAINS=0
  [ "$C_ENABLED" = 1 ] && C_SETUP=pending
  cfg_save
  rm -f "$SUMF"
  log ERROR "hosts 文件缺失或损坏，且无法写入干净的兜底文件"
  return 1
}

in_init_ns() {
  _ns_s=$(readlink /proc/self/ns/mnt 2>/dev/null)
  [ -n "$_ns_s" ] && [ "$_ns_s" = "$(readlink "$INIT_NS" 2>/dev/null)" ]
}

bind_hosts() {
  if in_init_ns; then
    mount -o bind "$HOSTS" "$MOUNT_TARGET" 2>/dev/null && return 0
  fi
  if [ "$HK_BB" != none ]; then
    "$HK_BB" nsenter -t 1 -m -- "$HK_BB" mount -o bind "$HOSTS" "$MOUNT_TARGET" 2>/dev/null && return 0
  fi
  if [ -x /system/bin/nsenter ]; then
    /system/bin/nsenter -t 1 -m -- /system/bin/mount -o bind "$HOSTS" "$MOUNT_TARGET" 2>/dev/null && return 0
  fi
  in_init_ns || mount -o bind "$HOSTS" "$MOUNT_TARGET" 2>/dev/null
}

mount_record() {
  printf '%s\n%s\n' "$(boot_id)" "$1" > "$MOUNTF.tmp.$$" 2>/dev/null && mv -f "$MOUNTF.tmp.$$" "$MOUNTF"
  return 0
}

mount_mode() {
  _mm_b=; R_MOUNT=
  [ -f "$MOUNTF" ] && { read -r _mm_b; read -r R_MOUNT; } < "$MOUNTF"
  [ "$_mm_b" = "$(boot_id)" ] || R_MOUNT=
}

conflicts_scan() {
  R_CONF=
  for _cf_d in "$MODROOT"/*; do
    [ -d "$_cf_d" ] || continue
    _cf_i=${_cf_d##*/}
    [ "$_cf_i" = hostkeeper ] && continue
    [ -f "$_cf_d/system/etc/hosts" ] || continue
    [ -f "$_cf_d/disable" ] && continue
    [ -f "$_cf_d/remove" ] && continue
    case $_cf_i in *[!A-Za-z0-9._-]*) continue ;; esac
    R_CONF="$R_CONF $_cf_i"
  done
  R_CONF=${R_CONF# }
}

ensure_mounted() {
  [ -f "$HOSTS" ] || return 0
  mount_mode
  if hosts_live; then
    case $R_MOUNT in manager | self) ;; *) mount_record manager ;; esac
    return 0
  fi
  conflicts_scan
  if [ -n "$R_CONF" ]; then
    [ "${1:-}" = quiet ] && return 1
    [ "$R_MOUNT" = conflict ] || log WARN "另一个模块也替换了 /system/etc/hosts（$R_CONF），HostKeeper 未改动它"
    mount_record conflict
    return 1
  fi
  set_hosts_perm "$HOSTS"
  if bind_hosts && hosts_live; then
    mount_record self
    log INFO "Root 管理器未应用 HostKeeper 的 hosts 文件，已由 HostKeeper 直接挂载"
    return 0
  fi
  [ "${1:-}" = quiet ] && return 1
  [ "$R_MOUNT" = failed ] || log ERROR "无法将 hosts 文件挂载到 /system/etc/hosts"
  mount_record failed
  return 1
}

apply_now() {
  IH_LIVE=0
  [ "$MODE" = install ] && return 1
  if hosts_live; then
    IH_LIVE=1
    rm -f "$PENDF"
    return 0
  fi
  [ "$C_LIVE" = 1 ] || return 1
  if ensure_mounted quiet; then
    IH_LIVE=1
    rm -f "$PENDF"
    return 0
  fi
  return 1
}

settle_change() {
  if apply_now; then
    flush_dns
    return 0
  fi
  mark_pending
  return 1
}

applied_state() {
  if [ ! -f "$HOSTS" ]; then R_APPLIED=unknown; return 0; fi
  if hosts_live; then
    R_APPLIED=applied
  elif pending_flag; then
    R_APPLIED=pending
  else
    conflicts_scan
    if [ -n "$R_CONF" ]; then R_APPLIED=overridden; else R_APPLIED=inactive; fi
  fi
}

describe() {
  cfg_load
  case $C_SETUP in
    pending) R_DESC="🛡️ ⏳ 等待初始化 • 联网后会自动下载 $L_NAME"; return 0 ;;
    failed) R_DESC='🛡️ ❌ Setup incomplete • Open the WebUI and tap Download now to finish setup'; return 0 ;;
  esac
  applied_state
  _ds_x=
  if [ -n "$C_ADDONS" ]; then
    set -- $C_ADDONS
    _ds_x=" + $# $(plural "$#" add-on add-ons)"
  fi
  if [ "$R_APPLIED" = pending ]; then
    if [ "$C_ENABLED" = 1 ]; then
      R_DESC="🛡️ 🟡 需要重启 • $L_NAME$_ds_x • 已就绪 $(fmt_num "$C_DOMAINS") 个域名"
    else
      R_DESC='🛡️ 🟡 Reboot required • Blocking will be turned off'
    fi
  elif [ "$C_ENABLED" != 1 ]; then
    R_DESC="🛡️ 🔴 已停用 • $L_NAME 已暂停"
  elif [ "$R_APPLIED" = overridden ]; then
    R_DESC='🛡️ ⚠️ Overridden • Another module replaces /system/etc/hosts'
  elif [ "$R_APPLIED" = inactive ]; then
    R_DESC="🛡️ 🔴 未生效 • 重启后激活 $L_NAME"
  else
    R_DESC="🛡️ 🟢 已启用 • $L_NAME$_ds_x • 已拦截 $(fmt_num "$C_DOMAINS") 个域名"
  fi
}

set_description() {
  [ -f "$PROP" ] || return 0
  describe
  awk -v d="$R_DESC" 'BEGIN { f = 0 } /^description=/ { if (!f) print "description=" d; f = 1; next } { print } END { if (!f) print "description=" d }' "$PROP" > "$PROP.hktmp" 2>/dev/null && mv -f "$PROP.hktmp" "$PROP"
  chmod 0644 "$PROP" 2>/dev/null
  return 0
}

flush_dns() {
  _fd=
  if [ -x /system/bin/ndc ]; then
    case $(/system/bin/ndc resolver flushdefaultif 2>&1) in 200*) _fd='flushdefaultif' ;; esac
    _fd_ip=/system/bin/ip
    [ -x "$_fd_ip" ] || _fd_ip=ip
    for _fd_n in $("$_fd_ip" rule 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "fwmark" && $(i + 1) ~ /^0x1[0-9a-f][0-9a-f][0-9a-f][0-9a-f]\/0x1ffff$/) print substr($(i + 1), 4, 4) }' | sort -u); do
      _fd_id=$((0x$_fd_n))
      case $(/system/bin/ndc resolver flushnet "$_fd_id" 2>&1) in 200*) _fd="${_fd:+$_fd, }flushnet $_fd_id" ;; esac
    done
  fi
  [ -n "$_fd" ] && log INFO "DNS 缓存已刷新（$_fd）"
  return 0
}

detect_manager() {
  MGR_NAME=; MGR_VER=; MGR_HTTPD=
  _dm_b=$(boot_id)
  if [ -f "$RUND/manager" ]; then
    { read -r _dm_c; read -r MGR_NAME; read -r MGR_VER; read -r MGR_HTTPD; } < "$RUND/manager"
    [ "$_dm_c" = "$_dm_b" ] && [ -n "$MGR_NAME" ] && [ -n "$MGR_HTTPD" ] && return 0
  fi
  _dm=
  if [ "${APATCH:-}" = true ]; then _dm=apatch
  elif [ "${KSU:-}" = true ]; then _dm=ksu
  elif [ -n "${MAGISK_VER:-}" ]; then _dm=magisk
  elif has magisk; then _dm=magisk
  elif [ -x /data/adb/apd ]; then _dm=apatch
  elif [ -x /data/adb/ksud ]; then _dm=ksu
  elif [ -d /data/adb/magisk ]; then _dm=magisk
  fi
  case $_dm in
    apatch)
      MGR_NAME=APatch
      MGR_VER=${APATCH_VER:-$(timeout 3 /data/adb/apd -V 2>/dev/null | head -n 1)}
      ;;
    ksu)
      if [ -d /data/data/com.sukisu.ultra ]; then
        MGR_NAME='SukiSU Ultra'
      elif [ -d /data/data/com.rifsxd.ksunext ]; then
        MGR_NAME='KernelSU Next'
      else
        MGR_NAME=KernelSU
      fi
      MGR_VER=${KSU_VER:-$(timeout 3 /data/adb/ksud -V 2>/dev/null | head -n 1)}
      ;;
    magisk)
      MGR_NAME=Magisk
      MGR_VER=${MAGISK_VER:-$(timeout 3 magisk -v 2>/dev/null | head -n 1)}
      MGR_VER=${MGR_VER%%:*}
      ;;
    *) MGR_NAME=Unknown ;;
  esac
  case $MGR_VER in *' '*) MGR_VER=${MGR_VER##* } ;; esac
  MGR_VER=$(clean_val "$MGR_VER")
  MGR_HTTPD=no
  [ "$HK_BB" != none ] && "$HK_BB" --list 2>/dev/null | grep -qx httpd && MGR_HTTPD=yes
  [ -d "$RUND" ] && printf '%s\n%s\n%s\n%s\n' "$_dm_b" "$MGR_NAME" "$MGR_VER" "$MGR_HTTPD" > "$RUND/manager" 2>/dev/null
  return 0
}

httpd_available() {
  [ -n "${MGR_HTTPD:-}" ] || detect_manager
  [ "$MGR_HTTPD" = yes ]
}

device_addon() {
  R_DEVADDON=
  _da_b=$(boot_id)
  if [ -f "$RUND/device" ]; then
    { read -r _da_c; read -r R_DEVADDON; } < "$RUND/device"
    [ "$_da_c" = "$_da_b" ] && return 0
  fi
  _da=$(getprop ro.product.brand 2>/dev/null; getprop ro.product.manufacturer 2>/dev/null)
  _da=$(printf '%s' "$_da" | tr '[:upper:]\n' '[:lower:] ')
  R_DEVADDON=
  case $_da in
    *xiaomi* | *redmi* | *poco*) R_DEVADDON=hagezi-xiaomi ;;
    *samsung*) R_DEVADDON=hagezi-samsung ;;
    *huawei* | *honor*) R_DEVADDON=hagezi-huawei ;;
    *oppo* | *realme* | *oneplus*) R_DEVADDON=hagezi-oppo ;;
    *vivo* | *iqoo*) R_DEVADDON=hagezi-vivo ;;
    *amazon*) R_DEVADDON=hagezi-amazon ;;
  esac
  [ -d "$RUND" ] && printf '%s\n%s\n' "$_da_b" "$R_DEVADDON" > "$RUND/device" 2>/dev/null
  return 0
}

open_url() {
  [ -x /system/bin/am ] || return 1
  _ou=$(/system/bin/am start -a android.intent.action.VIEW -d "$1" 2>&1) || return 1
  case $_ou in *Error* | *error:* | *Exception*) return 1 ;; esac
  return 0
}

meta_load() {
  M_COUNT=; M_EPOCH=; M_RAW=; M_ERR=; M_FETCHED=0; M_SIZE=
  [ -f "$METAD/$1" ] || return 1
  while IFS= read -r _ml_l || [ -n "$_ml_l" ]; do
    _ml_v=${_ml_l#*=}
    case ${_ml_l%%=*} in
      COUNT) M_COUNT=$_ml_v ;;
      EPOCH) M_EPOCH=$_ml_v ;;
      RAW) M_RAW=$_ml_v ;;
      ERR) M_ERR=$_ml_v ;;
      FETCHED) M_FETCHED=$_ml_v ;;
      SIZE) M_SIZE=$_ml_v ;;
    esac
  done < "$METAD/$1"
  is_num "$M_FETCHED" || M_FETCHED=0
  return 0
}

meta_save() {
  {
    printf 'COUNT=%s\nEPOCH=%s\nRAW=%s\n' "$2" "$3" "$4"
    printf 'ERR=%s\nFETCHED=%s\nSIZE=%s\n' "$5" "$(now)" "$6"
  } > "$METAD/$1.tmp" 2>/dev/null && mv -f "$METAD/$1.tmp" "$METAD/$1"
}

meta_ids() {
  custom_ids
  R_META="$BASE_IDS $ADDON_IDS${R_CUSTOM:+ $R_CUSTOM}"
}

meta_fetch_one() {
  list_info "$1" || return 0
  DL_GUARD_PRIVATE=0; DL_MAX_REDIR=5
  if [ "$L_CUSTOM" = 1 ]; then DL_GUARD_PRIVATE=1; DL_MAX_REDIR=0; fi
  _mf_b=$TMPD/meta.$1.body
  _mf_h=$TMPD/meta.$1.hdr
  _mf_urls=$L_URL
  [ -n "$L_URL_ALT" ] && _mf_urls="$_mf_urls $L_URL_ALT"
  if [ "$DL_TOOL" = none ] || [ -z "$DL_TOOL" ]; then
    meta_save "$1" '' '' '' no_downloader ''
  elif ! dl_fetch_any "$_mf_b" "$_mf_h" peek $_mf_urls; then
    meta_save "$1" '' '' '' "${DL_FAIL:-network}" ''
    log WARN "无法获取 $L_NAME 的详情：$(dl_reason)"
  else
    # peek 成功只代表这一次请求；full 仍保留主源+镜像，避免二次请求被同一网络重置。
    head_info "$_mf_b"
    _mf_c=$HI_COUNT
    _mf_d=$HI_DATE
    _mf_s=$DL_TOTAL
    [ -n "$_mf_d" ] || _mf_d=$DL_LASTMOD
    if [ -z "$_mf_c" ] && ! looks_html "$_mf_b"; then
      _mf_full=0
      [ -n "$DL_TOTAL" ] && [ "$(fsize "$_mf_b")" = "$DL_TOTAL" ] && _mf_full=1
      if [ "$_mf_full" = 0 ] && [ "$L_KIND" = base ]; then
        dl_fetch_any "$_mf_b" "$_mf_h" full $_mf_urls && _mf_full=1
        [ -n "$DL_TOTAL" ] && _mf_s=$DL_TOTAL
      fi
      if [ "$_mf_full" = 1 ] && ! looks_html "$_mf_b"; then
        rm -f "$TMPD/meta.$1.count"
        awk -v cntf="$TMPD/meta.$1.count" "$AWK_NORM" "$_mf_b" > /dev/null 2>&1
        [ -f "$TMPD/meta.$1.count" ] && read -r _mf_c < "$TMPD/meta.$1.count"
        rm -f "$TMPD/meta.$1.count"
        is_num "$_mf_c" && [ "$_mf_c" -gt 0 ] || _mf_c=
      fi
    fi
    if [ -z "$_mf_c" ] && [ "$L_KIND" = addon ] && src_load "$1" && [ "$S_COUNT" -gt 0 ]; then
      _mf_c=$S_COUNT
    fi
    if [ -n "$_mf_c" ]; then
      meta_save "$1" "$_mf_c" "$(date_epoch "$_mf_d")" "$_mf_d" '' "$_mf_s"
    elif [ "$L_KIND" = addon ]; then
      meta_save "$1" '' "$(date_epoch "$_mf_d")" "$_mf_d" '' "$_mf_s"
    else
      meta_save "$1" '' "$(date_epoch "$_mf_d")" "$_mf_d" count_unavailable "$_mf_s"
      log WARN "无法确定 $L_NAME 的条目数量"
    fi
  fi
  rm -f "$_mf_b" "$_mf_h" "$_mf_h.err" "$METAD/$1.busy"
}

meta_start() {
  lock_take "$METALOCK" || return 1
  for _ms in "$@"; do : > "$METAD/$_ms.busy"; done
  if spawn "$RUND/meta.out" _meta "$@"; then
    return 0
  fi
  for _ms in "$@"; do rm -f "$METAD/$_ms.busy"; done
  lock_drop "$METALOCK"
  return 1
}

meta_worker_main() {
  MODE=worker
  echo "$$" > "$METALOCK/pid" 2>/dev/null
  spawned
  trap 'rm -f "$METAD"/*.busy; lock_drop_if_mine "$METALOCK"' EXIT
  trap 'exit 143' TERM INT HUP
  dl_detect
  _mw_n=0
  for _mw in "$@"; do
    list_info "$_mw" || continue
    (
      trap - EXIT TERM INT HUP
      meta_fetch_one "$_mw"
    ) &
    _mw_n=$((_mw_n + 1))
    if [ "$_mw_n" -ge 6 ]; then
      wait
      _mw_n=0
    fi
  done
  wait
}

addon_added() {
  R_ADDED=
  _aa_n=0
  _aa_f=0
  for _aa_x in $ST_IDS; do
    _aa_n=$((_aa_n + 1))
    if [ "$_aa_x" = "$1" ]; then _aa_f=1; break; fi
  done
  [ "$_aa_f" = 1 ] || return 0
  _aa_k=0
  for _aa_v in $ST_ADDONS; do
    _aa_k=$((_aa_k + 1))
    if [ "$_aa_k" = "$_aa_n" ]; then R_ADDED=$_aa_v; return 0; fi
  done
}

list_item_json() {
  list_info "$1"
  meta_load "$1"
  _li_host=${L_URL#*://}
  _li_host=${_li_host%%/*}
  _li_alt=
  _li_ha=false
  if [ -n "$L_URL_ALT" ]; then
    _li_alt=${L_URL_ALT#*://}
    _li_alt=${_li_alt%%/*}
    _li_ha=true
  fi
  _li_errtxt=
  [ -n "$M_ERR" ] && _li_errtxt=$(source_error_text "$M_ERR")
  js "$L_NAME"; _li_1=$JS
  js "$L_LEVELTXT"; _li_2=$JS
  js "$L_DESC"; _li_3=$JS
  js "$_li_host"; _li_4=$JS
  js "$M_RAW"; _li_5=$JS
  js "$M_ERR"; _li_6=$JS
  jnum "$M_COUNT"; _li_7=$JN
  jnum "$M_EPOCH"; _li_8=$JN
  jnum "$M_SIZE"; _li_9=$JN
  jnum "$M_FETCHED"
  js "$_li_alt"; _li_10=$JS
  js "$_li_errtxt"; _li_11=$JS
  R_ITEM="{\"id\":\"$1\",\"name\":$_li_1,\"group\":\"$L_GROUP\",\"level\":\"$L_LEVEL\",\"levelText\":$_li_2,\"desc\":$_li_3,\"host\":$_li_4,\"altHost\":$_li_10,\"hasAlt\":$_li_ha,\"count\":$_li_7,\"date\":$_li_8,\"dateRaw\":$_li_5,\"size\":$_li_9,\"error\":$_li_6,\"errorText\":$_li_11,\"fetched\":$JN,\"busy\":$2}"
}

addon_item_json() {
  list_info "$1"
  meta_load "$1"
  _ai_host=${L_URL#*://}
  _ai_host=${_ai_host%%/*}
  _ai_alt=
  _ai_ha=false
  if [ -n "$L_URL_ALT" ]; then
    _ai_alt=${L_URL_ALT#*://}
    _ai_alt=${_ai_alt%%/*}
    _ai_ha=true
  fi
  _ai_errtxt=
  [ -n "$M_ERR" ] && _ai_errtxt=$(source_error_text "$M_ERR")
  _ai_on=false
  _ai_inst=null
  _ai_add=null
  if word_in "$1" "$C_ADDONS"; then
    _ai_on=true
    addon_added "$1"
    jnum "$R_ADDED"; _ai_add=$JN
  fi
  if src_ready "$1" && src_load "$1"; then _ai_inst=$S_COUNT; fi
  _ai_sug=false
  [ "$1" = "$R_DEVADDON" ] && _ai_sug=true
  _ai_cus=false
  _ai_url='""'
  if [ "$L_CUSTOM" = 1 ]; then
    _ai_cus=true
    js "$L_URL"; _ai_url=$JS
  fi
  js "$L_NAME"; _ai_1=$JS
  js "$L_DESC"; _ai_3=$JS
  js "$_ai_host"; _ai_4=$JS
  js "$M_ERR"; _ai_6=$JS
  jnum "$M_COUNT"; _ai_7=$JN
  jnum "$M_EPOCH"; _ai_8=$JN
  jnum "$M_SIZE"; _ai_9=$JN
  js "$_ai_alt"; _ai_10=$JS
  js "$_ai_errtxt"; _ai_11=$JS
  R_ITEM="{\"id\":\"$1\",\"name\":$_ai_1,\"icon\":\"$L_ICON\",\"group\":\"$L_GROUP\",\"desc\":$_ai_3,\"host\":$_ai_4,\"altHost\":$_ai_10,\"hasAlt\":$_ai_ha,\"count\":$_ai_7,\"date\":$_ai_8,\"size\":$_ai_9,\"error\":$_ai_6,\"errorText\":$_ai_11,\"busy\":$2,\"enabled\":$_ai_on,\"installed\":$_ai_inst,\"added\":$_ai_add,\"warn\":\"$L_WARN\",\"suggested\":$_ai_sug,\"custom\":$_ai_cus,\"url\":$_ai_url}"
}

pl_set() { PL_CODE=$1; PL_MSG=$2; }

pl_cancelled() {
  pl_set cancelled '✖️ 已取消，未做任何更改。'
  log INFO "用户已取消，未做任何更改"
}

pl_download_error() {
  case $DL_FAIL in
    http) pl_set http_error "🌐 列表服务器对 $FS_NAME 返回 HTTP $DL_CODE，未做任何更改，请稍后重试。" ;;
    toolarge) pl_set too_large "🐘 $FS_NAME 超过 $((MAX_BYTES / 1048576)) MB，未下载，未做任何更改。" ;;
    incomplete) pl_set download_interrupted "✂️ $FS_NAME 下载中断，未做任何更改，请重试。" ;;
    *) pl_set network_error "🌐 无法连接列表服务器，请检查网络后重试。" ;;
  esac
  log ERROR "$FS_NAME 下载失败：$(dl_reason)"
}

pl_cleanup() {
  rm -f "$DLPART" "$DLHDR" "$DLHDR.err" "$TMPD/norm.count" "$TMPD/peek.body" "$TMPD/peek.hdr" "$TMPD/peek.hdr.err" "$TMPD/compile.stats" "$RUND/cancel" "$RUND/dl.pid" 2>/dev/null
  rm -rf "$STAGED" 2>/dev/null
  rm -f "$HOSTSD"/.hosts.hk* 2>/dev/null
  return 0
}

fetch_source() {
  list_info "$1" || return 1
  DL_GUARD_PRIVATE=0; DL_MAX_REDIR=5
  if [ "$L_CUSTOM" = 1 ]; then DL_GUARD_PRIVATE=1; DL_MAX_REDIR=0; fi
  _fs_id=$1
  FS_NAME=$L_NAME
  _fs_url=$L_URL
  _fs_min=$L_MIN
  OP_SRC=$_fs_id
  OP_SRCNAME=$L_NAME
  OP_TOTAL=0
  op_phase check
  if [ "$2" = check ]; then
    say "🔎 正在检查 $FS_NAME 的更新…"
    log INFO "正在检查 $FS_NAME 的更新"
  fi
  _fs_et=; _fs_sd=; _fs_hc=; _fs_total=; _fs_have=0
  _fs_urls=$_fs_url
  [ -n "$L_URL_ALT" ] && _fs_urls="$_fs_urls $L_URL_ALT"
  if dl_fetch_any "$TMPD/peek.body" "$TMPD/peek.hdr" peek $_fs_urls; then
    head_info "$TMPD/peek.body"
    _fs_et=$DL_ETAG
    _fs_sd=$HI_DATE
    [ -n "$_fs_sd" ] || _fs_sd=$DL_LASTMOD
    _fs_hc=$HI_COUNT
    _fs_total=$DL_TOTAL
    [ -n "$DL_TOTAL" ] && [ "$(fsize "$TMPD/peek.body")" = "$DL_TOTAL" ] && _fs_have=1
  elif [ "$DL_FAIL" != http ] || [ "$DL_CODE" != 416 ]; then
    cancel_requested && return 3
    pl_download_error
    return 1
  fi
  if [ "$2" = check ] && src_ready "$_fs_id" && src_load "$_fs_id"; then
    _fs_same=0
    if [ -n "$_fs_et" ] && [ -n "$S_ETAG" ]; then
      [ "$_fs_et" = "$S_ETAG" ] && _fs_same=1
    elif [ -n "$_fs_sd" ] && [ -n "$S_SRCDATE" ]; then
      [ "$_fs_sd" = "$S_SRCDATE" ] && _fs_same=1
    fi
    if [ "$_fs_same" = 1 ]; then
      rm -f "$TMPD/peek.body" "$TMPD/peek.hdr"
      log INFO "$FS_NAME 已是最新版本"
      return 2
    fi
  fi
  cancel_requested && return 3

  _fs_need=51200
  if is_num "$_fs_total"; then
    _fs_est=$((_fs_total * 4 / 1024))
    [ "$_fs_est" -gt "$_fs_need" ] && _fs_need=$_fs_est
  fi
  _fs_free=$(free_kb "$DATA")
  if is_num "$_fs_free" && [ "$_fs_free" -lt "$_fs_need" ]; then
    pl_set no_space "💾 可用存储空间不足：需要约 $((_fs_need / 1024)) MB，当前可用 $((_fs_free / 1024)) MB。"
    log ERROR "存储空间不足：需要 ${_fs_need} KB，当前可用 ${_fs_free} KB"
    return 1
  fi

  OP_TOTAL=${_fs_total:-0}
  op_phase download
  say "⬇️ 正在下载 $FS_NAME…"
  log INFO "正在下载 $FS_NAME"
  if [ "$_fs_have" = 1 ]; then
    mv -f "$TMPD/peek.body" "$DLPART"
    mv -f "$TMPD/peek.hdr" "$DLHDR"
    _fs_code=200
    _fs_cl=
    _fs_enc=
    _fs_fet=$_fs_et
  else
    rm -f "$TMPD/peek.body" "$TMPD/peek.hdr"
    DL_PIDF=$RUND/dl.pid
    _fs_urls=$_fs_url
    [ -n "$L_URL_ALT" ] && case $_fs_urls in *"$L_URL_ALT"*) ;; *) _fs_urls="$_fs_urls $L_URL_ALT" ;; esac
    if ! dl_fetch_any "$DLPART" "$DLHDR" full $_fs_urls; then
      DL_PIDF=
      cancel_requested && return 3
      pl_download_error
      return 1
    fi
    DL_PIDF=
    _fs_code=$DL_CODE
    _fs_cl=$DL_CL
    _fs_enc=$DL_ENC
    _fs_fet=$DL_ETAG
    [ -n "$_fs_et" ] || _fs_et=$DL_ETAG
    [ -n "$_fs_sd" ] || _fs_sd=$DL_LASTMOD
  fi
  cancel_requested && return 3

  op_phase verify
  _fs_size=$(fsize "$DLPART")
  if [ "$_fs_code" != 200 ]; then
    pl_set http_error "🌐 列表服务器返回 HTTP $_fs_code，而不是有效列表，未做任何更改。"
    log ERROR "$FS_NAME 返回意外的 HTTP 状态码 $_fs_code"
    return 1
  fi
  if [ "$_fs_size" -eq 0 ]; then
    pl_set empty_file "📭 服务器返回的空文件（$FS_NAME），未做任何更改。"
    log ERROR "$FS_NAME 的下载文件为空"
    return 1
  fi
  if looks_html "$DLPART"; then
    pl_set html_page '🧱 服务器返回的是网页而不是 hosts 列表，未做任何更改。'
    log ERROR "$FS_NAME 的下载内容是 HTML 页面"
    return 1
  fi
  _fs_want=
  if [ -z "$_fs_enc" ] && [ -n "$_fs_cl" ]; then
    _fs_want=$_fs_cl
  elif [ "$DL_TOOL" = curl ] && [ "$DL_GZ" = 1 ] && [ -n "$_fs_enc" ]; then
    # curl --compressed writes the decoded body; Content-Length is the
    # compressed wire size, so comparing them would always fail.
    _fs_want=
  elif [ -n "$_fs_enc" ] && is_num "$_fs_total" && [ -n "$_fs_fet" ] && [ "$_fs_fet" = "$_fs_et" ]; then
    _fs_want=$_fs_total
  fi
  if [ -n "$_fs_want" ] && [ "$_fs_want" != "$_fs_size" ]; then
    pl_set size_mismatch "✂️ 下载不完整（已下载 $(fmt_mb "$_fs_size")，应为 $(fmt_mb "$_fs_want")），未做任何更改。"
    log ERROR "$FS_NAME 下载不完整：已下载 $_fs_size / $_fs_want 字节"
    return 1
  fi
  say "✅ 已下载 $(fmt_mb "$_fs_size")"
  if [ -z "$_fs_hc" ] || [ -z "$_fs_sd" ]; then
    head_info "$DLPART"
    [ -n "$_fs_hc" ] || _fs_hc=$HI_COUNT
    [ -n "$_fs_sd" ] || _fs_sd=$HI_DATE
  fi
  cancel_requested && return 3

  op_phase optimize
  say "🧹 正在清理并优化条目…"
  rm -f "$TMPD/norm.count"
  mkdir -p "$STAGED"
  if ! awk -v cntf="$TMPD/norm.count" "$AWK_NORM" "$DLPART" > "$STAGED/$_fs_id.domains.tmp" 2>/dev/null; then
    rm -f "$STAGED/$_fs_id.domains.tmp"
    pl_set process_failed "❌ 无法处理 $FS_NAME，未做任何更改。"
    log ERROR "$FS_NAME 处理失败"
    return 1
  fi
  mv -f "$STAGED/$_fs_id.domains.tmp" "$STAGED/$_fs_id.domains" 2>/dev/null || {
    rm -f "$STAGED/$_fs_id.domains.tmp"
    pl_set write_failed "❌ 无法暂存 $FS_NAME，未做任何更改。"
    log ERROR "无法暂存 $FS_NAME"
    return 1
  }
  _fs_n=0
  [ -f "$TMPD/norm.count" ] && read -r _fs_n < "$TMPD/norm.count"
  is_num "$_fs_n" || _fs_n=0
  rm -f "$DLPART" "$DLHDR" "$TMPD/norm.count"
  if [ "$_fs_n" -lt "$_fs_min" ]; then
    rm -f "$STAGED/$_fs_id.domains"
    pl_set too_few_entries "📉 $FS_NAME 仅找到 $(fmt_num "$_fs_n") 条有效记录（至少需要 $(fmt_num "$_fs_min") 条），未做任何更改。"
    log ERROR "$FS_NAME 仅有 $_fs_n 条有效记录"
    return 1
  fi
  say "✅ 已校验 $(fmt_num "$_fs_n") 个唯一域名"
  if ! src_write "$STAGED/$_fs_id.info" "$_fs_et" "$_fs_sd" "$_fs_n" "$_fs_size"; then
    rm -f "$STAGED/$_fs_id.domains" "$STAGED/$_fs_id.info"
    pl_set write_failed "❌ 无法保存 $FS_NAME 的源元数据，未做任何更改。"
    log ERROR "无法保存 $FS_NAME 的源元数据"
    return 1
  fi
  meta_save "$_fs_id" "${_fs_hc:-$_fs_n}" "$(date_epoch "$_fs_sd")" "$_fs_sd" '' "$_fs_size"
  cancel_requested && return 3
  return 0
}

pipeline() {
  PL_KIND=$1; PL_BASE=$2; PL_CODE=; PL_MSG=; PL_REBOOT=0; PL_LIVE=0; PL_DOMAINS=0; PL_WARN=0
  if ! list_info "$PL_BASE" || [ "$L_KIND" != base ]; then
    pl_set invalid_list '❌ 未知列表。'
    return 1
  fi
  PL_NAME=$L_NAME
  addons_clean "$3"
  PL_ADDONS=$R_ADDONS
  cfg_load
  _pl_enabled=$C_ENABLED
  ensure_dirs
  pl_cleanup
  mkdir -p "$STAGED"
  op_phase prepare

  _pl_plan=
  _pl_items=0
  for _pl_id in $PL_BASE $PL_ADDONS; do
    _pl_mode=
    if src_ready "$_pl_id"; then
      case $PL_KIND in update | auto | setup) _pl_mode=check ;; esac
    else
      _pl_mode=full
    fi
    [ -n "$_pl_mode" ] || continue
    _pl_plan="$_pl_plan $_pl_id:$_pl_mode"
    _pl_items=$((_pl_items + 1))
  done
  OP_ITEMS=$_pl_items
  if [ "$_pl_items" -gt 0 ] && ! dl_detect; then
    pl_set no_downloader '❌ 没有可用的下载器。HostKeeper 需要支持 HTTPS 的 curl 或 BusyBox wget。'
    log ERROR "没有可用的下载工具（curl 或 BusyBox wget）"
    pl_cleanup
    return 1
  fi

  _pl_i=0
  _pl_new=0
  for _pl_e in $_pl_plan; do
    _pl_id=${_pl_e%%:*}
    _pl_i=$((_pl_i + 1))
    OP_ITEM=$_pl_i
    fetch_source "$_pl_id" "${_pl_e##*:}"
    case $? in
      0) _pl_new=$((_pl_new + 1)) ;;
      2) ;;
      3)
        pl_cancelled
        pl_cleanup
        return 1
        ;;
      *)
        if [ "$_pl_id" != "$PL_BASE" ] && src_ready "$_pl_id"; then
          PL_WARN=$((PL_WARN + 1))
          rm -f "$STAGED/$_pl_id.domains" "$STAGED/$_pl_id.info"
          log WARN "$FS_NAME 刷新失败，继续使用上一版本"
        else
          pl_cleanup
          return 1
        fi
        ;;
    esac
  done
  OP_SRC=; OP_SRCNAME=; OP_TOTAL=0
  if cancel_requested; then
    pl_cancelled
    pl_cleanup
    return 1
  fi

  cfg_load
  case $PL_KIND in
    update | auto)
      if [ "$_pl_new" = 0 ] && [ "$PL_WARN" = 0 ] && [ "$C_LIST" = "$PL_BASE" ] && [ "$C_ADDONS" = "$PL_ADDONS" ] && [ "$C_SETUP" = ready ] && hosts_sane "$HOSTS" && verify_hosts_deep "$C_DOMAINS" && sum_check; then
        C_CHECKED=$(now)
        cfg_save
        PL_DOMAINS=$C_DOMAINS
        pl_set up_to_date "✅ 已是最新版本，自上次更新以来没有变化。"
        log INFO "所有内容都已是最新版本"
        pl_cleanup
        return 0
      fi
      ;;
  esac

  op_phase install
  rm -f "$RUND/cancel"
  C_LIST=$PL_BASE
  C_ADDONS=$PL_ADDONS
  if ! merge_sources "$STAGED" || ! compile_into "$HOSTSD/.hosts.hknew" "$C_ENABLED"; then
    pl_set write_failed "❌ 无法构建新的 hosts 文件，未做任何更改。"
    log ERROR "无法为 $PL_NAME 构建 hosts 文件"
    pl_cleanup
    return 1
  fi
  _pl_stage_bad=0
  for _pl_f in "$STAGED"/*.domains; do
    [ -f "$_pl_f" ] || continue
    [ "$_pl_f" = "$STAGED/extras.domains" ] && continue
    _pl_id=${_pl_f##*/}
    _pl_id=${_pl_id%.domains}
    [ -f "$STAGED/$_pl_id.info" ] || _pl_stage_bad=1
  done
  if [ "$_pl_stage_bad" = 1 ] || ! stage_commit; then
    rm -f "$HOSTSD/.hosts.hknew"
    pl_set write_failed "❌ 无法提交下载的缓存，未做任何更改。"
    log ERROR "无法提交 $PL_NAME 的下载缓存"
    pl_cleanup
    return 1
  fi
  install_hosts "$HOSTSD/.hosts.hknew" "$CH_COUNT" backup
  case $? in
    1)
      pl_set write_failed "❌ 无法写入 hosts 文件，已恢复之前的 hosts 文件。"
      log ERROR "无法写入 $PL_NAME 的 hosts 文件"
      pl_cleanup
      return 1
      ;;
    2)
      pl_set verify_failed '❌ 新的 hosts 文件校验失败，已恢复之前的 hosts 文件。'
      pl_cleanup
      return 1
      ;;
  esac

  src_load "$PL_BASE"
  C_ENABLED=$_pl_enabled
  C_COUNT=$S_COUNT
  C_DOMAINS=$CH_COUNT
  C_SETUP=ready
  C_CHECKED=$(now)
  if [ "$_pl_new" -gt 0 ] || [ "$C_UPDATED" = 0 ]; then C_UPDATED=$C_CHECKED; fi
  cfg_save
  stats_commit

  op_phase finish
  PL_DOMAINS=$CH_COUNT
  _pl_n=$(fmt_num "$CH_COUNT")
  if [ "$_pl_enabled" != 1 ]; then
    _pl_code=disabled
    _pl_msg="✅ 拦截列表源已就绪，拦截仍处于关闭状态。"
    if [ "$IH_CHANGED" = 1 ] && ! settle_change; then
      PL_REBOOT=1
    fi
  else
    case $PL_KIND in
      update | auto) _pl_msg="✅ $PL_NAME 已更新，共 $_pl_n 个域名。" ;;
      enable) _pl_msg="🟢 已使用 $PL_NAME 重新开启拦截，共 $_pl_n 个域名。" ;;
      addons) _pl_msg="✅ 附加列表已更新，共 $_pl_n 个域名。" ;;
      *) _pl_msg="✅ $PL_NAME 已就绪，共 $_pl_n 个域名。" ;;
    esac
    if [ "$IH_CHANGED" = 1 ]; then
      if settle_change; then
        PL_LIVE=1
        _pl_msg="$_pl_msg 已立即生效，无需重启。"
      else
        PL_REBOOT=1
        _pl_msg="$_pl_msg 重启后生效。"
      fi
      _pl_code=applied
    else
      if settle_change; then
        PL_LIVE=1
        _pl_msg="✅ $PL_NAME 已是最新版本，hosts 文件未变化。"
      else
        PL_REBOOT=1
        _pl_msg="✅ $PL_NAME 已是最新版本，重启后恢复即时拦截。"
      fi
      _pl_code=unchanged
    fi
  fi
  if [ "$PL_WARN" -gt 0 ]; then
    _pl_msg="$_pl_msg ⚠️ $PL_WARN 个附加列表刷新失败，已保留上一版本。"
  fi
  set_description
  pl_set "$_pl_code" "$_pl_msg"
  set -- $PL_ADDONS
  log INFO "$PL_NAME 安装完成，包含 $# 个附加列表，共 $_pl_n 个域名$( [ "$PL_LIVE" = 1 ] && printf '，已即时生效')$( [ "$PL_REBOOT" = 1 ] && printf '，需要重启')"
  pl_cleanup
  return 0
}

rebuild() {
  RB_CHANGED=0; RB_STATE=ok; RB_LIVE=0
  cfg_load
  if [ "$C_ENABLED" != 1 ]; then RB_STATE=disabled; return 0; fi
  if [ "$C_SETUP" != ready ] || ! sources_ready; then RB_STATE=nocache; return 0; fi
  if ! compile_into "$HOSTSD/.hosts.hknew" 1; then
    rm -f "$HOSTSD/.hosts.hknew" "$TMPD/compile.stats"
    RB_STATE=write_failed
    return 1
  fi
  install_hosts "$HOSTSD/.hosts.hknew" "$CH_COUNT"
  case $? in
    1) RB_STATE=write_failed; return 1 ;;
    2) RB_STATE=verify_failed; return 1 ;;
  esac
  RB_CHANGED=$IH_CHANGED
  C_DOMAINS=$CH_COUNT
  cfg_save
  stats_commit
  if [ "$RB_CHANGED" = 1 ]; then
    settle_change && RB_LIVE=1
  fi
  set_description
  return 0
}

change_note() {
  if [ "$RB_CHANGED" != 1 ]; then R_NOTE=
  elif [ "$RB_LIVE" = 1 ]; then R_NOTE=' 当前已生效。'
  else R_NOTE=' 重启后生效。'
  fi
}

extract_domain() {
  _ed=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  _ed=${_ed#"${_ed%%[! 	]*}"}
  _ed=${_ed%"${_ed##*[! 	]}"}
  _ed_w=
  case $_ed in '*.'*) _ed_w='*.'; _ed=${_ed#'*.'} ;; esac
  case $_ed in
    *://*)
      _ed=${_ed#*://}
      _ed=${_ed%%/*}
      _ed=${_ed%%\?*}
      _ed=${_ed%%#*}
      _ed=${_ed##*@}
      case $_ed in \[*) ;; *:*) _ed=${_ed%:*} ;; esac
      ;;
    */* | *\?* | *#*)
      _ed=${_ed%%/*}
      _ed=${_ed%%\?*}
      _ed=${_ed%%#*}
      ;;
  esac
  printf '%s' "$_ed_w${_ed%.}"
}

domain_problem() {
  _dp=$1
  if [ -z "$_dp" ]; then printf '✏️ 请先输入域名。'; return 0; fi
  case $_dp in
    '*.'*)
      if [ "$2" != allow ]; then
        printf "🚫 Hosts 文件不能拦截通配符，请输入要拦截的精确域名。"
        return 0
      fi
      _dp=${_dp#'*.'}
      ;;
  esac
  case $_dp in
    *"$NL"* | *"$CR"*) printf "🚫 这看起来不是有效域名，例如 ads.example.com。"; return 0 ;;
    *' '* | *"$TAB"*) printf "🚫 域名中不能包含空格。"; return 0 ;;
    *'*'*) printf "🚫 通配符只能用在放行规则开头，例如 *.example.com。"; return 0 ;;
    \[* | *:*) printf "🚫 不允许端口和 IPv6 地址，请只输入域名，例如 example.com。"; return 0 ;;
  esac
  case $_dp in *[!0-9.]*) ;; *) printf "🚫 不允许 IP 地址，请输入域名。"; return 0 ;; esac
  if ! printf '%s\n' "$_dp" | awk "$AWK_VALID"; then
    printf "🚫 这看起来不是有效域名，例如 ads.example.com。"
  fi
  return 0
}

rules_json() {
  _rj_a='[]'
  _rj_b='[]'
  [ -s "$ALLOWF" ] && _rj_a=$(awk "$AWK_JARR" "$ALLOWF")
  [ -s "$BLOCKF" ] && _rj_b=$(awk "$AWK_JARR" "$BLOCKF")
  R_RULES="{\"allow\":$_rj_a,\"block\":$_rj_b}"
}

rules_engine() {
  RE_ADDED_A=0; RE_ADDED_B=0; RE_INVALID=0; RE_DUP=0; RE_CONFLICT=0; RE_LIMIT=0; RE_LASTREJ=; RE_LASTREF=
  rm -f "$TMPD/rules.a.new" "$TMPD/rules.b.new"
  _re=$(awk -v mode="$1" -v allowf="$ALLOWF" -v blockf="$BLOCKF" -v outa="$TMPD/rules.a.new" -v outb="$TMPD/rules.b.new" -v max="$RULE_MAX" "$AWK_RULES" "$2" 2>/dev/null) || return 1
  [ -f "$TMPD/rules.a.new" ] && [ -f "$TMPD/rules.b.new" ] || return 1
  while IFS= read -r _re_l; do
    _re_v=${_re_l#*=}
    case ${_re_l%%=*} in
      ADDED_A) RE_ADDED_A=$_re_v ;;
      ADDED_B) RE_ADDED_B=$_re_v ;;
      INVALID) RE_INVALID=$_re_v ;;
      DUP) RE_DUP=$_re_v ;;
      CONFLICT) RE_CONFLICT=$_re_v ;;
      LIMIT) RE_LIMIT=$_re_v ;;
      LASTREJ) RE_LASTREJ=$_re_v ;;
      LASTREF) RE_LASTREF=$_re_v ;;
    esac
  done << EOF
$_re
EOF
  return 0
}

rules_commit() {
  rm -f "$ALLOWF.undo" "$BLOCKF.undo"
  if ! cp -f "$ALLOWF" "$ALLOWF.undo" 2>/dev/null; then
    rm -f "$ALLOWF.undo" "$BLOCKF.undo"
    return 1
  fi
  if ! cp -f "$BLOCKF" "$BLOCKF.undo" 2>/dev/null; then
    rm -f "$ALLOWF.undo" "$BLOCKF.undo"
    return 1
  fi
  if ! mv -f "$TMPD/rules.a.new" "$ALLOWF" || ! mv -f "$TMPD/rules.b.new" "$BLOCKF"; then
    rules_rollback
    return 1
  fi
  return 0
}

rules_rollback() {
  _rr_ok=1
  if [ -f "$ALLOWF.undo" ]; then
    mv -f "$ALLOWF.undo" "$ALLOWF" 2>/dev/null || _rr_ok=0
  fi
  if [ -f "$BLOCKF.undo" ]; then
    mv -f "$BLOCKF.undo" "$BLOCKF" 2>/dev/null || _rr_ok=0
  fi
  rm -f "$TMPD/rules.a.new" "$TMPD/rules.b.new"
  return "$_rr_ok"
}
rules_done() { rm -f "$ALLOWF.undo" "$BLOCKF.undo" "$TMPD/rules.a.new" "$TMPD/rules.b.new" "$TMPD/rules.in"; return 0; }

sched_alive() {
  _sa=
  [ -f "$SCHEDPID" ] && read -r _sa < "$SCHEDPID"
  is_num "$_sa" && [ -d "/proc/$_sa" ] && grep -q '_sched' "/proc/$_sa/cmdline" 2>/dev/null
}

sched_stop() {
  _ss=
  [ -f "$SCHEDPID" ] && read -r _ss < "$SCHEDPID"
  if is_num "$_ss" && [ -d "/proc/$_ss" ] && grep -q '_sched' "/proc/$_ss/cmdline" 2>/dev/null; then
    kill "$_ss" 2>/dev/null
  fi
  rm -f "$SCHEDPID" "$SCHEDRETRY"
  return 0
}

sched_sync() {
  if [ "$C_AUTO" -gt 0 ]; then
    sched_alive && return 0
    spawn "$RUND/sched.out" _sched
    return
  fi
  sched_stop
}

words_json() {
  R_WORDS='['
  for _wj in $1; do
    R_WORDS="$R_WORDS\"$_wj\","
  done
  R_WORDS="${R_WORDS%,}]"
}

cmd_status() {
  op_json
  cfg_load
  _st_name=$L_NAME; _st_level=$L_LEVEL; _st_ltxt=$L_LEVELTXT
  detect_manager
  applied_state
  conflicts_scan
  mount_mode
  words_json "$R_CONF"; _st_cfj=$R_WORDS
  jbool "$C_ENABLED"; _st_en=$JB
  _st_rb=false; [ "$R_APPLIED" = pending ] && _st_rb=true
  _st_hd=false; [ "$MGR_HTTPD" = yes ] && _st_hd=true
  _st_aa=false; [ -d /data/data/org.adaway ] && _st_aa=true
  jbool "$C_LIVE"; _st_lv=$JB
  _st_sc=false; sched_alive && _st_sc=true
  count_lines "$ALLOWF"; _st_al=$R_LINES
  count_lines "$BLOCKF"; _st_bl=$R_LINES
  stats_read
  _st_ad=
  for _st_i in $C_ADDONS; do
    list_info "$_st_i" || continue
    addon_added "$_st_i"
    jnum "$R_ADDED"
    js "$L_NAME"
    _st_ad="$_st_ad{\"id\":\"$_st_i\",\"name\":$JS,\"icon\":\"$L_ICON\",\"added\":$JN},"
  done
  _st_ad="[${_st_ad%,}]"
  S_SRCDATE=
  src_load "$C_LIST"
  _st_host=${L_URL#*://}
  _st_host=${_st_host%%/*}
  _st_alt=
  _st_ha=false
  if [ -n "$L_URL_ALT" ]; then
    _st_alt=${L_URL_ALT#*://}
    _st_alt=${_st_alt%%/*}
    _st_ha=true
  fi
  js "$_st_name"; _st_1=$JS
  js "$_st_ltxt"; _st_2=$JS
  js "$MGR_NAME"; _st_3=$JS
  js "$MGR_VER"; _st_4=$JS
  js "$S_SRCDATE"; _st_5=$JS
  js "$HK_VER"; _st_v=$JS
  js "$C_LIST"; _st_lid=$JS
  js "$_st_level"; _st_lvl=$JS
  js "$R_APPLIED"; _st_ap=$JS
  js "$R_MOUNT"; _st_mt=$JS
  js "$C_SETUP"; _st_su=$JS
  js "$C_GUARD"; _st_gd=$JS
  js "$_st_host"; _st_lhost=$JS
  js "$_st_alt"; _st_lalt=$JS
  _st_hs=0
  [ -f "$HOSTS" ] && _st_hs=$(fsize "$HOSTS")
  reply true status '' "{\"version\":$_st_v,\"versionCode\":$HK_VCODE,\"manager\":$_st_3,\"managerVersion\":$_st_4,\"enabled\":$_st_en,\"list\":$_st_lid,\"listName\":$_st_1,\"level\":$_st_lvl,\"levelText\":$_st_2,\"domains\":$C_DOMAINS,\"listCount\":$C_COUNT,\"allow\":$_st_al,\"block\":$_st_bl,\"updated\":$C_UPDATED,\"checked\":$C_CHECKED,\"sourceDate\":$_st_5,\"reboot\":$_st_rb,\"applied\":$_st_ap,\"mount\":$_st_mt,\"setup\":$_st_su,\"conflicts\":$_st_cfj,\"adaway\":$_st_aa,\"httpd\":$_st_hd,\"addons\":$_st_ad,\"live\":$_st_lv,\"autoupdate\":$C_AUTO,\"sched\":$_st_sc,\"guard\":$_st_gd,\"hostsSize\":$_st_hs,\"listHost\":$_st_lhost,\"listAltHost\":$_st_lalt,\"listHasAlt\":$_st_ha,\"staleDays\":$STALE_DAYS,\"now\":$(now),\"stats\":{\"base\":${ST_BASE:-0},\"allowed\":${ST_ALLOWED:-0},\"blocked\":${ST_BLOCKED:-0},\"guarded\":${ST_GUARDED:-0}},\"op\":$R_OP}"
}

cmd_progress() { op_json; reply true progress '' "$R_OP"; }

cmd_wait() {
  _wt=${1:-600}
  is_num "$_wt" || _wt=600
  [ "$_wt" -gt 3600 ] && _wt=3600
  _wt_e=$(($(now) + _wt))
  while :; do
    op_json
    case $R_OP in *'"running":true'*) ;; *) break ;; esac
    [ "$(now)" -ge "$_wt_e" ] && break
    nap 0.5
  done
  case $R_OP in
    *'"running":true'*) reply false timeout '⏳ 任务仍在运行。' "$R_OP" ;;
    *'"state":"error"'* | *'"state":"interrupted"'*) reply false failed '' "$R_OP" ;;
    *) reply true finished '' "$R_OP" ;;
  esac
}

cmd_lists() {
  _cl_now=$(now)
  _cl_stale=
  meta_ids
  _cl_ids=$R_META
  for _cl_id in $_cl_ids; do
    if meta_load "$_cl_id"; then
      _cl_age=$((_cl_now - M_FETCHED))
      if [ -n "$M_ERR" ]; then
        [ "$_cl_age" -ge 900 ] && _cl_stale="$_cl_stale $_cl_id"
      elif [ "$_cl_age" -ge 21600 ] || [ "$_cl_age" -lt 0 ]; then
        _cl_stale="$_cl_stale $_cl_id"
      fi
    else
      _cl_stale="$_cl_stale $_cl_id"
    fi
  done
  _cl_ref=false
  if lock_alive "$METALOCK"; then
    _cl_ref=true
  elif [ -n "$_cl_stale" ]; then
    meta_start $_cl_stale && _cl_ref=true
  fi
  cfg_load
  device_addon
  stats_read
  _cl_items=
  for _cl_id in $BASE_IDS; do
    _cl_busy=false
    [ "$_cl_ref" = true ] && [ -f "$METAD/$_cl_id.busy" ] && _cl_busy=true
    list_item_json "$_cl_id" "$_cl_busy"
    _cl_items="$_cl_items$R_ITEM,"
  done
  _cl_add=
  for _cl_id in $ADDON_IDS $R_CUSTOM; do
    _cl_busy=false
    [ "$_cl_ref" = true ] && [ -f "$METAD/$_cl_id.busy" ] && _cl_busy=true
    addon_item_json "$_cl_id" "$_cl_busy"
    _cl_add="$_cl_add$R_ITEM,"
  done
  jbool "$C_ENABLED"
  reply true lists '' "{\"lists\":[${_cl_items%,}],\"addons\":[${_cl_add%,}],\"refreshing\":$_cl_ref,\"active\":\"$C_LIST\",\"enabled\":$JB,\"setup\":\"$C_SETUP\",\"customMax\":$CUSTOM_MAX}"
}

cmd_meta_refresh() {
  if [ -n "$1" ]; then
    if ! list_info "$1"; then reply false invalid_list '❌ 未知列表。'; return 0; fi
    _mr=$1
  else
    meta_ids
    _mr=$R_META
  fi
  if lock_alive "$METALOCK"; then
    reply true refreshing '🔄 已在刷新列表详情…' '{"refreshing":true}'
    return 0
  fi
  if meta_start $_mr; then
    reply true refreshing '🔄 正在刷新列表详情…' '{"refreshing":true}'
  else
    reply false refresh_failed "❌ 无法开始刷新列表详情，请重试。" '{"refreshing":false}'
  fi
}

start_job() {
  op_begin "$1" "$2"
  if spawn "$RUND/worker.out" _worker "$1" "$2" "$3"; then
    return 0
  fi
  op_finish error spawn_failed "❌ Couldn’t start the background task. Please try again."
  lock_drop "$LOCKD"
  log ERROR "无法启动后台任务"
  return 1
}

job_reply() {
  op_json
  reply true started "$1" "{\"op\":$R_OP}"
}

spawn_failed_reply() { reply false spawn_failed "❌ 无法启动后台任务，请重试。"; }

cmd_apply() {
  if ! list_info "$1" || [ "$L_KIND" != base ]; then reply false invalid_list '❌ 未知列表。'; return 0; fi
  _ap_id=$1
  cfg_load
  if [ "$C_ENABLED" != 1 ]; then reply false blocker_disabled '⏻ 请先开启拦截。'; return 0; fi
  if [ "$C_LIST" = "$_ap_id" ] && [ "$C_SETUP" = ready ] && src_ready "$_ap_id"; then
    reply false already_active '⚠️ 该列表已在生效中，请使用“更新列表”。'
    return 0
  fi
  lock_take "$LOCKD" || { busy_reply; return 0; }
  list_info "$_ap_id"
  log INFO "正在切换到 $L_NAME"
  if start_job apply "$_ap_id" "$C_ADDONS"; then
    job_reply "⬇️ 正在下载 $L_NAME…"
  else
    spawn_failed_reply
  fi
}

cmd_update() {
  cfg_load
  if [ "$C_ENABLED" != 1 ]; then reply false blocker_disabled '⏻ 请先开启拦截。'; return 0; fi
  lock_take "$LOCKD" || { busy_reply; return 0; }
  _up_kind=update
  [ "$C_SETUP" = ready ] && src_ready "$C_LIST" || _up_kind=setup
  _up_name=$L_NAME
  if start_job "$_up_kind" "$C_LIST" "$C_ADDONS"; then
    job_reply "🔄 正在检查 $_up_name 的更新…"
  else
    spawn_failed_reply
  fi
}

cmd_addons() {
  case $1 in
    *[!a-z0-9,\ -]*) reply false invalid_list '❌ 未知附加列表。'; return 0 ;;
  esac
  _ad_new=
  for _ad in $(printf '%s' "$1" | tr ',' ' '); do
    if ! list_info "$_ad" || [ "$L_KIND" != addon ]; then
      reply false invalid_list '❌ 未知附加列表。'
      return 0
    fi
    word_in "$_ad" "$_ad_new" || _ad_new="$_ad_new $_ad"
  done
  _ad_new=${_ad_new# }
  cfg_load
  if [ "$C_ENABLED" != 1 ]; then reply false blocker_disabled '⏻ 请先开启拦截。'; return 0; fi
  if [ "$C_SETUP" != ready ] || ! src_ready "$C_LIST"; then
    reply false setup_pending '⏳ 请先下载主列表，再添加附加列表。'
    return 0
  fi
  _ad_same=1
  for _ad in $_ad_new; do word_in "$_ad" "$C_ADDONS" || _ad_same=0; done
  for _ad in $C_ADDONS; do word_in "$_ad" "$_ad_new" || _ad_same=0; done
  if [ "$_ad_same" = 1 ] && sources_ready; then
    reply false unchanged '✅ 这些附加列表已处于启用状态。'
    return 0
  fi
  lock_take "$LOCKD" || { busy_reply; return 0; }
  set -- $_ad_new
  log INFO "正在更改附加列表：${_ad_new:-无}"
  if start_job addons "$C_LIST" "$_ad_new"; then
    job_reply "🧩 正在应用 $# 个附加列表…"
  else
    spawn_failed_reply
  fi
}

custom_id_for() {
  if has md5sum; then
    R_CID=$(printf '%s' "$1" | md5sum 2>/dev/null | cut -c1-8)
  else
    R_CID=$(printf '%s' "$1" | cksum 2>/dev/null | awk '{ printf "%08x", $1 }')
  fi
  case $R_CID in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) R_CID=c-$R_CID; return 0 ;; esac
  R_CID=
  return 1
}

is_private_ip() {
  case $1 in
    10.* | 127.* | 0.* | 192.168.* | 169.254.* | 198.18.* | 198.19.* | \
    192.0.0.* | 192.0.2.* | 198.51.100.* | 203.0.113.* | 22[4-9].* | 2[3-5][0-9].*)
      return 0 ;;
    172.*)
      _ip_o=${1#172.}
      _ip_o=${_ip_o%%.*}
      is_num "$_ip_o" && [ "$_ip_o" -ge 16 ] && [ "$_ip_o" -le 31 ] && return 0 ;;
    100.*)
      _ip_o=${1#100.}
      _ip_o=${_ip_o%%.*}
      is_num "$_ip_o" && [ "$_ip_o" -ge 64 ] && [ "$_ip_o" -le 127 ] && return 0 ;;
    ::1 | :: | fe* | fc* | fd* | ff*)
      return 0 ;;
    ::ffff:*)
      is_private_ip "${1#::ffff:}" && return 0 ;;
  esac
  return 1
}

host_resolves_private() {
  has nslookup || return 1
  _hp_out=$(timeout 5 nslookup "$1" 2>/dev/null)
  _hp_ips=$(printf '%s\n' "$_hp_out" | awk '
    function emit(start, i, v) {
      for (i = start; i <= NF; i++) {
        v = $i
        gsub(/,/, "", v)
        if (v ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ || v ~ /^[0-9a-fA-F]{0,4}(:[0-9a-fA-F]{0,4})+$/ || v ~ /^[0-9a-fA-F:]+:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print v
      }
    }
    BEGIN { seen = 0; addr = 0 }
    tolower($1) == "name:" { seen = 1; addr = 0; next }
    seen && tolower($1) ~ /^address(es)?:/ { addr = 1; emit(2); next }
    seen && tolower($1) == "address" { addr = 1; emit(3); next }
    addr && $0 ~ /^[ \t]/ { emit(1); next }
    addr { addr = 0 }
  ')
  for _hp_ip in $_hp_ips; do
    is_private_ip "$_hp_ip" && return 0
  done
  return 1
}

cmd_source_add() {
  _sa_u=$1
  _sa_raw=${2:-}
  case $_sa_u in
    https://*) ;;
    *) reply false source_invalid '🚫 请输入完整的 HTTPS 地址，例如 https://example.com/hosts.txt'; return 0 ;;
  esac
  case $_sa_u in
    *[!A-Za-z0-9._~:/?\&=%+,@-]*) reply false source_invalid '🚫 该地址包含不允许的字符。'; return 0 ;;
  esac
  if [ "${#_sa_u}" -gt 300 ]; then reply false source_invalid '🚫 该地址过长。'; return 0; fi
  _sa_h=${_sa_u#https://}
  _sa_h=${_sa_h%%/*}
  _sa_h=${_sa_h%%\?*}
  case $_sa_h in *@*) reply false source_invalid '🚫 不允许包含用户名的地址。'; return 0 ;; esac
  case $_sa_h in *:*) _sa_p=${_sa_h##*:}; _sa_h=${_sa_h%:*}; is_num "$_sa_p" || _sa_h= ;; esac
  _sa_h=$(printf '%s' "$_sa_h" | tr '[:upper:]' '[:lower:]')
  if [ -z "$_sa_h" ] || ! printf '%s\n' "$_sa_h" | awk "$AWK_VALID"; then
    reply false source_invalid '🚫 地址必须使用真实域名，不允许 IP 地址和本地 hosts。'
    return 0
  fi
  case $_sa_h in
    localhost | *.localhost | *.local | *.internal | *.home | *.lan)
      reply false source_invalid '🚫 不允许使用本地域名，请填写公网 HTTPS 地址。'
      return 0 ;;
  esac
  if host_resolves_private "$_sa_h"; then
    log WARN "拒绝自定义列表：域名解析到本地或私有地址（$_sa_h）"
    reply false source_invalid '🚫 该域名解析到了本地或私有网络地址，出于安全考虑不能添加。'
    return 0
  fi
  for _sa_i in $BASE_IDS $ADDON_IDS; do
    list_info "$_sa_i"
    if [ "$L_URL" = "$_sa_u" ]; then
      reply false source_exists "⚠️ 该地址已作为 $L_NAME 内置。"
      return 0
    fi
  done
  custom_ids
  set -- $R_CUSTOM
  if [ -f "$SRCF" ] && grep -qF "|$_sa_u|" "$SRCF" 2>/dev/null; then
    reply false source_exists '⚠️ 该列表已在你的自定义列表中。'
    return 0
  fi
  if [ "$#" -ge "$CUSTOM_MAX" ]; then
    reply false source_limit "📦 最多可添加 $CUSTOM_MAX 个自定义列表，请先移除一个。"
    return 0
  fi
  if ! custom_id_for "$_sa_u" || custom_info "$R_CID"; then
    reply false source_invalid '❌ 无法注册该地址，请换一个试试。'
    return 0
  fi
  _sa_n=$(printf '%s' "$_sa_raw" | tr -cd 'A-Za-z0-9 ._()+-' | cut -c1-40)
  _sa_n=${_sa_n#"${_sa_n%%[! ]*}"}
  _sa_n=${_sa_n%"${_sa_n##*[! ]}"}
  [ -n "$_sa_n" ] || _sa_n=$_sa_h
  lock_take "$LOCKD" || { busy_reply; return 0; }
  # Re-check under the lock: two concurrent additions must not both pass
  # the pre-lock duplicate/capacity checks.
  custom_ids
  set -- $R_CUSTOM
  if [ -f "$SRCF" ] && grep -qF "|$_sa_u|" "$SRCF" 2>/dev/null; then
    lock_drop "$LOCKD"
    reply false source_exists '⚠️ 该列表已在你的自定义列表中。'
    return 0
  fi
  if [ "$#" -ge "$CUSTOM_MAX" ]; then
    lock_drop "$LOCKD"
    reply false source_limit "📦 最多可添加 $CUSTOM_MAX 个自定义列表，请先移除一个。"
    return 0
  fi
  if ! custom_id_for "$_sa_u" || custom_info "$R_CID"; then
    lock_drop "$LOCKD"
    reply false source_invalid '❌ 无法注册该地址，请换一个试试。'
    return 0
  fi
  if ! printf '%s|%s|%s\n' "$R_CID" "$_sa_u" "$_sa_n" >> "$SRCF"; then
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法保存自定义列表，请重试。"
    return 0
  fi
  log INFO "已添加自定义列表：$_sa_n（$_sa_h）"
  cfg_load
  if [ "$C_ENABLED" = 1 ] && [ "$C_SETUP" = ready ] && src_ready "$C_LIST"; then
    if start_job addons "$C_LIST" "$C_ADDONS $R_CID"; then
      op_json
      reply true started "⬇️ 正在下载 $_sa_n…" "{\"id\":\"$R_CID\",\"op\":$R_OP}"
    else
      spawn_failed_reply
    fi
    return 0
  fi
  lock_drop "$LOCKD"
  reply true source_added "🔗 已添加 $_sa_n。拦截就绪后，请在“附加列表”中开启。" "{\"id\":\"$R_CID\"}"
}

cmd_source_del() {
  case $1 in
    c-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) reply false invalid_list '❌ 未知自定义列表。'; return 0 ;;
  esac
  if ! custom_info "$1"; then reply false invalid_list '❌ 未知自定义列表。'; return 0; fi
  _sd_n=$L_NAME
  lock_wait "$LOCKD" || { busy_reply; return 0; }
  cfg_load
  _sd_note=
  _sd_line=
  _sd_active=0
  word_in "$1" "$C_ADDONS" && _sd_active=1
  _sd_line=$(grep -F "^$1|" "$SRCF" 2>/dev/null | head -n 1)
  grep -v "^$1|" "$SRCF" > "$SRCF.tmp.$$" 2>/dev/null
  _sd_grep=$?
  # grep returns 1 when every line matched (the last custom source was the
  # only row); that is success, not a write failure.
  if [ "$_sd_grep" -gt 1 ]; then
    rm -f "$SRCF.tmp.$$"
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法更新自定义列表文件，未做任何更改。"
    log ERROR "重写 $SRCF 时移除自定义列表失败"
    return 0
  fi
  if ! mv -f "$SRCF.tmp.$$" "$SRCF" 2>/dev/null; then
    rm -f "$SRCF.tmp.$$"
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法更新自定义列表文件，未做任何更改。"
    log ERROR "移除自定义列表时无法替换 $SRCF"
    return 0
  fi
  if [ "$_sd_active" = 1 ]; then
    _sd_keep=
    for _sd_i in $C_ADDONS; do [ "$_sd_i" = "$1" ] || _sd_keep="$_sd_keep $_sd_i"; done
    _sd_old=$C_ADDONS
    C_ADDONS=${_sd_keep# }
    if ! cfg_save; then
      [ -n "$_sd_line" ] && printf '%s\n' "$_sd_line" >> "$SRCF" 2>/dev/null
      C_ADDONS=$_sd_old
      cfg_save
      lock_drop "$LOCKD"
      reply false write_failed "❌ 无法保存设置，未做任何更改。"
      log ERROR "移除自定义列表时无法保存设置"
      return 0
    fi
    if ! rebuild; then
      cfg_load
      C_ADDONS=$_sd_old
      cfg_save
      [ -n "$_sd_line" ] && printf '%s\n' "$_sd_line" >> "$SRCF" 2>/dev/null
      rebuild >/dev/null 2>&1
      lock_drop "$LOCKD"
      reply false "$RB_STATE" "❌ 无法重建 hosts 文件，已保留该自定义列表。"
      log ERROR "重建失败后，自定义列表移除操作已回滚"
      return 0
    fi
    change_note
    _sd_note=$R_NOTE
  fi
  if ! rm -f "$LISTSD/$1.domains" "$LISTSD/$1.info" "$METAD/$1" "$METAD/$1.busy" 2>/dev/null; then
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法移除自定义列表缓存，请查看 WebUI 日志。"
    log ERROR "清理 $1 的自定义列表缓存失败"
    return 0
  fi
  lock_drop "$LOCKD"
  log INFO "已移除自定义列表：$_sd_n"
  reply true source_removed "🗑️ 已移除 $_sd_n。$_sd_note"
}

cmd_cancel() {
  op_reconcile
  op_load
  if [ "$OP_STATE" != running ]; then
    reply false not_running 'ℹ️ 没有可取消的任务。'
    return 0
  fi
  case $OP_PHASE in
    prepare | check | download | verify | optimize)
      : > "$RUND/cancel"
      _cc=
      [ -f "$RUND/dl.pid" ] && read -r _cc < "$RUND/dl.pid"
      kill_tree "$_cc"
      log INFO "已请求取消"
      reply true cancelling '✖️ 正在取消…'
      ;;
    *)
      reply false too_late "⏳ 即将完成，新的 hosts 文件正在安装，此时无法取消。"
      ;;
  esac
}

cmd_rules() { rules_json; reply true rules '' "$R_RULES"; }

rule_names() {
  case $1 in
    allow) RF=$ALLOWF; RF_KEY=a; RF_NAME='放行'; RF_OTHERNAME='拦截' ;;
    block) RF=$BLOCKF; RF_KEY=b; RF_NAME='拦截'; RF_OTHERNAME='放行' ;;
    *) return 1 ;;
  esac
  return 0
}

cmd_rule_add() {
  if ! rule_names "$1"; then reply false invalid_type '❌ 未知规则类型。'; return 0; fi
  _ra=$(extract_domain "$2")
  _ra_p=$(domain_problem "$_ra" "$1")
  if [ -n "$_ra_p" ]; then reply false rule_invalid "$_ra_p"; return 0; fi
  lock_wait "$LOCKD" || { busy_reply; return 0; }
  printf '%s\t%s\n' "$RF_KEY" "$_ra" > "$TMPD/rules.in"
  if ! rules_engine merge "$TMPD/rules.in"; then
    rules_done
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法保存规则，请重试。"
    return 0
  fi
  if [ "$((RE_ADDED_A + RE_ADDED_B))" != 1 ]; then
    rules_done
    lock_drop "$LOCKD"
    case $RE_LASTREJ in
      exists) reply false rule_exists "⚠️ $_ra 已在你的$RF_NAME列表中。" ;;
      covered) reply false rule_exists "⚠️ $_ra 已被你的规则 $RE_LASTREF 放行。" ;;
      conflict) reply false rule_conflict "⚠️ 已在$RF_OTHERNAME列表中，请先在那里移除 $_ra。" ;;
      covers) reply false rule_conflict "⚠️ $_ra 还会放行 $RE_LASTREF，而它位于你的拦截列表中，请先移除它。" ;;
      blocked_by_wildcard) reply false rule_conflict "⚠️ $_ra 已被你的放行规则 $RE_LASTREF 覆盖，请先移除该规则。" ;;
      limit) reply false rule_limit "📦 该列表已达到 $(fmt_num "$RULE_MAX") 条规则上限，请先移除一些。" ;;
      *) reply false rule_invalid "🚫 这看起来不是有效域名，例如 ads.example.com。" ;;
    esac
    return 0
  fi
  if ! rules_commit; then
    rules_done
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法保存规则，请重试。"
    return 0
  fi
  if ! rebuild; then
    rules_rollback
    lock_drop "$LOCKD"
    log ERROR "添加 $_ra 后重建 hosts 文件失败，规则已回滚"
    reply false "$RB_STATE" "❌ 无法重建 hosts 文件，规则未添加。之前的 hosts 文件仍然保留。"
    return 0
  fi
  rules_done
  lock_drop "$LOCKD"
  if [ "$1" = allow ]; then _ra_e='✅'; _ra_v='已放行'; else _ra_e='⛔'; _ra_v='已拦截'; fi
  case $RB_STATE in
    disabled) _ra_m="$_ra_e $_ra 已保存到$RF_NAME列表，开启拦截后生效。" ;;
    nocache) _ra_m="$_ra_e $_ra 已保存到$RF_NAME列表，列表下载完成后生效。" ;;
    *)
      change_note
      if [ "$RB_CHANGED" = 1 ]; then
        _ra_m="$_ra_e $_ra $_ra_v。$R_NOTE"
      elif [ "$1" = allow ]; then
        _ra_m="$_ra_e $_ra 已放行。它不在当前列表中，因此暂时没有变化。"
      else
        _ra_m="$_ra_e $_ra 已拦截。当前列表已经拦截了它。"
      fi
      ;;
  esac
  log INFO "已添加$RF_NAME规则：$_ra"
  rules_json
  jbool "$RB_CHANGED"; _ra_c=$JB
  jbool "$RB_LIVE"
  reply true rule_added "$_ra_m" "{\"rules\":$R_RULES,\"changed\":$_ra_c,\"live\":$JB}"
}

cmd_rule_del() {
  if ! rule_names "$1"; then reply false invalid_type '❌ 未知规则类型。'; return 0; fi
  _rd=$(extract_domain "$2")
  case $_rd in
    '' | *[!a-z0-9._*-]*) _rd= ;;
  esac
  if [ -z "$_rd" ] || ! grep -qxF -e "$_rd" "$RF" 2>/dev/null; then
    reply false rule_missing "⚠️ 该域名不在你的$RF_NAME列表中。"
    return 0
  fi
  lock_wait "$LOCKD" || { busy_reply; return 0; }
  cp -f "$ALLOWF" "$ALLOWF.undo" 2>/dev/null
  cp -f "$BLOCKF" "$BLOCKF.undo" 2>/dev/null
  grep -vxF -e "$_rd" "$RF" > "$RF.tmp" 2>/dev/null
  if [ $? -gt 1 ] || ! mv -f "$RF.tmp" "$RF"; then
    rm -f "$RF.tmp"
    rules_done
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法移除规则，请重试。"
    return 0
  fi
  if ! rebuild; then
    rules_rollback
    lock_drop "$LOCKD"
    log ERROR "移除 $_rd 后重建 hosts 文件失败，规则已恢复"
    reply false "$RB_STATE" "❌ 无法重建 hosts 文件，规则已保留。之前的 hosts 文件仍然保留。"
    return 0
  fi
  rules_done
  lock_drop "$LOCKD"
  log INFO "已移除$RF_NAME规则：$_rd"
  change_note
  rules_json
  jbool "$RB_CHANGED"; _rd_c=$JB
  jbool "$RB_LIVE"
  reply true rule_removed "🗑️ 已从$RF_NAME列表中移除 $_rd。$R_NOTE" "{\"rules\":$R_RULES,\"changed\":$_rd_c,\"live\":$JB}"
}

cmd_rules_import() {
  _ri_mode=merge
  [ "${3:-}" = replace ] && _ri_mode=replace
  if [ -z "$1$2" ] && [ "$_ri_mode" != replace ]; then
    reply false import_empty '✏️ 没有可导入的内容。'
    return 0
  fi
  lock_wait "$LOCKD" || { busy_reply; return 0; }
  {
    printf '%s' "$1" | tr ', ' '\n\n' | awk 'NF { print "a\t" $1 }'
    printf '%s' "$2" | tr ', ' '\n\n' | awk 'NF { print "b\t" $1 }'
  } > "$TMPD/rules.in" 2>/dev/null
  if ! rules_engine "$_ri_mode" "$TMPD/rules.in"; then
    rules_done
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法导入规则，未做任何更改。"
    return 0
  fi
  _ri_add=$((RE_ADDED_A + RE_ADDED_B))
  _ri_skip=$((RE_INVALID + RE_DUP + RE_CONFLICT + RE_LIMIT))
  _ri_d="\"added\":$_ri_add,\"addedAllow\":$RE_ADDED_A,\"addedBlock\":$RE_ADDED_B,\"invalid\":$RE_INVALID,\"duplicate\":$RE_DUP,\"conflict\":$RE_CONFLICT,\"limit\":$RE_LIMIT"
  if [ "$_ri_add" = 0 ] && [ "$_ri_mode" != replace ]; then
    rules_done
    lock_drop "$LOCKD"
    rules_json
    reply false import_nothing "ℹ️ 没有新规则可导入，已跳过 $_ri_skip 条。" "{$_ri_d,\"rules\":$R_RULES}"
    return 0
  fi
  if ! rules_commit; then
    rules_done
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法导入规则，未做任何更改。"
    return 0
  fi
  if ! rebuild; then
    rules_rollback
    lock_drop "$LOCKD"
    log ERROR "导入规则后重建 hosts 文件失败，导入已回滚"
    reply false "$RB_STATE" "❌ 无法重建 hosts 文件，未导入任何内容。之前的 hosts 文件仍然保留。"
    return 0
  fi
  rules_done
  lock_drop "$LOCKD"
  change_note
  if [ "$_ri_mode" = replace ]; then
    _ri_m="📥 已替换规则，导入 $_ri_add 条。"
  else
    _ri_m="📥 已导入 $_ri_add 条规则。"
  fi
  [ "$_ri_skip" -gt 0 ] && _ri_m="$_ri_m 跳过 $_ri_skip 条。"
  log INFO "规则导入完成（$_ri_mode）：$RE_ADDED_A 条放行，$RE_ADDED_B 条拦截，跳过 $_ri_skip 条"
  rules_json
  jbool "$RB_CHANGED"; _ri_c=$JB
  jbool "$RB_LIVE"
  reply true rules_imported "$_ri_m$R_NOTE" "{$_ri_d,\"rules\":$R_RULES,\"changed\":$_ri_c,\"live\":$JB}"
}

cmd_lookup() {
  _lk=$(extract_domain "$1")
  case $_lk in '*.'*) _lk=${_lk#'*.'} ;; esac
  if [ -z "$_lk" ]; then reply false lookup_invalid '✏️ 请先输入域名或关键词。'; return 0; fi
  cfg_load
  applied_state
  jbool "$C_ENABLED"; _lk_en=$JB
  _lk_p=$(domain_problem "$_lk" block)
  if [ -n "$_lk_p" ]; then
    case $_lk in
      *[!a-z0-9-]* | ?? | ?) reply false lookup_invalid "$_lk_p"; return 0 ;;
    esac
    _lk_n=0
    _lk_m='[]'
    if [ "$C_ENABLED" = 1 ] && [ -f "$HOSTS" ]; then
      _lk_o=$(grep -F -e "$_lk" "$HOSTS" 2>/dev/null | awk '$1 == "0.0.0.0" { n++; if (n <= 40) print $2 } END { print n + 0 }')
      _lk_n=${_lk_o##*"$NL"}
      is_num "$_lk_n" || _lk_n=0
      [ "$_lk_n" -gt 0 ] && _lk_m=$(printf '%s\n' "$_lk_o" | awk -v n="$_lk_n" 'NR <= 40 && NR <= n' | awk "$AWK_JARR")
    fi
    if [ "$_lk_n" = 0 ]; then
      _lk_msg="🔍 没有已拦截域名包含“$_lk”。"
    else
      _lk_msg="🔍 有 $(fmt_num "$_lk_n") 个已拦截域名包含“$_lk”。"
    fi
    reply true lookup "$_lk_msg" "{\"type\":\"keyword\",\"query\":\"$_lk\",\"matchCount\":$_lk_n,\"matches\":$_lk_m,\"enabled\":$_lk_en,\"applied\":\"$R_APPLIED\"}"
    return 0
  fi
  _lk_rule=
  _lk_ref=
  if grep -qxF -e "$_lk" "$ALLOWF" 2>/dev/null; then
    _lk_rule=allow
    _lk_ref=$_lk
  else
    _lk_s=$_lk
    while :; do
      if grep -qxF -e "*.$_lk_s" "$ALLOWF" 2>/dev/null; then
        _lk_rule=allow
        _lk_ref="*.$_lk_s"
        break
      fi
      case $_lk_s in *.*) _lk_s=${_lk_s#*.} ;; *) break ;; esac
    done
  fi
  if [ -z "$_lk_rule" ] && grep -qxF -e "$_lk" "$BLOCKF" 2>/dev/null; then
    _lk_rule=block
    _lk_ref=$_lk
  fi
  _lk_src=
  _lk_names=
  for _lk_i in $C_LIST $C_ADDONS; do
    [ -s "$LISTSD/$_lk_i.domains" ] || continue
    grep -qxF -e "$_lk" "$LISTSD/$_lk_i.domains" 2>/dev/null || continue
    list_info "$_lk_i"
    js "$L_NAME"
    _lk_src="$_lk_src$JS,"
    _lk_names="$_lk_names${_lk_names:+, }$L_NAME"
  done
  _lk_src="[${_lk_src%,}]"
  _lk_in=false
  [ "$C_ENABLED" = 1 ] && grep -qxF -e "0.0.0.0 $_lk" "$HOSTS" 2>/dev/null && _lk_in=true
  _lk_n=0
  _lk_m='[]'
  if [ "$C_ENABLED" = 1 ] && [ -f "$HOSTS" ]; then
    _lk_o=$(grep -F -e ".$_lk" "$HOSTS" 2>/dev/null | awk -v s=".$_lk" '$1 == "0.0.0.0" && length($2) > length(s) && substr($2, length($2) - length(s) + 1) == s { n++; if (n <= 8) print $2 } END { print n + 0 }')
    _lk_n=${_lk_o##*"$NL"}
    is_num "$_lk_n" || _lk_n=0
    [ "$_lk_n" -gt 0 ] && _lk_m=$(printf '%s\n' "$_lk_o" | awk -v n="$_lk_n" 'NR <= 8 && NR <= n' | awk "$AWK_JARR")
  fi
  if [ "$C_ENABLED" != 1 ]; then
    _lk_st=disabled
    _lk_msg="🔴 拦截已关闭，$_lk 当前未被拦截。"
  elif [ "$_lk_in" = true ]; then
    _lk_st=blocked
    if [ "$_lk_rule" = block ]; then
      _lk_msg="⛔ $_lk 被你的拦截规则拦截。"
    else
      _lk_msg="⛔ $_lk 被 ${_lk_names:-你的列表} 拦截。"
    fi
  elif [ "$_lk_rule" = allow ]; then
    _lk_st=allowed
    if [ -n "$_lk_names" ]; then
      _lk_msg="✅ $_lk 被你的规则 $_lk_ref 放行；若无此规则，$_lk_names 会拦截它。"
    else
      _lk_msg="✅ $_lk 被你的规则 $_lk_ref 放行。"
    fi
  else
    _lk_st=clear
    _lk_msg="✅ $_lk 未被拦截。"
  fi
  reply true lookup "$_lk_msg" "{\"type\":\"domain\",\"query\":\"$_lk\",\"domain\":\"$_lk\",\"status\":\"$_lk_st\",\"rule\":\"$_lk_rule\",\"ref\":\"$_lk_ref\",\"sources\":$_lk_src,\"subCount\":$_lk_n,\"subs\":$_lk_m,\"enabled\":$_lk_en,\"applied\":\"$R_APPLIED\"}"
}

cmd_disable() {
  cfg_load
  if [ "$C_ENABLED" != 1 ]; then reply false already_disabled '🔴 拦截已处于关闭状态。'; return 0; fi
  lock_wait "$LOCKD" || { busy_reply; return 0; }
  if ! compile_into "$HOSTSD/.hosts.hknew" 0; then
    rm -f "$HOSTSD/.hosts.hknew"
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法写入 hosts 文件，未做任何更改。"
    return 0
  fi
  if ! install_hosts "$HOSTSD/.hosts.hknew" 0; then
    lock_drop "$LOCKD"
    reply false write_failed "❌ 无法写入 hosts 文件，已恢复之前的 hosts 文件。"
    return 0
  fi
  C_ENABLED=0
  cfg_save
  _ds_live=0
  if [ "$IH_CHANGED" = 1 ]; then
    settle_change && _ds_live=1
  else
    apply_now && _ds_live=1
  fi
  set_description
  lock_drop "$LOCKD"
  log INFO "拦截已关闭，列表和规则均已保留"
  if [ "$_ds_live" = 1 ]; then
    reply true disabled '🔴 已关闭拦截。当前不再拦截，列表和规则均已保留。' '{"live":true}'
  else
    reply true disabled '🔴 已关闭拦截。重启后停止拦截，列表和规则均已保留。' '{"live":false}'
  fi
}

cmd_enable() {
  cfg_load
  if [ "$C_ENABLED" = 1 ]; then reply false already_enabled '🟢 拦截已处于开启状态。'; return 0; fi
  lock_wait "$LOCKD" || { busy_reply; return 0; }
  _en_name=$L_NAME
  if [ "$C_SETUP" = ready ] && sources_ready; then
    C_ENABLED=1
    if ! compile_into "$HOSTSD/.hosts.hknew" 1; then
      rm -f "$HOSTSD/.hosts.hknew"
      lock_drop "$LOCKD"
      reply false write_failed "❌ 无法构建 hosts 文件，未做任何更改。"
      return 0
    fi
    if ! install_hosts "$HOSTSD/.hosts.hknew" "$CH_COUNT"; then
      lock_drop "$LOCKD"
      reply false write_failed "❌ 无法写入 hosts 文件，已恢复之前的 hosts 文件。"
      return 0
    fi
    C_DOMAINS=$CH_COUNT
    cfg_save
    stats_commit
    _en_live=0
    if [ "$IH_CHANGED" = 1 ]; then
      settle_change && _en_live=1
    else
      apply_now && _en_live=1
    fi
    set_description
    lock_drop "$LOCKD"
    log INFO "已使用 $_en_name 开启拦截，共 $(fmt_num "$CH_COUNT") 个域名"
    if [ "$_en_live" = 1 ]; then
      reply true enabled "🟢 已开启拦截，共 $(fmt_num "$CH_COUNT") 个域名，当前已生效。" '{"live":true}'
    else
      reply true enabled "🟢 已开启拦截，共 $(fmt_num "$CH_COUNT") 个域名，重启后生效。" '{"live":false}'
    fi
    return 0
  fi
  log INFO "已请求开启拦截，但缓存列表缺失，正在重新下载"
  if start_job enable "$C_LIST" "$C_ADDONS"; then
    job_reply "⬇️ 正在下载 $_en_name，以重新开启拦截…"
  else
    spawn_failed_reply
  fi
}

settings_json() {
  jbool "$C_LIVE"; _sj_l=$JB
  _sj_s=false; sched_alive && _sj_s=true
  R_SETTINGS="{\"live\":$_sj_l,\"autoupdate\":$C_AUTO,\"sched\":$_sj_s}"
}

cmd_settings() { cfg_load; settings_json; reply true settings '' "$R_SETTINGS"; }

cmd_set() {
  case $1 in
    live)
      case $2 in 0 | 1) ;; *) reply false invalid_value '❌ 未知取值。'; return 0 ;; esac
      lock_wait "$LOCKD" || { busy_reply; return 0; }
      cfg_load
      C_LIVE=$2
      cfg_save
      if [ "$2" = 1 ]; then
        _se_m='⚡ 即时生效已开启。设备允许时，更改会立即生效。'
        if [ "$C_SETUP" = ready ] && ! hosts_live; then
          if apply_now; then
            flush_dns
            _se_m='⚡ 即时生效已开启，待处理的更改现已生效。'
          else
            _se_m='⚡ 即时生效已开启，但待处理的更改仍需重启一次。'
          fi
        fi
      else
        _se_m='🔁 即时生效已关闭，更改将在重启后生效。'
      fi
      set_description
      lock_drop "$LOCKD"
      log INFO "即时生效已$([ "$2" = 1 ] && printf 开启 || printf 关闭)"
      settings_json
      reply true setting_saved "$_se_m" "$R_SETTINGS"
      ;;
    autoupdate)
      case $2 in 0 | 1 | 3 | 7) ;; *) reply false invalid_value '❌ 未知取值。'; return 0 ;; esac
      lock_wait "$LOCKD" || { busy_reply; return 0; }
      cfg_load
      C_AUTO=$2
      cfg_save
      lock_drop "$LOCKD"
      sched_sync
      case $2 in
        0) _se_m='🔕 自动更新已关闭。' ;;
        1) _se_m='🔄 自动更新已开启，每天检查一次列表。' ;;
        *) _se_m="🔄 自动更新已开启，每 $2 天检查一次列表。" ;;
      esac
      log INFO "自动更新已设置为每 $2 天一次"
      settings_json
      reply true setting_saved "$_se_m" "$R_SETTINGS"
      ;;
    *) reply false invalid_setting '❌ 未知设置项。' ;;
  esac
}

diag_add() {
  js "$3"; _dg_t=$JS
  js "$4"
  DG="$DG{\"id\":\"$2\",\"level\":\"$1\",\"title\":$_dg_t,\"detail\":$JS},"
  case $1 in
    ok) DG_OK=$((DG_OK + 1)) ;;
    warn) DG_WARN=$((DG_WARN + 1)) ;;
    err) DG_ERR=$((DG_ERR + 1)) ;;
  esac
}

cmd_diag() {
  if ! lock_take "$DIAGLOCK"; then
    log WARN "健康检查被忽略：上一次诊断仍在运行"
    reply false diag_busy '⏳ 健康检查正在进行，请稍后重试。'
    return 0
  fi
  _dg_t0=$(now)
  log INFO "健康检查开始（WebUI 请求，HostKeeper $HK_VER）"
  DG=; DG_OK=0; DG_WARN=0; DG_ERR=0
  cfg_load
  DL_GUARD_PRIVATE=0; DL_MAX_REDIR=5
  if [ "$L_CUSTOM" = 1 ]; then DL_GUARD_PRIVATE=1; DL_MAX_REDIR=0; fi
  _dg_name=$L_NAME
  _dg_url=$L_URL
  _dg_alt=$L_URL_ALT
  _dg_host=${_dg_url#*://}
  _dg_host=${_dg_host%%/*}
  _dg_althost=
  [ -n "$_dg_alt" ] && { _dg_althost=${_dg_alt#*://}; _dg_althost=${_dg_althost%%/*}; }
  detect_manager
  applied_state
  conflicts_scan
  mount_mode
  _dg_now=$(now)

  if [ "$C_SETUP" != ready ]; then
    diag_add warn setup '⏳ 初始化' "首个列表尚未下载，请点击“立即下载”。"
  elif [ "$C_ENABLED" != 1 ]; then
    diag_add warn blocker '🛡️ 拦截状态' '拦截开关已关闭，当前不会拦截任何内容。'
  else
    diag_add ok blocker '🛡️ 拦截状态' "已开启，使用 $_dg_name，已拦截 $(fmt_num "$C_DOMAINS") 个域名。"
  fi

  if [ ! -f "$HOSTS" ]; then
    diag_add err integrity '🧾 Hosts 文件' 'hosts 文件不存在，请点击“修复”重新构建。'
  else
    _dg_want=$C_DOMAINS
    [ "$C_ENABLED" = 1 ] && [ "$C_SETUP" = ready ] || _dg_want=0
    if ! verify_hosts_deep "$_dg_want"; then
      diag_add err integrity '🧾 Hosts 文件' 'hosts 文件与 HostKeeper 构建的内容不一致，请点击“修复”重新构建。'
    else
      sum_check
      case $? in
        0) diag_add ok integrity '🧾 Hosts 文件' "校验通过：$(fmt_num "$_dg_want") 条记录，$(fmt_mb "$(fsize "$HOSTS")")，校验和匹配。" ;;
        1) diag_add err integrity '🧾 Hosts 文件' '校验和不匹配，请点击“修复”重新构建。' ;;
        *) diag_add warn integrity '🧾 Hosts 文件' '当前可用工具无法校验校验和，请点击“修复”重新构建。' ;;
      esac
    fi
  fi

  case $R_APPLIED in
    applied)
      case $R_MOUNT in
        self) diag_add ok applied '🧪 系统生效状态' 'Android 正在使用 HostKeeper 的 hosts 文件，由 HostKeeper 直接挂载。' ;;
        *) diag_add ok applied '🧪 系统生效状态' 'Android 正在使用 HostKeeper 的 hosts 文件。' ;;
      esac
      ;;
    pending) diag_add warn applied '🧪 系统生效状态' '最新更改将在重启后生效。' ;;
    overridden) diag_add err applied '🧪 系统生效状态' "另一个模块正在提供 /system/etc/hosts：$R_CONF。请停用它并重启。" ;;
    inactive) diag_add err applied '🧪 系统生效状态' 'Android 未使用 HostKeeper 的 hosts 文件。请重启，或点击“修复”立即挂载。' ;;
    *) diag_add warn applied '🧪 系统生效状态' '无法检查系统 hosts 文件。' ;;
  esac

  if [ -n "$R_CONF" ] && [ "$R_APPLIED" != overridden ]; then
    diag_add warn conflicts '🧩 其他 hosts 模块' "以下模块也带有 hosts 文件：$R_CONF。"
  elif [ -z "$R_CONF" ]; then
    if [ -d /data/data/org.adaway ]; then
      diag_add warn conflicts '🧩 其他 hosts 模块' '检测到 AdAway。请不要同时使用它的 root 模式与 HostKeeper。'
    else
      diag_add ok conflicts '🧩 其他 hosts 模块' '未发现冲突的 hosts 模块。'
    fi
  fi

  if [ "$C_SETUP" = ready ]; then
    _dg_miss=
    for _dg_i in $C_LIST $C_ADDONS; do
      src_ready "$_dg_i" && continue
      list_info "$_dg_i"
      _dg_miss="$_dg_miss${_dg_miss:+, }$L_NAME"
    done
    if [ -n "$_dg_miss" ]; then
      diag_add warn caches '🗂️ 列表缓存' "缓存中缺少：$_dg_miss。请点击“更新列表”重新下载。"
    else
      set -- $C_ADDONS
      diag_add ok caches '🗂️ 列表缓存' "$_dg_name 和 $# 个附加列表已缓存，可即时重建。"
    fi
    _dg_age=$(((_dg_now - C_UPDATED) / 86400))
    if [ "$C_UPDATED" = 0 ]; then
      diag_add warn freshness '🕒 列表更新时间' '列表从未更新过。'
    elif [ "$_dg_age" -ge "$STALE_DAYS" ]; then
      diag_add warn freshness '🕒 列表更新时间' "上次更新是在 $_dg_age 天前。请点击“更新列表”，或开启自动更新。"
    else
      diag_add ok freshness '🕒 列表更新时间' "上次更新是在 $_dg_age 天前。"
    fi
  fi

  if [ "$C_AUTO" -gt 0 ]; then
    if sched_alive; then
      diag_add ok scheduler '🔄 自动更新' "已开启，每 $C_AUTO 天一次，调度器正在运行。"
    else
      diag_add warn scheduler '🔄 自动更新' '已开启，但调度器未运行。下次开机或重新保存设置后会启动。'
    fi
  else
    diag_add info scheduler '🔄 自动更新' '已关闭。只有点击“更新列表”时才会更新。'
  fi

  if [ "$C_LIVE" = 1 ]; then
    diag_add info live '⚡ 即时生效' '已开启。更改会直接写入，并在可能时无需重启即可生效。'
  else
    diag_add info live '⚡ 即时生效' '已关闭。更改将在重启后生效。'
  fi

  if dl_detect; then
    if [ "$DL_TOOL" = curl ]; then
      if [ "$DL_GZ" = 1 ]; then
        diag_add ok downloader '⬇️ 下载工具' 'curl，启用压缩传输。'
      else
        diag_add ok downloader '⬇️ 下载工具' 'curl。'
      fi
    else
      diag_add ok downloader '⬇️ 下载工具' 'BusyBox wget。'
    fi
    DL_MAX_TIME=20
    if dl_get "$_dg_url" "$TMPD/diag.body" "$TMPD/diag.hdr" peek; then
      if [ -n "$_dg_althost" ]; then
        diag_add ok network '🌐 列表服务器' "可访问（HTTP $DL_CODE）。主源 $_dg_host · 备用源 $_dg_althost。"
      else
        diag_add ok network '🌐 列表服务器' "可访问（HTTP $DL_CODE）。主源 $_dg_host · 该列表未配置备用源。"
      fi
    else
      _dg_net_why=$(dl_reason)
      if [ -n "$_dg_althost" ]; then
        diag_add warn network '🌐 列表服务器' "主源 $_dg_host 无法连接：$_dg_net_why。更新时会尝试备用源 $_dg_althost。"
      else
        diag_add warn network '🌐 列表服务器' "无法连接 $_dg_name 的服务器：$_dg_net_why。该列表没有备用源，请切换列表或稍后重试。"
      fi
      log WARN "健康检查网络探测失败：$_dg_name：$_dg_net_why"
    fi
    DL_MAX_TIME=
    rm -f "$TMPD/diag.body" "$TMPD/diag.hdr" "$TMPD/diag.hdr.err"
  else
    diag_add err downloader '⬇️ 下载工具' 'curl 和 BusyBox wget 都不可用，无法下载列表。'
    log ERROR "健康检查失败：curl 和 BusyBox wget 都不可用"
  fi

  if meta_load "$C_LIST"; then
    if [ -n "$M_ERR" ]; then
      diag_add warn source '🗂️ 下载源' "上次获取 $L_NAME 详情失败：$(source_error_text "$M_ERR")。"
    elif [ -n "$_dg_althost" ]; then
      diag_add ok source '🗂️ 下载源' "主源 $_dg_host，备用源 $_dg_althost。"
    else
      diag_add ok source '🗂️ 下载源' "主源 $_dg_host；该列表没有备用源。"
    fi
  fi

  if [ "$HK_BB" = none ]; then
    diag_add warn busybox '🧰 BusyBox' '未找到 root 管理器的 BusyBox，HostKeeper 正在使用系统工具。'
  elif [ "$MGR_HTTPD" = yes ]; then
    diag_add ok busybox '🧰 BusyBox' "$HK_BB，包含供浏览器 WebUI 使用的 httpd。"
  else
    diag_add warn busybox '🧰 BusyBox' "$HK_BB 不包含 httpd，因此 Action 按钮无法在浏览器中打开 WebUI。"
  fi

  _dg_free=$(free_kb "$DATA")
  if is_num "$_dg_free"; then
    if [ "$_dg_free" -lt 51200 ]; then
      diag_add warn storage '💾 存储空间' "仅剩 $((_dg_free / 1024)) MB，更新至少需要 50 MB。"
    else
      diag_add ok storage '💾 存储空间' "剩余 $((_dg_free / 1024)) MB。"
    fi
  fi

  guard_detect
  if [ -n "$R_GUARD" ]; then
    live_hosts
    if grep -qxF -e "0.0.0.0 $R_GUARD" "$R_LIVE" 2>/dev/null; then
      diag_add err privatedns '🔏 私人 DNS' "你的私人 DNS 提供商 $R_GUARD 当前被拦截，请点击“修复”。"
    else
      diag_add ok privatedns '🔏 私人 DNS' "提供商 $R_GUARD 已受保护，不会被拦截。"
    fi
  fi

  count_lines "$ALLOWF"; _dg_a=$R_LINES
  count_lines "$BLOCKF"; _dg_b=$R_LINES
  diag_add info rules '🧩 域名规则' "$_dg_a 条放行规则，$_dg_b 条拦截规则。"

  _dg_v=
  [ -n "$MGR_VER" ] && _dg_v=" $MGR_VER"
  diag_add info environment '📦 运行环境' "HostKeeper $HK_VER ($HK_VCODE)，运行于 $MGR_NAME$_dg_v，Android $(getprop ro.build.version.release 2>/dev/null)。"

  log INFO "健康检查完成：ok=$DG_OK warn=$DG_WARN err=$DG_ERR，耗时 $(( $(now) - _dg_t0 )) 秒"
  lock_drop "$DIAGLOCK"
  reply true diag '' "{\"checks\":[${DG%,}],\"summary\":{\"ok\":$DG_OK,\"warn\":$DG_WARN,\"err\":$DG_ERR}}"
}

cmd_repair() {
  lock_wait "$LOCKD" || { busy_reply; return 0; }
  cfg_load
  rm -f "$SUMF"
  _rp_ok=1
  if [ "$C_ENABLED" != 1 ]; then
    if compile_into "$HOSTSD/.hosts.hknew" 0 && install_hosts "$HOSTSD/.hosts.hknew" 0; then
      C_DOMAINS=0
      if sources_ready; then C_SETUP=ready; else C_SETUP=pending; fi
      cfg_save
      stats_commit
    else
      _rp_ok=0
    fi
    rm -f "$HOSTSD/.hosts.hknew"
  elif [ "$C_SETUP" = ready ] && sources_ready; then
    if compile_into "$HOSTSD/.hosts.hknew" "$C_ENABLED" && install_hosts "$HOSTSD/.hosts.hknew" "$CH_COUNT"; then
      C_DOMAINS=$CH_COUNT
      cfg_save
      stats_commit
    else
      _rp_ok=0
    fi
    rm -f "$HOSTSD/.hosts.hknew"
  elif sources_ready; then
    if compile_into "$HOSTSD/.hosts.hknew" "$C_ENABLED" && install_hosts "$HOSTSD/.hosts.hknew" "$CH_COUNT"; then
      C_DOMAINS=$CH_COUNT
      C_SETUP=ready
      cfg_save
      stats_commit
    else
      _rp_ok=0
    fi
    rm -f "$HOSTSD/.hosts.hknew"
  else
    if write_clean_hosts; then
      C_DOMAINS=0
      C_SETUP=pending
      cfg_save
    else
      _rp_ok=0
    fi
  fi
  if [ "$_rp_ok" = 0 ]; then
    lock_drop "$LOCKD"
    log ERROR "修复失败：无法重建 hosts 文件"
    reply false write_failed "❌ 无法重建 hosts 文件，请查看 📜 日志 了解详情。"
    return 0
  fi
  [ -f "$SUMF" ] || sum_record "$C_DOMAINS"
  _rp_live=false
  if apply_now; then
    _rp_live=true
    flush_dns
  else
    mark_pending
  fi
  set_description
  lock_drop "$LOCKD"
  log INFO "修复完成：hosts 文件已重建并校验"
  if [ "$C_SETUP" != ready ]; then
    reply true repaired '🛠️ 修复完成。请点击“立即下载”获取列表。' "{\"live\":$_rp_live}"
  elif [ "$_rp_live" = true ]; then
    reply true repaired '🛠️ 修复完成，hosts 文件已重建并生效。' "{\"live\":$_rp_live}"
  else
    reply true repaired '🛠️ 修复完成，hosts 文件已重建，重启后生效。' "{\"live\":$_rp_live}"
  fi
}

cmd_logs() {
  if [ -s "$LOGF" ]; then
    reply true logs '' "{\"logs\":$(awk "$AWK_LOGS" "$LOGF")}"
  else
    reply true logs '' '{"logs":[]}'
  fi
}

cmd_logs_clear() {
  : > "$LOGF"
  reply true logs_cleared '🧹 日志已清空。'
}

cmd_reboot() {
  if [ ! -x /system/bin/svc ] && [ ! -x /system/bin/reboot ]; then
    reply false reboot_failed "❌ 无法从这里重启设备，请手动重启。"
    return 0
  fi
  log INFO "已从 WebUI 请求重启"
  reply true rebooting '🔁 正在重启设备…'
  if has setsid; then
    setsid sh -c 'sleep 2; /system/bin/svc power reboot || /system/bin/reboot || /system/bin/setprop sys.powerctl reboot' < /dev/null > /dev/null 2>&1 &
  else
    sh -c 'sleep 2; /system/bin/svc power reboot || /system/bin/reboot || /system/bin/setprop sys.powerctl reboot' < /dev/null > /dev/null 2>&1 &
  fi
}

cmd_open() {
  case $1 in
    stevenblack) _op=https://github.com/StevenBlack/hosts ;;
    hblock) _op=https://github.com/hectorm/hblock ;;
    hagezi) _op=https://github.com/hagezi/dns-blocklists ;;
    inter) _op=https://github.com/rsms/inter ;;
    *) reply false invalid_link '❓ 未知链接。'; return 0 ;;
  esac
  if open_url "$_op"; then
    reply true opened '🌐 正在浏览器中打开…'
  else
    reply false open_failed "❌ 无法打开浏览器，请手动访问 $_op。"
  fi
}

cmd_help() {
  cat << EOF
🛡️ HostKeeper $HK_VER — command line
Usage: sh $SELF <command> [arguments]
Every command except help prints one line of JSON and exits 0 on success, 1 on failure.

  status                     overall state
  lists                      catalog of lists and add-ons
  apply <list>               switch the main list
  update                     check every active list and download what changed
  addons <id,id,...>         set the active add-ons (empty turns all off)
  source-add <https-url> [name]   add and enable a custom list
  source-del <id>            remove a custom list
  progress                   state of the running task
  wait [seconds]             block until the running task has finished
  cancel                     cancel the running download
  rules                      show allow and block rules
  rule-add <allow|block> <domain>
  rule-del <allow|block> <domain>
  rules-import <allow,csv> <block,csv> [replace]
  lookup <domain|keyword>    explain whether and why a domain is blocked
  enable | disable           turn blocking on or off
  settings                   show settings
  set live <0|1>             apply changes without a reboot
  set autoupdate <0|1|3|7>   check for updates every N days
  diag                       run the health check
  repair                     rebuild the hosts file and re-check the mount
  logs | logs-clear
  reboot
EOF
}

dispatch() {
  case ${1:-} in
    status) cmd_status ;;
    progress) cmd_progress ;;
    wait) cmd_wait "${2:-}" ;;
    lists) cmd_lists ;;
    meta-refresh) cmd_meta_refresh "${2:-}" ;;
    apply) cmd_apply "${2:-}" ;;
    update) cmd_update ;;
    addons) cmd_addons "${2:-}" ;;
    source-add) cmd_source_add "${2:-}" "${3:-}" ;;
    source-del) cmd_source_del "${2:-}" ;;
    cancel) cmd_cancel ;;
    rules) cmd_rules ;;
    rule-add) cmd_rule_add "${2:-}" "${3:-}" ;;
    rule-del) cmd_rule_del "${2:-}" "${3:-}" ;;
    rules-import) cmd_rules_import "${2:-}" "${3:-}" "${4:-}" ;;
    lookup) cmd_lookup "${2:-}" ;;
    disable) cmd_disable ;;
    enable) cmd_enable ;;
    settings) cmd_settings ;;
    set) cmd_set "${2:-}" "${3:-}" ;;
    diag) cmd_diag ;;
    repair) cmd_repair ;;
    logs) cmd_logs ;;
    logs-clear) cmd_logs_clear ;;
    reboot) cmd_reboot ;;
    open) cmd_open "${2:-}" ;;
    ping) reply true pong '' ;;
    help | -h | --help) cmd_help ;;
    *) reply false unknown_command '❓ 未知命令。运行 help 查看可用命令。' ;;
  esac
}

port_listening() {
  _pl_x=$(printf ':%04X' "$PORT")
  for _pl_f in /proc/net/tcp /proc/net/tcp6; do
    [ -r "$_pl_f" ] || continue
    awk -v p="$_pl_x" 'NR > 1 && $4 == "0A" && substr($2, length($2) - 4) == p { f = 1 } END { exit !f }' "$_pl_f" && return 0
  done
  return 1
}

pid_alive() { is_num "$1" && [ -d "/proc/$1" ]; }

proc_cmdline() {
  [ -r "/proc/$1/cmdline" ] && tr '\000' ' ' < "/proc/$1/cmdline" 2>/dev/null
}

pid_is_hostkeeper_serve() {
  _phs_cmd=$(proc_cmdline "$1")
  case $_phs_cmd in *hostkeeper.sh*_serve*) return 0 ;; *) return 1 ;; esac
}

pid_is_httpd_for_run() {
  _phh_cmd=$(proc_cmdline "$1")
  case $_phh_cmd in *httpd*"$RUND/www"*) return 0 ;; *) return 1 ;; esac
}

server_running() {
  _sr_w=; _sr_h=
  [ -f "$RUND/watchdog.pid" ] && read -r _sr_w < "$RUND/watchdog.pid"
  [ -f "$RUND/httpd.pid" ] && read -r _sr_h < "$RUND/httpd.pid"
  pid_alive "$_sr_w" && pid_alive "$_sr_h" && [ -s "$RUND/token" ] && port_listening
}

gen_token() {
  _gt=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -dc '0-9a-f')
  [ "${#_gt}" -eq 32 ] || _gt=$(tr -dc '0-9a-f' < /proc/sys/kernel/random/uuid)
  printf '%s' "$_gt"
}

server_prepare() {
  rm -rf "$RUND/www"
  mkdir -p "$RUND/www/cgi-bin" || return 1
  cp -r "$MODDIR/webroot/." "$RUND/www/" || return 1
  chmod 0700 "$RUND" "$RUND/www" "$RUND/www/cgi-bin" 2>/dev/null
  printf '#!/system/bin/sh\nexec /system/bin/sh "%s" cgi\n' "$MODDIR/hostkeeper.sh" > "$RUND/www/cgi-bin/api" || return 1
  chmod 0755 "$RUND/www/cgi-bin/api"
  {
    printf 'A:127.0.0.1\nD:*\n'
    printf '.woff2:font/woff2\n.svg:image/svg+xml\n.json:application/json\n.js:text/javascript\n.css:text/css\n'
  } > "$RUND/httpd.conf"
  ( umask 077; gen_token > "$RUND/token" )
  chmod 0600 "$RUND/token"
  [ "$(wc -c < "$RUND/token")" -eq 32 ]
}

touch_activity() {
  date +%s > "$RUND/last_request.$$" 2>/dev/null && mv -f "$RUND/last_request.$$" "$RUND/last_request"
  rm -f "$RUND/last_request.$$" 2>/dev/null
  return 0
}

server_cleanup() {
  rm -rf "$RUND/www" 2>/dev/null
  rm -f "$RUND/token" "$RUND/httpd.pid" "$RUND/watchdog.pid" "$RUND/last_request" "$RUND"/last_request.* "$RUND/httpd.conf" 2>/dev/null
  return 0
}

server_stop() {
  _ss_w=; _ss_h=
  [ -f "$RUND/watchdog.pid" ] && read -r _ss_w < "$RUND/watchdog.pid"
  [ -f "$RUND/httpd.pid" ] && read -r _ss_h < "$RUND/httpd.pid"
  if pid_alive "$_ss_h" && pid_is_httpd_for_run "$_ss_h"; then
    kill "$_ss_h" 2>/dev/null
  elif pid_alive "$_ss_h"; then
    log WARN "忽略过期的 WebUI httpd 进程 $_ss_h：命令行与当前运行目录不匹配"
  fi
  if pid_alive "$_ss_w" && pid_is_hostkeeper_serve "$_ss_w"; then
    kill "$_ss_w" 2>/dev/null
  elif pid_alive "$_ss_w"; then
    log WARN "忽略过期的 WebUI 守护进程 $_ss_w：命令行与 hostkeeper _serve 不匹配"
  fi
  server_cleanup
}

serve_main() {
  MODE=worker
  echo "$$" > "$RUND/watchdog.pid"
  "$HK_BB" httpd -f -p "127.0.0.1:$PORT" -h "$RUND/www" -c "$RUND/httpd.conf" &
  _sv_h=$!
  echo "$_sv_h" > "$RUND/httpd.pid"
  touch_activity
  spawned
  _sv_s=
  trap 'kill "$_sv_h" $_sv_s 2>/dev/null; server_cleanup; exit 0' TERM INT HUP
  log INFO "本地 WebUI 服务已启动：127.0.0.1:$PORT"
  while kill -0 "$_sv_h" 2>/dev/null; do
    sleep 15 &
    _sv_s=$!
    wait "$_sv_s"
    _sv_s=
    if [ ! -f "$RUND/last_request" ]; then
      kill "$_sv_h" 2>/dev/null
      break
    fi
    _sv_l=
    read -r _sv_l < "$RUND/last_request"
    is_num "$_sv_l" || continue
    if [ $(($(date +%s) - _sv_l)) -ge "$IDLE_LIMIT" ]; then
      log INFO "本地 WebUI 服务在 10 分钟无活动后已停止"
      kill "$_sv_h" 2>/dev/null
      break
    fi
  done
  wait "$_sv_h" 2>/dev/null
  server_cleanup
}

cgi_headers() {
  printf '%s\r\n' \
    'Content-Type: application/json; charset=utf-8' \
    'Cache-Control: no-store' \
    'X-Content-Type-Options: nosniff' \
    'X-Frame-Options: DENY' \
    'Referrer-Policy: no-referrer' \
    "Content-Security-Policy: default-src 'none'; frame-ancestors 'none'" \
    'Cross-Origin-Resource-Policy: same-origin' \
    'Permissions-Policy: camera=(), microphone=(), geolocation=()' \
    ''
}

cgi_deny() {
  printf 'HTTP/1.0 403 Forbidden\r\n'
  cgi_headers
  reply false unauthorized "$1"
}

cgi_main() {
  case ${REQUEST_METHOD:-GET} in
    POST)
      _cg_n=${CONTENT_LENGTH:-0}
      if ! is_num "$_cg_n" || [ "$_cg_n" -gt 262144 ]; then cgi_deny '🚫 Request rejected.'; return 0; fi
      _cg_q=
      [ "$_cg_n" -gt 0 ] && _cg_q=$(head -c "$_cg_n")
      ;;
    *)
      # The WebUI always POSTs commands. Reject GET so the token can never
      # land in httpd access logs or browser history.
      cgi_deny '🚫 Request rejected.'
      return 0
      ;;
  esac
  _cg_p=$(printf '%s\n' "$_cg_q" | awk "$AWK_QUERY")
  { IFS= read -r Q_T; IFS= read -r Q_C; IFS= read -r Q_A; IFS= read -r Q_B; IFS= read -r Q_D; } << EOF
$_cg_p
EOF
  _cg_t=
  [ -f "$RUND/token" ] && read -r _cg_t < "$RUND/token"
  if [ "${#_cg_t}" -ne 32 ] || [ "$Q_T" != "$_cg_t" ]; then
    cgi_deny '🔑 This session has expired. Press the Action button on HostKeeper in your root manager to open a new one.'
    return 0
  fi
  case ${HTTP_HOST:-} in
    "127.0.0.1:$PORT" | "localhost:$PORT") ;;
    *) cgi_deny '🚫 Request rejected.'; return 0 ;;
  esac
  # Empty Referer is allowed on purpose: the frontend uses
  # referrerPolicy=no-referrer and the token is still required in POST.
  case ${HTTP_REFERER:-} in
    '' | "http://127.0.0.1:$PORT/"* | "http://localhost:$PORT/"*) ;;
    *) cgi_deny '🚫 Request rejected.'; return 0 ;;
  esac
  touch_activity
  cgi_headers
  dispatch "$Q_C" "$Q_A" "$Q_B" "$Q_D"
}

action_main() {
  MODE=action
  ensure_dirs
  detect_manager
  printf '\n🛡️ HostKeeper %s\n' "$HK_VER"
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  describe
  printf '%s\n\n' "${R_DESC#🛡️ }"
  case $MGR_NAME in
    KernelSU* | SukiSU* | APatch) _ac_ksu=1 ;;
    *) _ac_ksu=0 ;;
  esac
  if ! httpd_available; then
    printf '%s\n' "❌ 此设备没有 BusyBox httpd，本地 WebUI 服务无法启动。"
    if [ "$_ac_ksu" = 1 ]; then
      printf '💡 请改用 HostKeeper 卡片上的 WebUI 按钮。\n'
    else
      printf '💡 KsuWebUI、MMRL 或 WebUI X 可在不启动本地服务的情况下打开 HostKeeper WebUI。\n'
    fi
    log ERROR "本地 WebUI 服务不可用：未找到 BusyBox httpd"
    return 0
  fi
  if server_running; then
    read -r _ac_t < "$RUND/token"
    touch_activity
    printf '♻️ WebUI 服务已在运行，正在重新打开。\n'
  else
    server_stop
    if port_listening; then
      printf '❌ 端口 %s 已被其他应用占用。\n' "$PORT"
      printf '💡 请关闭该应用或重启设备，然后再次点击 Action。\n'
      log ERROR "端口 $PORT 已被其他应用占用，WebUI 服务未启动"
      return 0
    fi
    printf '🚀 正在启动本地 WebUI 服务…\n'
    if ! server_prepare; then
      server_cleanup
      printf '%s\n' "❌ 无法准备 WebUI 文件，请重试。"
      log ERROR "无法准备 WebUI 服务文件"
      return 0
    fi
    if ! spawn "$RUND/server.out" _serve; then
      server_stop
      printf '❌ WebUI 服务启动失败，请重试。\n'
      log ERROR "WebUI 服务进程未能启动"
      return 0
    fi
    _ac_i=0
    while [ "$_ac_i" -lt 30 ] && ! port_listening; do
      nap 0.2
      _ac_i=$((_ac_i + 1))
    done
    if ! port_listening; then
      server_stop
      printf '❌ WebUI 服务启动失败，请重试。\n'
      log ERROR "WebUI 服务未在端口 $PORT 开始监听"
      return 0
    fi
    read -r _ac_t < "$RUND/token"
    printf '✅ 服务已运行：http://127.0.0.1:%s（仅本机可访问）\n' "$PORT"
    printf '🔐 已使用一次性会话令牌保护\n'
  fi
  _ac_u="http://127.0.0.1:$PORT/#t=$_ac_t"
  printf '🌐 正在打开浏览器…\n'
  if ! open_url "$_ac_u"; then
    printf '%s\n%s\n' "⚠️ 无法自动打开浏览器，请手动访问以下地址：" "$_ac_u"
  fi
  printf '⏱️ 服务在 10 分钟无活动后会自动停止。\n'
  if [ "$_ac_ksu" = 1 ]; then
    printf '💡 提示：点击 HostKeeper 卡片上的 WebUI 按钮，也能在 %s 中打开同一界面。\n' "$MGR_NAME"
  fi
  printf '\n'
}

run_job() {
  if pipeline "$1" "$2" "$3"; then
    OP_DOMAINS=$PL_DOMAINS
    OP_REBOOT=$PL_REBOOT
    OP_LIVE=$PL_LIVE
    OP_WARN=$PL_WARN
    op_finish success "$PL_CODE" "$PL_MSG"
    return 0
  fi
  if [ "$PL_CODE" = cancelled ]; then
    op_finish cancelled "$PL_CODE" "$PL_MSG"
    return 2
  fi
  op_finish error "$PL_CODE" "$PL_MSG"
  return 1
}

worker_exit() {
  pl_cleanup
  op_running && op_interrupt '⚠️ The task was stopped before it finished. Your hosts file is intact.'
  lock_drop_if_mine "$LOCKD"
}

worker_main() {
  MODE=worker
  echo "$$" > "$LOCKD/pid" 2>/dev/null
  op_load
  spawned
  trap 'worker_exit' EXIT
  trap 'exit 143' TERM INT HUP
  run_job "$1" "$2" "$3"
}

wait_boot() {
  _wb=0
  while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ] && [ "$_wb" -lt 300 ]; do
    sleep 5
    _wb=$((_wb + 5))
  done
}

setup_main() {
  MODE=worker
  spawned
  wait_boot
  _su_try=1
  while :; do
    cfg_load
    [ "$C_SETUP" = pending ] || return 0
    if lock_take "$LOCKD"; then
      trap 'worker_exit' EXIT
      trap 'exit 143' TERM INT HUP
      op_begin setup "$C_LIST"
      run_job setup "$C_LIST" "$C_ADDONS"
      _su_rc=$?
      lock_drop "$LOCKD"
      trap - EXIT
      [ "$_su_rc" = 1 ] || return 0
    fi
    if [ "$_su_try" -ge 5 ]; then
      cfg_load
      if [ "$C_SETUP" = pending ]; then
        C_SETUP=failed
        cfg_save
        set_description
        log ERROR "首次下载在 5 次尝试后失败，请打开 WebUI 重试"
      fi
      return 0
    fi
    log WARN "首次下载第 $_su_try 次尝试失败，稍后重试"
    sleep $((30 * _su_try))
    _su_try=$((_su_try + 1))
  done
}

sched_due() {
  cfg_load
  [ "$C_AUTO" -gt 0 ] || return 1
  [ "$C_ENABLED" = 1 ] && [ "$C_SETUP" = ready ] || return 1
  _sd_now=$(now)
  _sd_last=$C_CHECKED
  [ "$C_UPDATED" -gt "$_sd_last" ] && _sd_last=$C_UPDATED
  [ "$_sd_now" -ge $((_sd_last + C_AUTO * 86400)) ] || return 1
  _sd_r=0
  [ -f "$SCHEDRETRY" ] && read -r _sd_r < "$SCHEDRETRY"
  is_num "$_sd_r" || _sd_r=0
  [ "$_sd_now" -ge "$_sd_r" ]
}

sched_exit() {
  [ -n "${_sm_s:-}" ] && kill "$_sm_s" 2>/dev/null
  if op_running; then
    op_interrupt '⚠️ The auto-update task was interrupted. Your hosts file is intact — run it again if needed.'
    pl_cleanup
  fi
  lock_drop_if_mine "$LOCKD"
  [ "$(cat "$SCHEDPID" 2>/dev/null)" = "$$" ] && rm -f "$SCHEDPID"
  log INFO "自动更新调度器已停止"
  exit 0
}

sched_main() {
  MODE=worker
  _sm_tick=$1
  is_num "$_sm_tick" && [ "$_sm_tick" -gt 0 ] || _sm_tick=$SCHED_TICK
  echo "$$" > "$SCHEDPID"
  spawned
  _sm_s=
  trap 'sched_exit' TERM INT HUP
  log INFO "自动更新调度器已启动"
  wait_boot
  while :; do
    _sm_p=
    [ -f "$SCHEDPID" ] && read -r _sm_p < "$SCHEDPID"
    [ "$_sm_p" = "$$" ] || break
    cfg_load
    [ "$C_AUTO" -gt 0 ] || break
    if sched_due && lock_take "$LOCKD"; then
      log INFO "自动更新：正在检查新的列表版本"
      op_begin auto "$C_LIST"
      if run_job auto "$C_LIST" "$C_ADDONS"; then
        rm -f "$SCHEDRETRY"
      else
        echo $(($(now) + 3600)) > "$SCHEDRETRY"
        log WARN "自动更新未完成，约一小时后重试"
      fi
      pl_cleanup
      lock_drop "$LOCKD"
    fi
    sleep "$_sm_tick" &
    _sm_s=$!
    wait "$_sm_s"
    _sm_s=
  done
  [ "$(cat "$SCHEDPID" 2>/dev/null)" = "$$" ] && rm -f "$SCHEDPID"
  log INFO "自动更新调度器已停止"
}

boot_main() {
  MODE=boot
  ensure_dirs
  op_running && op_interrupt '⚠️ A task was interrupted by a reboot. Your hosts file is intact — run it again if needed.'
  rm -rf "$LOCKD" "$METALOCK" "$RUND/www" 2>/dev/null
  rm -f "$RUND"/spawn.* "$RUND/cancel" "$RUND/dl.pid" "$RUND/token" "$RUND/httpd.pid" "$RUND/watchdog.pid" "$RUND/last_request" "$RUND"/last_request.* "$RUND/httpd.conf" "$RUND/manager" "$RUND/device" "$SCHEDPID" "$SCHEDRETRY" "$PENDF" 2>/dev/null
  rm -f "$METAD"/*.busy "$METAD"/*.tmp "$HOSTSD"/.hosts.hk* "$RULESD"/*.undo "$RULESD"/*.tmp 2>/dev/null
  rm -rf "$TMPD" 2>/dev/null
  mkdir -p "$TMPD"
  migrate_data
  cfg_load
  if [ ! -f "$CFG" ]; then
    C_SETUP=pending
    cfg_save
    log WARN "设置缺失，将重新下载默认列表"
  elif [ "$C_SETUP" = failed ]; then
    C_SETUP=pending
    cfg_save
  elif [ "$C_SETUP" = ready ] && ! sources_ready; then
    C_SETUP=pending
    cfg_save
    log WARN "缓存列表缺失，将重新下载"
  fi
  repair_hosts deep
  ensure_mounted
  set_description
  cfg_load
  if [ "$C_SETUP" = pending ]; then
    log INFO "开机：等待网络以下载 $L_NAME"
    spawn "$RUND/setup.out" _setup || log ERROR "无法启动首次开机下载"
  elif [ "$C_ENABLED" = 1 ]; then
    applied_state
    log INFO "开机：$L_NAME 已生效，共 $(fmt_num "$C_DOMAINS") 个域名（$R_APPLIED）"
  else
    log INFO "开机：拦截处于关闭状态"
  fi
  if [ "$C_AUTO" -gt 0 ]; then
    spawn "$RUND/sched.out" _sched || log ERROR "无法启动自动更新调度器"
  fi
}

mount_main() {
  MODE=boot
  ensure_dirs
  repair_hosts deep
  ensure_mounted
  return 0
}

restore_original_for_uninstall() {
  [ -f "$ORIGHOSTS" ] || return 1
  umount "$MOUNT_TARGET" 2>/dev/null || true
  if cmp -s "$ORIGHOSTS" "$MOUNT_TARGET" 2>/dev/null; then
    return 0
  fi
  _ru_tmp="$MOUNT_TARGET.hkun.$$"
  rm -f "$_ru_tmp"
  if cp -f "$ORIGHOSTS" "$_ru_tmp" 2>/dev/null && cmp -s "$ORIGHOSTS" "$_ru_tmp" && set_hosts_perm "$_ru_tmp" && mv -f "$_ru_tmp" "$MOUNT_TARGET"; then
    return 0
  fi
  rm -f "$_ru_tmp" 2>/dev/null
  return 1
}

uninstall_main() {
  server_stop
  sched_stop
  for _un in "$LOCKD" "$METALOCK"; do
    _un_p=$(lock_pid "$_un")
    pid_alive "$_un_p" && kill_tree "$_un_p"
  done
  if ! restore_original_for_uninstall; then
    log ERROR "卸载时无法恢复原始 /system/etc/hosts，已保留模块数据以便恢复"
    return 1
  fi
  rm -rf "$DATA"
  return 0
}

install_main() {
  MODE=install
  _in_fail=0
  ensure_dirs
  rm -rf "$LOCKD" "$METALOCK" "$STAGED" 2>/dev/null
  rm -f "$RUND"/spawn.* "$RUND/manager" "$METAD"/*.busy 2>/dev/null
  detect_manager
  printf '🔎 正在检查环境…\n'
  if [ -n "$MGR_VER" ]; then
    printf '✅ Root 管理器：%s（%s）\n' "$MGR_NAME" "$MGR_VER"
  else
    printf '✅ Root 管理器：%s\n' "$MGR_NAME"
  fi
  if [ "$HK_BB" != none ]; then
    printf '✅ BusyBox：%s\n' "$HK_BB"
  else
    printf '⚠️ 未找到 BusyBox，回退到系统工具\n'
  fi
  if dl_detect; then
    if [ "$DL_TOOL" = curl ]; then
      if [ "$DL_GZ" = 1 ]; then printf '✅ 下载工具：curl（启用压缩传输）\n'; else printf '✅ 下载工具：curl\n'; fi
    else
      printf '✅ 下载工具：BusyBox wget\n'
    fi
  else
    printf '❌ 未找到下载工具（curl 或 BusyBox wget）\n'
  fi
  if ! httpd_available; then
    printf '%s\n' "⚠️ 未找到 BusyBox httpd，Action 按钮无法在浏览器中打开 WebUI"
  fi
  log INFO "正在安装 HostKeeper $HK_VER，管理器为 $MGR_NAME $MGR_VER"

  printf '\n🧩 正在检查其他 hosts 拦截模块…\n'
  _in_cf=0
  conflicts_scan
  for _in_m in $R_CONF; do
    _in_cf=1
    if [ "$_in_m" = hosts ]; then
      printf '%s\n' "⚠️ 系统 hosts 模块（Systemless hosts）已启用，请在 root 管理器中关闭它。"
    else
      printf '⚠️ 模块“%s”也会替换 /system/etc/hosts，请停用它以避免冲突。\n' "$_in_m"
    fi
    log WARN "发现冲突的 hosts 模块：$_in_m"
  done
  if [ -d /data/data/org.adaway ]; then
    _in_cf=1
    printf '%s\n' "⚠️ 检测到 AdAway，请不要同时启用它的 root 或 systemless 模式，以免与 HostKeeper 冲突。"
    log WARN "检测到 AdAway 应用"
  fi
  [ "$_in_cf" = 0 ] && printf '✅ 未发现冲突的 hosts 拦截模块\n'

  printf '\n🧹 正在清理旧版本…\n'
  _in_old=
  _in_legacy=0
  if [ -f "$DATA/config.txt" ]; then
    _in_legacy=$(sed -n 's/^ACTIVE_LIST=//p' "$DATA/config.txt" 2>/dev/null | head -n 1)
    is_num "$_in_legacy" || _in_legacy=0
  fi
  for _in_f in config.txt hosts.bak hosts.tmp hosts.tmp.clean hosts.tmp.clean.sort; do
    if [ -e "$DATA/$_in_f" ]; then
      rm -f "$DATA/$_in_f"
      _in_old="$_in_old $_in_f"
    fi
  done
  _in_v1=0
  [ -f "$OLDCACHE" ] && _in_v1=1
  migrate_data keep
  rm -f "$BACKUPD/hosts.1" "$BACKUPD/hosts.2" "$BACKUPD/hosts.3" 2>/dev/null
  if [ -n "$_in_old" ]; then
    printf '✅ 已移除旧版 HostKeeper 文件：%s\n' "$_in_old"
    log INFO "已移除旧版文件：$_in_old"
  fi
  if [ "$_in_v1" = 1 ]; then
    printf '✅ 已将缓存列表迁移到当前布局\n'
  fi
  [ -z "$_in_old" ] && [ "$_in_v1" = 0 ] && printf '✅ 没有需要清理的内容\n'
  if [ "$_in_legacy" -gt 1 ] 2>/dev/null; then
    printf 'ℹ️ 之前的列表已不可用，HostKeeper 将使用 StevenBlack Main 启动\n'
  fi

  printf '\n💾 正在备份原始 hosts 文件…\n'
  if [ -s "$ORIGHOSTS" ]; then
    printf '✅ 原始 hosts 文件的副本已保存\n'
  elif [ -f "$SYS_HOSTS" ] && [ "$(wc -l < "$SYS_HOSTS")" -le 30 ] && ! grep -q '^0\.0\.0\.0 ' "$SYS_HOSTS" 2>/dev/null; then
    cp -f "$SYS_HOSTS" "$ORIGHOSTS" && printf '✅ 已保存原始 hosts 文件的副本\n'
  else
    printf '127.0.0.1 localhost\n::1 ip6-localhost\n' > "$ORIGHOSTS"
    printf '%s\n' "ℹ️ 当前 hosts 文件来自其他拦截模块，因此已改为保存 Android 默认 hosts"
  fi

  printf '\n📋 正在准备拦截列表…\n'
  cfg_load
  _in_keep=0
  if [ -f "$CFG" ] && [ "$C_SETUP" = ready ] && sources_ready; then
    _in_name=$L_NAME
    rm -f "$HOSTSD/.hosts.hknew"
    if compile_into "$HOSTSD/.hosts.hknew" "$C_ENABLED"; then
      if mv -f "$HOSTSD/.hosts.hknew" "$HOSTS" && set_hosts_perm "$HOSTS" && verify_hosts "$CH_COUNT"; then
        _in_keep=1
        [ "$C_ENABLED" = 1 ] && C_DOMAINS=$CH_COUNT
        cfg_save
        [ "$C_ENABLED" = 1 ] && stats_commit
        if [ "$C_ENABLED" = 1 ]; then
          printf '♻️ 保留当前设置：%s • %s 个域名\n' "$_in_name" "$(fmt_num "$CH_COUNT")"
        else
          printf '♻️ 保留当前设置：%s（拦截已关闭）\n' "$_in_name"
        fi
        set -- $C_ADDONS
        [ "$#" -gt 0 ] && printf '✅ 已保留 %s 个附加列表\n' "$#"
        count_lines "$ALLOWF"; _in_r=$R_LINES
        count_lines "$BLOCKF"; _in_r=$((_in_r + R_LINES))
        [ "$_in_r" -gt 0 ] && printf '✅ 已保留 %s 条域名规则\n' "$_in_r"
        log INFO "已保留现有设置：$_in_name"
      fi
    fi
    rm -f "$HOSTSD/.hosts.hknew" "$TMPD/compile.stats"
  fi
  if [ "$_in_keep" = 0 ]; then
    cfg_load
    _in_enabled=$C_ENABLED
    C_SETUP=pending
    cfg_save
    _in_name=$L_NAME
    if [ "${BOOTMODE:-true}" != false ] && pipeline setup "$C_LIST" "$C_ADDONS"; then
      if [ "$_in_enabled" = 1 ]; then
        printf '✅ hosts 文件已就绪：重启后将拦截 %s 个域名\n' "$(fmt_num "$PL_DOMAINS")"
      else
        printf '✅ 拦截列表源已就绪，拦截仍保持关闭\n'
      fi
    else
      if [ "${BOOTMODE:-true}" = false ]; then
        printf '⚠️ 从 Recovery 安装：没有网络，列表将在重启后下载\n'
        log WARN "从 Recovery 安装，首次下载已推迟"
      else
        printf '⚠️ %s\n' "${PL_MSG#* }"
      fi
      if write_clean_hosts; then
        cfg_load
        C_SETUP=pending
        cfg_save
        printf '🧩 已暂时写入仅含 localhost 的干净 hosts 文件\n'
        printf '%s\n' "🔁 联网后，HostKeeper 将在重启后自动重试"
        log WARN "安装期间首次下载失败，将在重启后重试"
      else
        _in_fail=1
        printf '❌ 无法写入干净的 hosts 文件。\n'
        log ERROR "安装时无法写入干净的 hosts 文件"
      fi
    fi
  fi
  set_hosts_perm "$HOSTS"
  mark_pending
  if [ "$_in_fail" = 0 ] && ! hosts_sane "$HOSTS"; then
    _in_fail=1
    log ERROR "安装结束时没有可用的 hosts 文件"
  fi
  if [ "$_in_fail" != 0 ]; then
    printf '\n❌ HostKeeper 安装失败。在可能的情况下已保留之前的 hosts 文件。\n'
    log ERROR "HostKeeper 安装失败，初始化未完成"
    return 1
  fi
  set_description

  printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf '🎉 HostKeeper %s 已安装！\n' "$HK_VER"
  printf '🔁 请重启设备以启用。\n'
  printf '⚡ 功能：即时生效、附加列表、自动更新等。\n'
  case $MGR_NAME in
    KernelSU* | SukiSU*)
      printf '🔗 如果安装了 metamodule（例如 meta-overlayfs），模块的 system 目录会被挂载；如果没有，HostKeeper 会尝试直接 bind，并在诊断中报告挂载状态。\n'
      printf '🖥️ 重启后，点击 HostKeeper 卡片上的 WebUI 按钮。\n'
      printf '▶️ Action 按钮会在浏览器中打开同一 WebUI。\n'
      ;;
    APatch)
      printf '🔗 APatch 通过其 OverlayFS 应用模块；HostKeeper 会在每次开机时检查挂载。\n'
      printf '🖥️ 重启后，点击 HostKeeper 卡片上的 WebUI 按钮。\n'
      printf '▶️ Action 按钮会在浏览器中打开同一 WebUI。\n'
      ;;
    *)
      printf '▶️ 重启后，点击 HostKeeper 卡片上的 Action 按钮——\n'
      printf '   WebUI 会在浏览器中打开。\n'
      printf '💡 也可以使用 KsuWebUI、MMRL 或 WebUI X 打开 WebUI。\n'
      ;;
  esac
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  return 0
}

[ -d "$TMPD" ] && [ -d "$LISTSD" ] || ensure_dirs

case ${1:-} in
  cgi) cgi_main ;;
  _worker) worker_main "${2:-}" "${3:-}" "${4:-}" ;;
  _meta) shift; meta_worker_main "$@" ;;
  _setup) setup_main ;;
  _sched) sched_main "${2:-}" ;;
  _serve) serve_main ;;
  _action) action_main ;;
  _install) install_main ;;
  _boot) boot_main ;;
  _mount) mount_main ;;
  _uninstall) uninstall_main ;;
  *) dispatch "$@" ;;
esac
HK_RC=$?
exit "$HK_RC"
