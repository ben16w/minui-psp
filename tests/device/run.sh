#!/bin/sh
# On-device (or host) test of the Game Switcher preview logic in launch.sh (PR #9).
#
# It runs the *real* launch.sh and the *real* bin/jpg2bmp inside a throw-away SD card
# tree, with a stub standing in for PPSSPP and minui-power-control. So it checks what the
# PR's on-device table is really about (BusyBox tools, the aarch64 converter, the
# NextUI file layout, SIGTERM handling) without needing a screen or button presses.
# Nothing under the real SD card is touched; the sandbox is deleted afterwards.
#
# Usage (on the device, over ssh):
#   scp -r tests root@device:/mnt/SDCARD/Emus/tg5040/PSP.pak/
#   ssh root@device 'sh /mnt/SDCARD/Emus/tg5040/PSP.pak/tests/device/run.sh'
# Output: PASS/FAIL per test, exit code 0 only if all pass. Logs are kept in $OUT_DIR.
#
# Env overrides:
#   SRC_PAK    pak to test (default: two directories above this script)
#   JPG2BMP    jpg2bmp binary to use instead of $SRC_PAK/bin/jpg2bmp (host runs)
#   PLATFORM   tg5040 (default) or tg5050
#   OUT_DIR    where to keep logs and sandbox files on failure (default /tmp/psp-preview-test-out)
#   KEEP=1     keep the sandbox

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_PAK="${SRC_PAK:-$(cd "$HERE/../.." && pwd)}"
FIX="$HERE/fixtures"
PLATFORM="${PLATFORM:-tg5040}"
OUT_DIR="${OUT_DIR:-/tmp/psp-preview-test-out}"
T="$(mktemp -d /tmp/psp-preview-test.XXXXXX)" || exit 2

SD="$T/sd"
PAK="$SD/Emus/$PLATFORM/PSP.pak"
USERDATA="$SD/.userdata/$PLATFORM"
SHARED="$SD/.userdata/shared"
LOGS="$USERDATA/logs"
ROMS="$SD/Roms"
ROMDIR="$ROMS/PlayStation Portable (PSP)"
MINUI="$SHARED/.minui/PSP"
STATES="$SHARED/PSP-ppsspp"
STUB="$T/stub"
INI="$PAK/PPSSPP/.config/ppsspp/PSP/SYSTEM/ppsspp.ini"

# The device's BusyBox is small: say clearly which tool is missing instead of failing oddly.
missing=""
for tool in mktemp cp mv rm mkdir cmp grep head tr find sed cat sleep touch basename sync wc; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    echo "run.sh: missing tools on this system:$missing" >&2
    rm -rf "$T"
    exit 2
fi

PASS=0
FAIL=0
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

finish() {
    if [ -n "$KEEP" ] || [ "$FAIL" -gt 0 ]; then
        cp -R "$MINUI" "$OUT_DIR/minui-PSP" 2>/dev/null
        ls -l "$STATES" >"$OUT_DIR/states-listing.txt" 2>/dev/null
        echo "Logs and files kept in $OUT_DIR"
    fi
    [ -n "$KEEP" ] || rm -rf "$T"
}
trap finish EXIT

check() { # check <description> <command...>
    desc="$1"
    shift
    if "$@"; then
        echo "  ok   $desc"
    else
        echo "  FAIL $desc"
        CASE_FAIL=1
    fi
}

begin() {
    CASE="$1"
    CASE_FAIL=0
    echo "[$CASE]"
}

end() {
    if [ "$CASE_FAIL" = 0 ]; then
        PASS=$((PASS + 1))
        echo "PASS $CASE"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL $CASE"
    fi
}

contains() { grep -q -- "$2" "$1"; }
lacks() { ! grep -q -- "$2" "$1"; }
same() { cmp -s "$1" "$2"; }

# --- sandbox -------------------------------------------------------------------------
mkdir -p "$PAK/bin" "$PAK/PPSSPP/.config/ppsspp/PSP/SYSTEM" "$LOGS" "$ROMDIR" "$MINUI" "$STATES" "$STUB"
cp "$SRC_PAK/launch.sh" "$SRC_PAK/pak.json" "$PAK/"
cp "$SRC_PAK/PPSSPP/.config/ppsspp/PSP/SYSTEM/ppsspp.ini" "$INI"
cp "${JPG2BMP:-$SRC_PAK/bin/jpg2bmp}" "$PAK/bin/jpg2bmp" || { echo "no jpg2bmp found (set JPG2BMP)"; exit 2; }
chmod +x "$PAK/bin/jpg2bmp"

# Stubs for hardware helpers so nothing touches the screen or the real power control.
printf '#!/bin/sh\nexit 0\n' >"$PAK/bin/minui-power-control"
printf '#!/bin/sh\nexit 0\n' >"$PAK/bin/setalpha"
printf '#!/bin/sh\nexit 0\n' >"$PAK/bin/show_message"

# Fake PPSSPP: records its args, then runs $STUB/actions:
#   save <fixture> <prefix> <slot>   write <prefix>_<slot>.jpg (+ .ppst) into the state dir
#   sleep <n>                         wait n seconds (lets mtimes differ)
#   hang                              wait until killed (like a running emulator)
cat >"$PAK/PPSSPP/PPSSPPSDL_$PLATFORM" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$STUB/args"
echo $$ >"$STUB/pid"
sleep 2 # like a real boot: saves must be newer than launch.sh's marker (FAT has 2 s mtime)
while read -r action a b c; do
    case "$action" in
    save)
        cp "$FIX/$a.jpg" "$STATES/${b}_${c}.jpg"
        printf 'state' >"$STATES/${b}_${c}.ppst"
        touch "$STUB/saved"
        ;;
    sleep) sleep "$a" ;;
    hang) exec sleep 300 ;;
    esac
done <"$STUB/actions"
EOF
chmod +x "$PAK/PPSSPP/PPSSPPSDL_$PLATFORM" "$PAK/bin/"*

printf 'b' >"$ROMDIR/Game B.iso"
printf 'c' >"$ROMDIR/Game C.iso"

export PLATFORM DEVICE=brick SDCARD_PATH="$SD" USERDATA_PATH="$USERDATA" LOGS_PATH="$LOGS" \
    SHARED_USERDATA_PATH="$SHARED" ROMS_PATH="$ROMS" STUB FIX STATES
mkdir -p "$USERDATA/PSP-ppsspp"
touch "$USERDATA/PSP-ppsspp/debug" # trace logging, like the PR's setup step

conv() { "$PAK/bin/jpg2bmp" "$FIX/$1.jpg" "$T/expected-$1.bmp" && echo "$T/expected-$1.bmp"; }

# run_game <rom file> [action lines...]: runs launch.sh to completion and saves its log.
run_game() {
    rom="$1"
    shift
    rm -f "$STUB/args" "$STUB/pid" "$STUB/saved"
    printf '%s\n' "$@" >"$STUB/actions"
    sh "$PAK/launch.sh" "$ROMDIR/$rom" >"$T/launch.out" 2>&1
    cp "$LOGS/PSP.txt" "$OUT_DIR/$CASE.log" 2>/dev/null
}

preview() { echo "$MINUI/$1.$2.bmp"; }

# --- tests ---------------------------------------------------------------------------
begin "1 no save state -> no preview, no slot file (NextUI shows No Preview)"
run_game "Game B.iso" "sleep 0"
check "no slot file" test ! -e "$MINUI/Game B.iso.txt"
check "no preview image" test -z "$(find "$MINUI" -name 'Game B.iso.*.bmp')"
end

begin "2 save state -> preview and slot file"
run_game "Game C.iso" "save thumb1 ULUS10041_1.00 0"
check "slot file holds 0" contains "$MINUI/Game C.iso.txt" '^0$'
check "preview is converted thumb1" same "$(preview "Game C.iso" 0)" "$(conv thumb1)"
check "preview is a real BMP" sh -c "head -c 2 '$(preview "Game C.iso" 0)' | grep -q BM"
check "log says from save state" contains "$OUT_DIR/$CASE.log" 'Game switcher preview from save state'
end

begin "3 two saves in different slots -> newest slot wins"
run_game "Game C.iso" "save thumb1 ULUS10041_1.00 1" "sleep 2" "save thumb2 ULUS10041_1.00 5"
check "slot file holds 5" contains "$MINUI/Game C.iso.txt" '^5$'
check "preview .5 is converted thumb2" same "$(preview "Game C.iso" 5)" "$(conv thumb2)"
end

begin "4 other game without saving gets no preview"
run_game "Game B.iso" "sleep 0"
check "B has no slot file" test ! -e "$MINUI/Game B.iso.txt"
check "B has no preview image" test -z "$(find "$MINUI" -name 'Game B.iso.*.bmp')"
end

begin "5 launch without saving keeps the previous preview"
run_game "Game C.iso" "sleep 0"
check "slot file still 5" contains "$MINUI/Game C.iso.txt" '^5$'
check "preview .5 still thumb2" same "$(preview "Game C.iso" 5)" "$(conv thumb2)"
end

begin "6 resume hand-off file is removed and no state is forced"
printf '5' >/tmp/resume_slot.txt
run_game "Game C.iso" "sleep 0"
check "resume_slot.txt removed (minarch would pick it up)" test ! -f /tmp/resume_slot.txt
check "no --state argument" lacks "$STUB/args" '^--state='
end

begin "7 SIGTERM (power off) still writes the preview, once"
rm -f "$STUB/args" "$STUB/pid" "$STUB/saved"
printf '%s\n' "save thumb1 ULUS10041_1.00 3" "hang" >"$STUB/actions"
sh "$PAK/launch.sh" "$ROMDIR/Game C.iso" >"$T/launch.out" 2>&1 &
LAUNCH_PID=$!
i=0
while [ ! -f "$STUB/saved" ] && [ "$i" -lt 100 ]; do sleep 0.1 2>/dev/null || sleep 1; i=$((i + 1)); done
sleep 1
kill -TERM "$LAUNCH_PID" 2>/dev/null
kill -TERM "$(cat "$STUB/pid" 2>/dev/null)" 2>/dev/null
wait "$LAUNCH_PID" 2>/dev/null
cp "$LOGS/PSP.txt" "$OUT_DIR/$CASE.log" 2>/dev/null
check "slot file holds 3" contains "$MINUI/Game C.iso.txt" '^3$'
check "preview .3 is converted thumb1" same "$(preview "Game C.iso" 3)" "$(conv thumb1)"
check "preview written exactly once" test "$(grep -v '^+' "$OUT_DIR/$CASE.log" | grep -c 'Game switcher preview from save state')" = 1
end

begin "8 jpg2bmp works on this CPU and rejects junk"
echo "  info: $(uname -m)"
printf 'not an image' >"$T/junk.jpg"
check "converts a JPEG" "$PAK/bin/jpg2bmp" "$FIX/thumb1.jpg" "$T/out.bmp"
check "rejects junk with non-zero exit" sh -c "! '$PAK/bin/jpg2bmp' '$T/junk.jpg' '$T/junk.bmp' 2>/dev/null"
check "no tmp files left behind" sh -c "[ -z \"\$(find '$MINUI' -name '*.tmp')\" ]"
end

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
