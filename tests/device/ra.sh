#!/bin/sh
# On-device (or host) test of the RetroAchievements sync in launch.sh.
#
# It runs the *real* launch.sh inside a throw-away SD card tree with a stub
# standing in for PPSSPP. A NextUI-style minuisettings.txt is put in $SHARED_USERDATA_PATH,
# and the stub records what PPSSPP would see at start-up: the [Achievements] section of
# ppsspp.ini, the token file PPSSPP reads (SYSTEM/ppsspp_retroachievements.dat) and the
# inodes of both (to prove nothing is rewritten needlessly).
# Nothing under the real SD card is touched; the sandbox is deleted afterwards.
#
# Usage (on the device, over ssh):
#   scp -r tests root@device:/mnt/SDCARD/Emus/tg5040/PSP.pak/
#   ssh root@device 'sh /mnt/SDCARD/Emus/tg5040/PSP.pak/tests/device/ra.sh'
# Output: PASS/FAIL per test, exit code 0 only if all pass. Logs are kept in $OUT_DIR.
#
# Env overrides:
#   SRC_PAK       pak to test (default: two directories above this script)
#   PLATFORM      tg5040 (default) or tg5050
#   OUT_DIR       where to keep logs (and the sandbox on failure) (default /tmp/psp-ra-test-out)
#   TMP_ROOT      where the sandbox is made (default /tmp; e.g. /mnt/SDCARD to test on FAT)
#   LAUNCH_SHELL  shell that runs launch.sh (default sh; e.g. "busybox sh", bash)
#   KEEP=1        keep the sandbox

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_PAK="${SRC_PAK:-$(cd "$HERE/../.." && pwd)}"
PLATFORM="${PLATFORM:-tg5040}"
OUT_DIR="${OUT_DIR:-/tmp/psp-ra-test-out}"
LAUNCH_SHELL="${LAUNCH_SHELL:-sh}"
T="$(mktemp -d "${TMP_ROOT:-/tmp}/psp-ra-test.XXXXXX")" || exit 2

SD="$T/sd"
PAK="$SD/Emus/$PLATFORM/PSP.pak"
USERDATA="$SD/.userdata/$PLATFORM"
SHARED="$SD/.userdata/shared"
LOGS="$USERDATA/logs"
ROMDIR="$SD/Roms/PlayStation Portable (PSP)"
FLAGS="$USERDATA/PSP-ppsspp"
STUB="$T/stub"
SYSDIR="$PAK/PPSSPP/.config/ppsspp/PSP/SYSTEM"
INI="$SYSDIR/ppsspp.ini"
TOKEN="$SYSDIR/ppsspp_retroachievements.dat"
SETTINGS="$SHARED/minuisettings.txt"

# Secrets: they must reach the token file and nothing else (no log, no ini).
# Random per run, so no credential-like literal is committed.
RA_TOKEN="t$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
RA_PASSWORD="p$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"

missing=""
for tool in mktemp cp mv rm mkdir cmp grep head tr sed cat awk ls wc find touch chmod cut; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    echo "ra.sh: missing tools on this system:$missing" >&2
    rm -rf "$T"
    exit 2
fi

PASS=0
FAIL=0
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

finish() {
    if [ -n "$KEEP" ] || [ "$FAIL" -gt 0 ]; then
        cp -R "$STUB" "$OUT_DIR/stub" 2>/dev/null
        cp "$INI" "$OUT_DIR/ppsspp.ini" 2>/dev/null
        echo "Logs and files kept in $OUT_DIR"
    fi
    [ -n "$KEEP" ] || rm -rf "$T"
}
trap finish EXIT

check() { # check <description> <command...>
    desc="$1"
    shift
    if "$@"; then
        printf '  ok   %s\n' "$desc"
    else
        printf '  FAIL %s\n' "$desc"
        CASE_FAIL=1
    fi
}

begin() {
    CASE="$1"
    CASE_FAIL=0
    printf '[%s]\n' "$CASE"
}

end() {
    if [ "$CASE_FAIL" = 0 ]; then
        PASS=$((PASS + 1))
        printf 'PASS %s\n' "$CASE"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n' "$CASE"
    fi
}

contains() { grep -q -- "$2" "$1"; }
lacks() { ! grep -q -- "$2" "$1"; }
same() { cmp -s "$1" "$2"; }
CR="$(printf '\r')"

# Section-aware ini filter, written to $SECTION_AWK below. Headers are read the way
# scripts/set_ini_values.awk reads them (CR, a BOM before the first header, blanks
# around the brackets), so no check depends on where a section or a key is in the file.
#   mode=in    print the lines of section s, header included (CR kept)
#   mode=out   print every other line
#   mode=host  replace the AchievementsHost lines of section s by one "AchievementsHost = h",
#              right after the header
section_program() {
    cat <<'AWK'
{
    l = $0
    sub(/\r$/, "", l)
    if (NR == 1 && index(l, "[") > 1 && index(l, "[") <= 4)
        l = substr(l, index(l, "["))
}
l ~ /^[ \t]*\[.*\][ \t]*$/ {
    name = l
    gsub(/^[ \t]*\[|\][ \t]*$/, "", name)
    on = (name == s)
    if (mode == "host") {
        print
        if (on)
            print "AchievementsHost = " h
        next
    }
}
mode == "in" && on
mode == "out" && !on
mode == "host" && !(on && l ~ /^[ \t]*AchievementsHost[ \t]*=/)
AWK
}
# section <in|out> <name> <file>
section() { awk -v mode="$1" -v s="$2" -f "$SECTION_AWK" "$3"; }
# Prints the [Achievements] section of ini $1 (CR kept, so CRLF can be checked).
ach_section() { section in Achievements "$1"; }

# --- sandbox -------------------------------------------------------------------------
mkdir -p "$PAK/bin" "$SYSDIR" "$LOGS" "$ROMDIR" "$FLAGS" "$SHARED" "$STUB"
cp "$SRC_PAK/launch.sh" "$SRC_PAK/pak.json" "$PAK/"
cp -R "$SRC_PAK/scripts" "$PAK/"
cp "$SRC_PAK/PPSSPP/.config/ppsspp/PSP/SYSTEM/ppsspp.ini" "$T/shipped.ini"
SECTION_AWK="$T/section.awk"
section_program >"$SECTION_AWK"
for b in minui-power-control setalpha show_message; do
    printf '#!/bin/sh\nexit 0\n' >"$PAK/bin/$b"
done

# Fake PPSSPP: records what the real one would read at start-up, then exits.
cat >"$PAK/PPSSPP/PPSSPPSDL_$PLATFORM" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$STUB/args"
awk -v mode=in -v s=Achievements -f "$SECTION_AWK" "$INI" >"$STUB/ach.ini"
ls -i "$INI" | awk '{ print $1 }' >"$STUB/ini.inode"
rm -f "$STUB/token"
if [ -f "$TOKEN" ]; then
    cp "$TOKEN" "$STUB/token"
    ls -i "$TOKEN" | awk '{ print $1 }' >"$STUB/token.inode"
    ls -l "$TOKEN" | cut -c1-10 >"$STUB/token.mode"
else
    echo none >"$STUB/token.inode"
fi
EOF
chmod +x "$PAK/PPSSPP/PPSSPPSDL_$PLATFORM" "$PAK/bin/"*
printf 'g' >"$ROMDIR/Game.iso"

export PLATFORM DEVICE=brick SDCARD_PATH="$SD" USERDATA_PATH="$USERDATA" LOGS_PATH="$LOGS" \
    SHARED_USERDATA_PATH="$SHARED" ROMS_PATH="$SD/Roms" STUB INI TOKEN SECTION_AWK

# Does this filesystem keep Unix permissions? (FAT does not.)
touch "$T/perm" && chmod 600 "$T/perm"
PERMS_WORK=0
# shellcheck disable=SC2012 # BusyBox has no stat -c; the file name is our own
[ "$(ls -l "$T/perm" | cut -c1-10)" = "-rw-------" ] && PERMS_WORK=1

# fresh: shipped ini, no token, no flags, no settings.
fresh() {
    cp "$T/shipped.ini" "$INI"
    rm -f "$TOKEN" "$SETTINGS" "$FLAGS/no-ra-sync" "$FLAGS/no-config-changes" \
        "$FLAGS/debug"
}

# settings [key=value ...]: a NextUI-style minuisettings.txt (as NextUI's CFG_sync writes
# it), logged in with hardcore off; arguments override or add lines (later lines win,
# like NextUI's parser). "-raEnable" drops that key.
settings() {
    {
        echo "font=1"
        echo "radius=20"
        echo "raEnable=1"
        echo "raUsername=Player1"
        echo "raPassword=$RA_PASSWORD"
        echo "raHardcoreMode=0"
        echo "raToken=$RA_TOKEN"
        echo "raServerUsername=Player1"
        echo "raAuthenticated=1"
        echo "raShowNotifications=1"
        for kv in "$@"; do
            case "$kv" in -*) ;; *) printf '%s\n' "$kv" ;; esac
        done
    } >"$SETTINGS.new"
    for kv in "$@"; do
        case "$kv" in -*) grep -v "^${kv#-}=" "$SETTINGS.new" >"$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS.new" ;; esac
    done
    mv "$SETTINGS.new" "$SETTINGS"
}

# run_game: runs launch.sh to completion and keeps its log as $OUT_DIR/<case>[.n].log.
RUN_N=0
run_game() {
    rm -f "$STUB/args" "$STUB/ach.ini" "$STUB/token" "$STUB/ini.inode" "$STUB/token.inode" "$STUB/token.mode"
    RUN_N=$((RUN_N + 1))
    $LAUNCH_SHELL "$PAK/launch.sh" "$ROMDIR/Game.iso" >"$T/launch.out" 2>&1
    LOG="$OUT_DIR/$(echo "$CASE" | cut -d' ' -f1).$RUN_N.log"
    cat "$LOGS/PSP.txt" "$T/launch.out" >"$LOG" 2>/dev/null
}

# ach KEY: value of KEY in the [Achievements] section PPSSPP saw; fails if KEY is absent.
ach() {
    awk -v k="$1" '{ sub(/\r$/, "") }
        index($0, k " = ") == 1 { print substr($0, length(k) + 4); f = 1 }
        END { exit !f }' "$STUB/ach.ini"
}
ach_is() { v="$(ach "$1")" && [ "$v" = "$2" ]; }
# AchievementsHost lines in the [Achievements] section of the shipped ini and of what
# PPSSPP saw must be identical (both absent, or the same lines).
host_unchanged() {
    [ "$(ach_section "$T/shipped.ini" | grep '^[ 	]*AchievementsHost[ 	]*=')" = \
        "$(grep '^[ 	]*AchievementsHost[ 	]*=' "$STUB/ach.ini")" ]
}
# Sets AchievementsHost in [Achievements] of ppsspp.ini, as if set by hand in PPSSPP:
# whatever AchievementsHost lines the section has, wherever they are, become one.
set_host_by_hand() {
    awk -v mode=host -v s=Achievements -v h="$1" -f "$SECTION_AWK" "$INI" >"$INI.x" &&
        mv "$INI.x" "$INI"
}
ach_count() { [ "$(grep -c "^$1 = " "$STUB/ach.ini")" = "$2" ]; }
token_is() { [ -f "$STUB/token" ] && printf '%s' "$1" | cmp -s - "$STUB/token"; }
token_absent() { [ ! -f "$STUB/token" ] && [ ! -f "$TOKEN" ]; }
launched() { [ -f "$STUB/args" ]; }
no_tmp_left() { [ -z "$(find "$SYSDIR" -name '*.tmp*')" ]; }
no_secrets() { # no_secrets <file>
    lacks "$1" "$RA_TOKEN" && lacks "$1" "$RA_PASSWORD"
}

check_enabled() { # check_enabled <user> <hardcore True|False>
    check "PPSSPP was launched" launched
    check "AchievementsEnable = True" ach_is AchievementsEnable True
    check "AchievementsUserName = $1" ach_is AchievementsUserName "$1"
    check "AchievementsChallengeMode = $2" ach_is AchievementsChallengeMode "$2"
    check "token file holds exactly the NextUI token" token_is "$RA_TOKEN"
    check "token and password not in log" no_secrets "$LOG"
    check "token not in ppsspp.ini" lacks "$INI" "$RA_TOKEN"
    check "no temp files left" no_tmp_left
}

check_disabled() {
    check "PPSSPP was launched" launched
    check "AchievementsEnable = False" ach_is AchievementsEnable False
    check "AchievementsUserName cleared" ach_is AchievementsUserName ""
    check "token file removed" token_absent
    check "token and password not in log" no_secrets "$LOG"
}

# A PPSSPP that was set up by hand inside PPSSPP (MinUI users, no-ra-sync users).
manual_ppsspp_login() {
    awk '{ sub(/^AchievementsEnable = .*/, "AchievementsEnable = True")
           sub(/^AchievementsUserName = .*/, "AchievementsUserName = HandUser") } 1' \
        "$T/shipped.ini" >"$INI"
    printf 'handTok' >"$TOKEN"
    ach_section "$INI" >"$T/before.ach"
}

check_untouched() {
    check "PPSSPP was launched" launched
    check "[Achievements] section unchanged" same "$STUB/ach.ini" "$T/before.ach"
    check "hand-made token kept" token_is handTok
}

# --- tests ---------------------------------------------------------------------------
begin "1 enabled, softcore"
fresh
settings
run_game
check_enabled Player1 False
check "log says enabling" contains "$LOG" "RetroAchievements: enabling for user 'Player1' (hardcore: False)"
if [ "$PERMS_WORK" = 1 ]; then
    check "token file is private (-rw-------)" [ "$(cat "$STUB/token.mode")" = "-rw-------" ]
fi
end

begin "2 enabled, hardcore"
fresh
settings raHardcoreMode=1
run_game
check_enabled Player1 True
end

begin "3 disabled in NextUI -> off, logged out"
fresh
settings
run_game
settings raEnable=0
run_game
check_disabled
check "log says disabled" contains "$LOG" "RetroAchievements: disabled in NextUI"
end

begin "4 enabled but not logged in -> off, logged out"
fresh
settings
run_game
settings raAuthenticated=0
run_game
check_disabled
check "log says not logged in" contains "$LOG" "enabled in NextUI but not logged in"
settings raToken=
run_game
check "empty token also counts as logged out" token_absent
settings raUsername=
run_game
check "empty username also counts as logged out" ach_is AchievementsEnable False
end

begin "5 no minuisettings.txt (MinUI) -> PPSSPP untouched"
fresh
manual_ppsspp_login
run_game
check_untouched
check "log says no settings" contains "$LOG" "no NextUI settings found"
end

begin "6 no raEnable key (older NextUI) -> PPSSPP untouched"
fresh
manual_ppsspp_login
settings -raEnable
run_game
check_untouched
check "log says not configured" contains "$LOG" "not configured in NextUI"
end

begin "7 no-ra-sync flag -> PPSSPP untouched"
fresh
manual_ppsspp_login
settings raEnable=0
touch "$FLAGS/no-ra-sync"
run_game
check_untouched
check "log says sync disabled" contains "$LOG" "sync disabled via no-ra-sync"
end

begin "8 no-config-changes flag -> PPSSPP untouched"
fresh
manual_ppsspp_login
settings raEnable=0
touch "$FLAGS/no-config-changes"
cp "$INI" "$T/before.ini"
run_game
check_untouched
check "ini byte for byte unchanged (graphics too)" same "$INI" "$T/before.ini"
check "log says config changes disabled" contains "$LOG" "RetroAchievements: Config changes disabled"
end

begin "9 username with special characters / & | \\1"
fresh
settings 'raUsername=a/b&c|d\1e'
run_game
check_enabled 'a/b&c|d\1e' False
end

begin "10 older ini without the keys / without the section"
fresh
grep -v -e '^AchievementsEnable = ' -e '^AchievementsUserName = ' -e '^AchievementsChallengeMode = ' \
    "$T/shipped.ini" >"$INI"
settings raHardcoreMode=1
run_game
check_enabled Player1 True
check "AchievementsEnableRAIntegration untouched" ach_is AchievementsEnableRAIntegration False
check "AchievementsEnable added once" ach_count AchievementsEnable 1
section out Achievements "$T/shipped.ini" >"$INI"
run_game
check_enabled Player1 True
ach_headers_once() { [ "$(ach_section "$INI" | grep -c 'Achievements\]')" = 1 ]; }
check "section added once" ach_headers_once
graphics_kept() { section in Graphics "$INI" | grep -q '^DisplayAspectRatio = '; }
check "[Graphics] still there" graphics_kept
end

begin "11 CRLF ini keeps CRLF"
fresh
sed "s/\$/$CR/" "$T/shipped.ini" >"$INI"
grep -v '^AchievementsUserName = ' "$INI" >"$INI.x" && mv "$INI.x" "$INI"
settings
run_game
check_enabled Player1 False
check "every line still ends in CR" [ "$(grep -c "$CR\$" "$INI")" = "$(wc -l <"$INI" | tr -d ' ')" ]
check "no bare LF line added" lacks "$INI" "^AchievementsUserName = Player1\$"
end

begin "12 token file with a trailing newline is normalised"
fresh
settings
printf '%s\n' "$RA_TOKEN" >"$TOKEN"
run_game
check "token file is the token without newline" token_is "$RA_TOKEN"
check "log says token updated" contains "$LOG" "login token updated"
check "token and password not in log" no_secrets "$LOG"
end

begin "13 AchievementsHost is never touched"
fresh
settings
run_game
check_enabled Player1 False
# The shipped ini may or may not have the key (PPSSPP writes "AchievementsHost =" once it
# has saved the ini, e.g. in a pak installed on a device): it must be as it was.
check "AchievementsHost as in the shipped ini" host_unchanged
set_host_by_hand "http://hand.example"
run_game
check "one AchievementsHost line" ach_count AchievementsHost 1
check "host set by hand in PPSSPP has its value" ach_is AchievementsHost "http://hand.example"
settings raEnable=0
run_game
check "kept when disabling too" ach_is AchievementsHost "http://hand.example"
end

begin "14 second launch changes nothing (same inodes, same content)"
fresh
settings raHardcoreMode=1
run_game
cp "$STUB/ach.ini" "$T/run1.ach"
cp "$INI" "$T/run1.ini"
ini1="$(cat "$STUB/ini.inode")"
tok1="$(cat "$STUB/token.inode")"
run_game
check_enabled Player1 True
check "ini inode unchanged" [ "$(cat "$STUB/ini.inode")" = "$ini1" ]
check "token inode unchanged" [ "$(cat "$STUB/token.inode")" = "$tok1" ]
check "ini content unchanged" same "$INI" "$T/run1.ini"
check "log does not say token updated" lacks "$LOG" "login token updated"
end

begin "15 secrets never in the log, also with the debug flag (set -x)"
fresh
touch "$FLAGS/debug"
settings raHardcoreMode=1
run_game
check "debug tracing is on" contains "$LOG" '^+ '
check_enabled Player1 True
printf '%s\n' "$RA_TOKEN" >"$TOKEN"
run_game
check "token rewrite traced without secrets" no_secrets "$LOG"
settings raEnable=0
run_game
check_disabled
check "tracing resumes after the sync" contains "$LOG" '^+ .*mount'
end

begin "16 failed ini write (full SD card) leaves ppsspp.ini as it was"
fresh
settings raHardcoreMode=1
cp "$INI" "$T/before.ini"
# launch.sh puts the pak's bin/ first in PATH: this awk truncates its output when it is
# rewriting ppsspp.ini (the argument ending in ppsspp.ini.tmp.<pid>), and then
# says it failed (FAIL_MODE=exit) or claims success (FAIL_MODE=lie).
REAL_AWK="$(command -v awk)"
for mode in exit lie; do
    cat >"$PAK/bin/awk" <<EOF
#!/bin/sh
for arg in "\$@"; do
    case "\$arg" in
    */ppsspp.ini.tmp.*)
        "$REAL_AWK" "\$@" >/dev/null
        head -n 3 "\$arg" >"\$arg.cut" && mv "\$arg.cut" "\$arg"
        [ "$mode" = exit ] && exit 1
        echo 999
        exit 0
        ;;
    esac
done
exec "$REAL_AWK" "\$@"
EOF
    chmod +x "$PAK/bin/awk"
    run_game
    check "($mode) ini unchanged" same "$INI" "$T/before.ini"
    check "($mode) error logged" contains "$LOG" "could not write"
    check "($mode) no temp files left" no_tmp_left
    check "($mode) PPSSPP still launched" launched
done
rm -f "$PAK/bin/awk"
end

begin "17 settings parsing: CRLF, last key wins, raAuthenticated missing or not 1"
fresh
settings raHardcoreMode=1 # the base file says 0 earlier: the later line must win
sed "s/\$/$CR/" "$SETTINGS" >"$SETTINGS.crlf" && mv "$SETTINGS.crlf" "$SETTINGS"
run_game
check_enabled Player1 True
settings -raAuthenticated
run_game
check "missing raAuthenticated -> off" ach_is AchievementsEnable False
check "missing raAuthenticated -> token removed" token_absent
settings raAuthenticated=yes
run_game
check "raAuthenticated=yes -> off" ach_is AchievementsEnable False
end

begin "18 only managed lines change; BOM kept; missing graphics key added"
fresh
settings raHardcoreMode=1
run_game
check_enabled Player1 True
managed='^(AchievementsEnable|AchievementsUserName|AchievementsChallengeMode|DisplayAspectRatio|GraphicsBackend) = '
grep -v -E "$managed" "$T/shipped.ini" >"$T/a.rest"
grep -v -E "$managed" "$INI" >"$T/b.rest"
check "all other lines byte for byte the same" same "$T/a.rest" "$T/b.rest"
grep -v '^DisplayAspectRatio = ' "$T/shipped.ini" >"$INI" # the shipped ini starts with a BOM
run_game
check_enabled Player1 True
# The first line is a section header (with the BOM, if the ini has one): it must be
# byte for byte the same, so a BOM is neither lost nor doubled.
first_line_kept() { [ "$(head -n 1 "$INI")" = "$(head -n 1 "$T/shipped.ini")" ]; }
check "first line (and BOM, if any) kept" first_line_kept
graphics_has_ratio() { section in Graphics "$INI" | grep -q '^DisplayAspectRatio = '; }
check "DisplayAspectRatio added in [Graphics]" graphics_has_ratio
end

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
