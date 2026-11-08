#!/bin/sh
# End-to-end test of the Game Switcher preview on a real TrimUI device (PR #9).
#
# Unlike run.sh (stub emulator, throw-away SD tree), this drives the REAL NextUI, the REAL
# PPSSPP pak and the real SD card, with no human at the buttons:
#   - buttons are injected by writing evdev events to the "TRIMUI Player1" pad,
#   - games are launched through NextUI's own /tmp/next hand-off,
#   - screenshots are taken with the "Screenshot Monitor" pak's bin/screenshot,
#   - screenshots are judged by the bundled pngcolor (average colour of the screen centre).
#
# Requirements on the device: root, NextUI, this PSP pak installed in Emus/<platform>/PSP.pak,
# the Screenshot Monitor pak installed in Tools/<platform>/Screenshot Monitor.pak, and at
# least one file in a "...(PSP)" folder under Roms/. The test uses the FIRST file there.
#
# Usage (from a phone or computer):
#   ssh root@<device> 'sh /path/to/tests/device/e2e.sh'
#
# It temporarily changes recents / resume files of the test game and restores them on exit.
# The backup is kept on the SD card (/.userdata/shared/.psp-e2e-backup); if a run is cut
# short, the next run restores from it first.
# Do not touch the device while it runs. Results and screenshots: $OUT_DIR.
#
# Env overrides:
#   SDCARD_PATH (/mnt/SDCARD)  PLATFORM (tg5040)  ROM_DIR  ROM  OUT_DIR (/tmp/psp-e2e-out)
#   PSP_KEYS   space separated steps run inside PPSSPP after boot, to make save states.
#              Steps: up down left right a b x y l1 r1 select start | chords joined with +
#              (select+r1) | sleep<sec> | shot
#              Default uses the PPSSPP hotkeys set up on the device: select+r1 = save state,
#              select+right = next slot. It saves slot 0, moves to slot 1 and saves again.
#              PSP_KEYS="" skips saving: then there must be no preview (NextUI shows No Preview).
#   EXIT_KEYS  how the emulator is quit (default select+start; "" kills PPSSPP instead).
#   BOOT_WAIT (20)  UI_WAIT (4)  KEY_GAP (0.5)
#
# The save states made by the test (new files in /.userdata/shared/PSP-ppsspp) are deleted
# on exit. A state that already existed in slot 0 or 1 of the test game is overwritten.

HERE="$(cd "$(dirname "$0")" && pwd)"
SD="${SDCARD_PATH:-/mnt/SDCARD}"
PLATFORM="${PLATFORM:-tg5040}"
PAK="$SD/Emus/$PLATFORM/PSP.pak"
MON="$SD/Tools/$PLATFORM/Screenshot Monitor.pak"
SHARED="$SD/.userdata/shared"
LOGS="$SD/.userdata/$PLATFORM/logs"
OUT="${OUT_DIR:-/tmp/psp-e2e-out}"
BOOT_WAIT="${BOOT_WAIT:-20}"
UI_WAIT="${UI_WAIT:-6}"
KEY_GAP="${KEY_GAP:-0.5}"
PSP_KEYS="${PSP_KEYS-select+r1 sleep3 shot select+right sleep1 shot select+r1 sleep3 shot}"
EXIT_KEYS="${EXIT_KEYS-select+start}"
STATE_DIR="$SD/.userdata/shared/PSP-ppsspp"
PNGCOLOR="$HERE/bin/pngcolor"
BAK="$SD/.userdata/shared/.psp-e2e-backup" # on the SD card, so a power loss cannot lose it

PASS=0
FAIL=0
CASE_FAIL=0

say() { echo "$*"; }
die() { echo "e2e: $*" >&2; exit 2; }

# The device's BusyBox is small: say clearly which tool is missing instead of failing oddly.
missing=""
for tool in awk cmp cp mv rm mkdir grep head tail tr find ls wc sed cat sleep touch basename dirname sync pgrep killall id printf; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
[ -z "$missing" ] || die "missing tools on this system:$missing"

# --- preflight -----------------------------------------------------------------------
[ "$(id -u)" = 0 ] || die "run as root (needed to write to /dev/input)"
[ -d "$PAK" ] || die "PSP pak not found at $PAK"
[ -x "$PAK/bin/jpg2bmp" ] || die "$PAK/bin/jpg2bmp missing (install the pak from the PR's CI artifact)"
[ -f "$MON/bin/screenshot" ] || die "Screenshot Monitor pak not found at $MON"
[ -x "$PNGCOLOR" ] || die "$PNGCOLOR missing (use the psp-device-tests artifact)"
[ -f /tmp/nextui_exec ] || die "NextUI launcher not running (/tmp/nextui_exec missing)"

PAD="$(awk '/^N: Name="TRIMUI Player1"/{f=1} f&&/^H: Handlers=/{for(i=1;i<=NF;i++) if($i ~ /^event/){print "/dev/input/" $i; exit}}' /proc/bus/input/devices)"
[ -c "$PAD" ] || die "TRIMUI Player1 input device not found"

if [ -z "$ROM_DIR" ]; then
    for d in "$SD"/Roms/*"(PSP)"; do
        [ -d "$d" ] && ROM_DIR="$d" && break
    done
fi
[ -d "$ROM_DIR" ] || die "no Roms/*(PSP) folder found (set ROM_DIR)"
if [ -z "$ROM" ]; then
    for f in "$ROM_DIR"/*; do
        [ -f "$f" ] && ROM="$f" && break
    done
fi
[ -f "$ROM" ] || die "no game file in $ROM_DIR (set ROM)"

# Same emu tag NextUI uses: the text in the last (...) of the Roms folder name.
tag="${ROM%/*}"
tag="${tag#"$SD"/Roms/}"
tag="${tag%%/*}"
case "$tag" in *"("*")"*) tag="${tag##*(}"; tag="${tag%%)*}" ;; esac
ROM_FILE="$(basename "$ROM")"
MINUI="$SHARED/.minui/$tag"
SLOT_FILE="$MINUI/$ROM_FILE.txt"
PREVIEW="$MINUI/$ROM_FILE.0.bmp" # slot 0, used by E1; E2 uses whatever slot the game saved
RECENT="$SHARED/.minui/recent.txt"
PERSIST="$SHARED/.minui/game_switcher.txt"
AUTORESUME="$SHARED/.minui/auto_resume.txt"
SHOTDIR="$SD/Screenshots"

mkdir -p "$OUT" "$BAK"

# NEVER send SIGTERM to nextui.elf: SDL turns it into SDL_QUIT, which NextUI handles as
# PWR_powerOff(0) and the device shuts down. SIGKILL has no handler: NextUI just dies and the
# launcher loop in MinUI.pak starts it again (that is also what happens when it crashes).
kill_ui() { killall -9 nextui.elf 2>/dev/null; }

# --- back up everything we will touch, restore on exit ---------------------------------
# The backup lives on the SD card. If a run is cut short (power loss, SIGKILL), the next run
# first puts the files back from it.
restore_files() {
    rm -f /tmp/next
    if [ -f "$BAK/present" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] && cp -p "$BAK$f" "$f"
        done <"$BAK/present"
    fi
    if [ -f "$BAK/absent" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] && rm -f "$f"
        done <"$BAK/absent"
    fi
    rm -f "$PERSIST.tmp"
    # delete previews of other slots that the test created
    for f in "$MINUI/$ROM_FILE".*.bmp; do
        [ -f "$f" ] && ! grep -qxF "$f" "$BAK/present" 2>/dev/null && rm -f "$f"
    done
    # delete save states the test created (files that were not there before)
    if [ -f "$BAK/states.before" ]; then
        for f in "$STATE_DIR"/*; do
            [ -f "$f" ] && ! grep -qxF "$(basename "$f")" "$BAK/states.before" && rm -f "$f"
        done
    fi
    sync
}

if [ -f "$BAK/active" ]; then
    say "found the backup of an aborted run: restoring those files first"
    restore_files
    rm -f "$BAK/active"
fi

restore() {
    killall PPSSPPSDL_"$PLATFORM" 2>/dev/null
    restore_files
    rm -f "$BAK/active"
    kill_ui # relaunches NextUI with the restored files
    echo "restored; results in $OUT"
}

rm -f "${OUT:?}"/*.png "${OUT:?}"/*.log "${BAK:?}/present" "${BAK:?}/absent" "${BAK:?}/states.before" "${BAK:?}/marker"
say "device pad: $PAD"
say "game:       $ROM"
say "emu tag:    $tag"

stash() {
    if [ -e "$1" ]; then
        mkdir -p "$BAK$(dirname "$1")"
        cp -p "$1" "$BAK$1"
        echo "$1" >>"$BAK/present"
    else
        echo "$1" >>"$BAK/absent"
    fi
}
for f in "$RECENT" "$PERSIST" "$AUTORESUME" "$SLOT_FILE" "$PREVIEW"; do stash "$f"; done
for f in "$MINUI/$ROM_FILE".*.bmp; do [ -f "$f" ] && stash "$f"; done # previews of other slots
: >"$BAK/active"
sync
trap restore EXIT

# --- helpers ---------------------------------------------------------------------------
wait_for() { # wait_for <seconds> <command...>
    n="$1"
    shift
    while [ "$n" -gt 0 ]; do
        "$@" >/dev/null 2>&1 && return 0
        sleep 1
        n=$((n - 1))
    done
    return 1
}
running() { pgrep "$1" >/dev/null 2>&1; }
not_running() { ! pgrep "$1" >/dev/null 2>&1; }

# Write one evdev event (24 bytes: 16 zero timestamp bytes, type, code, value) to the pad.
pad() { # pad <type> <code> <value>
    v=$(($3 & 4294967295))
    b() { printf '\\%03o' $(($1 & 255)); }
    # shellcheck disable=SC2059 # the format is built from octal escapes on purpose
    printf "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0$(b "$1")$(b $(($1 >> 8)))$(b "$2")$(b $(($2 >> 8)))$(b "$v")$(b $((v >> 8)))$(b $((v >> 16)))$(b $((v >> 24)))" >"$PAD"
}
syn() { pad 0 0 0; }

btn_set() { # sets t (event type), c (code), val (value while pressed) for a button name
    val=1
    case "$1" in
    b) t=1 c=304 ;;
    a) t=1 c=305 ;;
    y) t=1 c=307 ;;
    x) t=1 c=308 ;;
    l1) t=1 c=310 ;;
    r1) t=1 c=311 ;;
    select) t=1 c=314 ;;
    start) t=1 c=315 ;;
    left) t=3 c=16 val=-1 ;;
    right) t=3 c=16 ;;
    up) t=3 c=17 val=-1 ;;
    down) t=3 c=17 ;;
    *) echo "unknown button: $1" >&2; return 1 ;;
    esac
}

# press <button>[+<button>...]: a tap, or a chord (all held together, then released).
press() {
    keys="$(printf '%s' "$1" | tr '+' ' ')"
    hold=0.05 # short, or NextUI's key repeat moves the selection more than once
    case "$1" in *+*) hold="${CHORD_HOLD:-0.3}" ;; esac
    for k in $keys; do
        btn_set "$k" || return 1
        pad "$t" "$c" "$val"
        syn
    done
    sleep "$hold"
    for k in $keys; do
        btn_set "$k"
        pad "$t" "$c" 0
        syn
    done
}

# shot <label>: takes a screenshot with the Screenshot Monitor pak, keeps it in $OUT.
shot() {
    sleep 1 # the pak names files by the second
    before="$(ls "$SHOTDIR" 2>/dev/null)"
    SDCARD_PATH="$SD" PATH="$MON/bin/$PLATFORM:$MON/bin:$PATH" sh "$MON/bin/screenshot" >"$OUT/$1.shot.log" 2>&1
    # shellcheck disable=SC2012 # names come from the screenshot pak (date based), ls -t is fine
    newest="$(ls -t "$SHOTDIR" 2>/dev/null | head -n 1)"
    SHOT=""
    SHOT_NAME=""
    if [ -n "$newest" ] && ! printf '%s\n' "$before" | grep -qxF "$newest"; then
        SHOT="$OUT/$1.png"
        SHOT_NAME="$newest"
        mv "$SHOTDIR/$newest" "$SHOT"
        say "  info: $1.png average colour (R G B): $(colour "$SHOT")"
    else
        say "  info: $1: no screenshot was written (see $OUT/$1.shot.log)"
    fi
}

colour() { "$PNGCOLOR" "$1" 2>/dev/null; } # prints "R G B"
# shellcheck disable=SC2046,SC2086 # word splitting of "R G B" is intended
is_red() { set -- $(colour "$1"); [ -n "$3" ] && [ "$1" -gt $(($2 + 60)) ] && [ "$1" -gt $(($3 + 60)) ]; }
# shellcheck disable=SC2046,SC2086
is_blue() { set -- $(colour "$1"); [ -n "$3" ] && [ "$3" -gt $(($1 + 60)) ] && [ "$3" -gt $(($2 + 60)) ]; }
not_fixture() { ! is_red "$1" && ! is_blue "$1"; }

begin() { CASE="$1"; CASE_FAIL=0; say "[$CASE]"; }
check() {
    d="$1"
    shift
    if "$@"; then say "  ok   $d"; else say "  FAIL $d"; CASE_FAIL=1; fi
}
end() {
    if [ "$CASE_FAIL" = 0 ]; then PASS=$((PASS + 1)); say "PASS $CASE"; else FAIL=$((FAIL + 1)); say "FAIL $CASE"; fi
}

# NextUI keeps recents relative to the SD card ("/Roms/..."), so it works on every platform.
# An absolute path is not found and NextUI drops it, rewriting recent.txt empty.
seed_recent() { mkdir -p "$(dirname "$RECENT")" && printf '%s\n' "${ROM#"$SD"}" >"$RECENT"; }

restart_ui() {
    kill_ui
    sleep 1
    wait_for 40 running nextui.elf && sleep "$UI_WAIT"
}

open_switcher() { # restarts NextUI directly into the Game Switcher
    printf unused >"$PERSIST"
    restart_ui
}

differs() { ! cmp -s "$1" "$2"; }
have_shot() { [ -n "$SHOT" ] && [ -s "$SHOT" ]; }
is_image() { head -c 2 "$1" | grep -q BM || head -c 4 "$1" | tail -c 3 | grep -q PNG; }

# --- E1: NextUI renders the BMP that jpg2bmp makes -------------------------------------
begin "E1 NextUI shows converted thumbnails in the Game Switcher"
mkdir -p "$MINUI"
seed_recent
printf 0 >"$SLOT_FILE"

"$PAK/bin/jpg2bmp" "$HERE/fixtures/thumb1.jpg" "$PREVIEW"
open_switcher
shot e1-red
check "screenshot taken" have_shot
check "switcher shows the red thumbnail" is_red "$SHOT"

"$PAK/bin/jpg2bmp" "$HERE/fixtures/thumb2.jpg" "$PREVIEW"
open_switcher
shot e1-blue
check "screenshot taken" have_shot
check "switcher shows the blue thumbnail" is_blue "$SHOT"

rm -f "$PREVIEW"
open_switcher
shot e1-nopreview
check "no preview file: switcher shows neither fixture colour" not_fixture "$SHOT"
end

# --- E2: real PPSSPP run, exit, preview written, switcher shows it ----------------------
begin "E2 real PPSSPP launch, exit, preview, switcher"
rm -f "$SLOT_FILE" "$PERSIST"
for f in "$MINUI/$ROM_FILE".*.bmp; do [ -f "$f" ] && rm -f "$f"; done
seed_recent
mkdir -p "$STATE_DIR"
ls -1 "$STATE_DIR" >"$BAK/states.before" 2>/dev/null
touch "$BAK/marker"
sleep 2 # FAT mtimes have 2 s resolution
printf "'%s/launch.sh' '%s'\n" "$PAK" "$ROM" >/tmp/next
kill_ui # the launcher loop then runs /tmp/next
check "PPSSPP started" wait_for 60 running PPSSPPSDL
sleep "$BOOT_WAIT"

shot e2-game
check "screenshot of the running game taken" have_shot
case "$SHOT_NAME" in Screenshot.*) named=0 ;; *) named=1 ;; esac
check "game screenshot is named after the game ($SHOT_NAME)" test "$named" = 1

i=0
for k in $PSP_KEYS; do
    i=$((i + 1))
    case "$k" in
    sleep*) sleep "${k#sleep}" ;;
    shot) shot "e2-step$i" ;;
    *) press "$k"; sleep "$KEY_GAP" ;;
    esac
done

if [ -n "$EXIT_KEYS" ]; then
    press "$EXIT_KEYS"
    check "PPSSPP exits on $EXIT_KEYS" wait_for 20 not_running PPSSPPSDL
fi
running PPSSPPSDL && killall PPSSPPSDL_"$PLATFORM" 2>/dev/null
check "PPSSPP exited" wait_for 30 not_running PPSSPPSDL
check "NextUI is back" wait_for 90 running nextui.elf
sleep "$UI_WAIT"
ls -l --full-time "$STATE_DIR" >"$OUT/e2-states.txt" 2>/dev/null || ls -l "$STATE_DIR" >"$OUT/e2-states.txt" 2>&1
cp "$LOGS/PSP.txt" "$OUT/e2-PSP.log" 2>/dev/null

if [ -z "$PSP_KEYS" ]; then
    check "no save state: no slot file" test ! -e "$SLOT_FILE"
    check "no save state: no preview image" test -z "$(find "$MINUI" -name "$ROM_FILE.*.bmp")"
    open_switcher
    shot e2-switcher
    check "switcher screenshot taken" have_shot
    check "switcher shows No Preview (neither fixture colour)" not_fixture "$SHOT"
else
    # shellcheck disable=SC2012,SC2046 # state names are PPSSPP's (no spaces); splitting is intended
    newest_state="$(ls -t $(find "$STATE_DIR" -name '*.jpg' ! -name '*.undo.jpg' -newer "$BAK/marker") 2>/dev/null | head -n 1)"
    new_states="$(find "$STATE_DIR" -name '*.jpg' ! -name '*.undo.jpg' -newer "$BAK/marker" | wc -l)"
    check "two save states were written (slot hotkey worked): $new_states" test "$new_states" -ge 2
    state_slot="${newest_state%.jpg}"
    state_slot="${state_slot##*_}"
    check "slot file holds the newest state's slot ($state_slot)" grep -qx "$state_slot" "$SLOT_FILE"
    PREVIEW_N="$MINUI/$ROM_FILE.$state_slot.bmp"
    check "preview file written for that slot" test -s "$PREVIEW_N"
    check "preview is a BMP/PNG" is_image "$PREVIEW_N"
    check "log: preview from save state" sh -c "grep -v '^+' '$OUT/e2-PSP.log' | grep -q 'Game switcher preview from save state'"
    if [ -n "$newest_state" ] && "$PAK/bin/jpg2bmp" "$newest_state" "$BAK/expected.bmp"; then
        check "preview is the newest state's thumbnail ($(basename "$newest_state"))" cmp -s "$PREVIEW_N" "$BAK/expected.bmp"
    else
        check "found a new state thumbnail to compare with" false
    fi

    open_switcher
    shot e2-switcher
    check "switcher screenshot taken" have_shot
    with_preview="$SHOT"
    mv "$PREVIEW_N" "$PREVIEW_N.off"
    open_switcher
    shot e2-switcher-nopreview
    check "switcher screenshot without preview taken" have_shot
    mv "$PREVIEW_N.off" "$PREVIEW_N"
    check "the preview changes what the switcher shows" differs "$with_preview" "$SHOT"
fi
end

say
say "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
