#!/bin/sh
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
[ -f "$USERDATA_PATH/PSP-ppsspp/debug" ] && set -x

rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1

echo "$0" "$@"
cd "$PAK_DIR" || exit 1
mkdir -p "$USERDATA_PATH/PSP-ppsspp"

architecture=arm
if uname -m | grep -q '64'; then
    architecture=arm64
fi

export PAK_DIR="$SDCARD_PATH/Emus/$PLATFORM/$PAK_NAME.pak"
export EMU_DIR="$PAK_DIR/PPSSPP"

export PATH="$EMU_DIR:$PAK_DIR/bin/$architecture:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"
export HOME="$EMU_DIR"
export LD_LIBRARY_PATH="$EMU_DIR:$PAK_DIR/lib:/usr/trimui/lib:/usr/magicx/lib:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/assets/gamecontrollerdb.txt"

PPSSPP_BIN="PPSSPPSDL"
PPSSPP_INI="$EMU_DIR/.config/ppsspp/PSP/SYSTEM/ppsspp.ini"

cleanup() {
    rm -f /tmp/stay_awake
    # A late volume restore must not turn the screen back on during power off.
    [ -n "$sync_pid" ] && kill "$sync_pid" 2>/dev/null
    [ -n "$powerd_pid" ] && kill "$powerd_pid" 2>/dev/null
    
    restore_cpu_settings 0
    restore_cpu_settings 4

    for dir in SAVEDATA PPSSPP_STATE; do
        umount "$EMU_DIR/.config/ppsspp/PSP/$dir" || umount -l "$EMU_DIR/.config/ppsspp/PSP/$dir" || true
    done

    # Anything still mounted over the pak or running here can hold up power off.
    echo "After cleanup, mounts under the pak:"
    grep "$PAK_DIR" /proc/mounts || echo "  (none)"
    echo "Processes still running:"
    ps | grep -i -E "ppsspp|powerd" | grep -v grep || echo "  (none)"
}

update_ppsspp_setting() {
    setting_name="$1"
    setting_value="$2"
    
    # Allow users to disable config changes
    if [ -f "$USERDATA_PATH/PSP-ppsspp/no-config-changes" ]; then
        echo "Config changes disabled via no-config-changes flag."
        return
    fi

    if [ ! -f "$PPSSPP_INI" ]; then
        echo "Error: $PPSSPP_INI not found."
        exit 1
    fi

    if grep -q "^${setting_name}" "$PPSSPP_INI"; then
        sed -i "s/^${setting_name} *= *.*/${setting_name} = ${setting_value}/" "$PPSSPP_INI"
    else
        echo "Setting '$setting_name' not found in ini."
    fi
}

save_cpu_settings() {
    cpu_num="$1"
    cpu_path="/sys/devices/system/cpu/cpu${cpu_num}/cpufreq"
    
    cat "${cpu_path}/scaling_governor" >"$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_governor.txt"
    cat "${cpu_path}/scaling_min_freq" >"$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_min_freq.txt"
    cat "${cpu_path}/scaling_max_freq" >"$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_max_freq.txt"
}

restore_cpu_settings() {
    cpu_num="$1"
    cpu_path="/sys/devices/system/cpu/cpu${cpu_num}/cpufreq"
    
    if [ -f "$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_governor.txt" ]; then
        cat "$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_governor.txt" >"${cpu_path}/scaling_governor"
        rm -f "$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_governor.txt"
    fi
    if [ -f "$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_min_freq.txt" ]; then
        cat "$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_min_freq.txt" >"${cpu_path}/scaling_min_freq"
        rm -f "$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_min_freq.txt"
    fi
    if [ -f "$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_max_freq.txt" ]; then
        cat "$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_max_freq.txt" >"${cpu_path}/scaling_max_freq"
        rm -f "$USERDATA_PATH/PSP-ppsspp/cpu${cpu_num}_max_freq.txt"
    fi
}

set_cpu_settings() {
    cpu_num="$1"
    governor="$2"
    min_freq="$3"
    max_freq="$4"
    cpu_path="/sys/devices/system/cpu/cpu${cpu_num}/cpufreq"
    
    echo "$governor" >"${cpu_path}/scaling_governor"
    echo "$min_freq" >"${cpu_path}/scaling_min_freq"
    echo "$max_freq" >"${cpu_path}/scaling_max_freq"
}

# SDL GameController mapping for the Zero 28's pad ("magicx-input"). MinUI's
# zero28 platform.h numbers it A=0 B=1 X=2 Y=3 L1=4 R1=5 L2=6 R2=7 Select=8
# Start=9 L3=10 R3=11 d-pad 13-16 Menu=19, sticks on axes 0/1 and 2/3. The face
# buttons are mapped by position, not label: PPSSPP puts Cross on SDL A, so the
# bottom button (B) is Cross and the right one (A) is Circle, as on a PSP. Menu
# is SDL's guide button: in-game the overlay takes it (setup_zero28_overlay),
# and in PPSSPP's own menus it goes back. The GUID comes from sysfs so it
# matches whatever the kernel reports.
zero28_gamecontroller_map() {
    guid="1900000012b400006666000000010000"
    for dev in /sys/class/input/event*/device; do
        [ "$(cat "$dev/name" 2>/dev/null)" = "magicx-input" ] || continue
        le16() { v="$(cat "$dev/id/$1")"; echo "$(echo "$v" | cut -c3-4)$(echo "$v" | cut -c1-2)"; }
        guid="$(le16 bustype)0000$(le16 vendor)0000$(le16 product)0000$(le16 version)0000"
        break
    done
    echo "$guid,magicx-input,a:b1,b:b0,x:b3,y:b2,leftshoulder:b4,rightshoulder:b5,lefttrigger:b6,righttrigger:b7,back:b8,start:b9,leftstick:b10,rightstick:b11,dpup:b13,dpleft:b14,dpright:b15,dpdown:b16,guide:b19,leftx:a0,lefty:a1,rightx:a2,righty:a3,platform:Linux,"
}

# The MinUI-style in-game menu built into PPSSPPSDL_zero28 (nx-redux's
# overlay): MENU opens Continue / Save / Load / Options / PPSSPP Menu / Quit.
# It draws with MinUI's own font, reads the pad by the numbers in EMU_PAD (the
# same format as N64.pak), and turns with the display. Save state screenshots
# go where minarch keeps its own.
setup_zero28_overlay() {
    rom="$1"
    export EMU_OVERLAY_JSON="$PAK_DIR/zero28/overlay/overlay_settings.json"
    export EMU_OVERLAY_INI="$PPSSPP_INI"
    export EMU_OVERLAY_RES="$PAK_DIR/zero28/overlay/res"
    export EMU_OVERLAY_FONT="$SDCARD_PATH/.system/res/BPreplayBold-unhinted.otf"
    export EMU_OVERLAY_GAME="$(basename "$rom" | sed 's/\.[^.]*$//')"
    export EMU_OVERLAY_ROMFILE="$(basename "$rom")"
    export EMU_OVERLAY_SCREENSHOT_DIR="$SHARED_USERDATA_PATH/.minui/PSP"
    export EMU_OVERLAY_ROTATE="$DISPLAY_ROTATION"
    export EMU_OVERLAY_HOST_MENU="PPSSPP Menu"
    export EMU_PAD="a=0,b=1,l1=4,r1=5,menu=19,up=13,down=16,left=14,right=15"
    mkdir -p "$EMU_OVERLAY_SCREENSHOT_DIR"
    if [ ! -f "$EMU_OVERLAY_FONT" ]; then
        echo "Overlay font $EMU_OVERLAY_FONT not found"
    fi
}

main() {
    echo "1" >/tmp/stay_awake
    trap "cleanup" EXIT INT TERM HUP QUIT

    if [ "$PLATFORM" = "tg3040" ] && [ -z "$DEVICE" ]; then
        export PLATFORM="tg5040"
    fi

    if [ "$PLATFORM" = "tg5040" ]; then

        # Detect Trimui model (Brick or Smart Pro)
        trimui_model=$(strings /usr/trimui/bin/MainUI | grep ^Trimui)
        if [ "$trimui_model" = "Trimui Brick" ]; then
            update_ppsspp_setting "DisplayAspectRatio" "0.848000"
        else
            update_ppsspp_setting "DisplayAspectRatio" "1.000000"
        fi

        update_ppsspp_setting "GraphicsBackend" "0 (OPENGL)"
        export SDL_VIDEODRIVER=mali
        setalpha 0
        rm -f "$EMU_DIR/.config/ppsspp/PSP/SYSTEM/FailedGraphicsBackends.txt"
        save_cpu_settings 0
        set_cpu_settings 0 ondemand 1608000 1800000

    elif [ "$PLATFORM" = "zero28" ]; then
        # MagicX Mini Zero 28 on MOSS: the same A133P / PowerVR GE8300 as the
        # Smart Pro, with its SDL2 in /usr/magicx/lib. The 640x480 panel is
        # mounted portrait (480x640) and MOSS's SDL2 cannot rotate GL output,
        # so the binary is built with the display-rotation patch and turns the
        # picture itself. Put 270 in $USERDATA_PATH/PSP-ppsspp/rotation if it
        # comes out upside down.
        update_ppsspp_setting "DisplayAspectRatio" "1.000000"
        update_ppsspp_setting "GraphicsBackend" "0 (OPENGL)"
        export SDL_VIDEODRIVER=mali
        export DISPLAY_ROTATION=90
        if [ -f "$USERDATA_PATH/PSP-ppsspp/rotation" ]; then
            DISPLAY_ROTATION="$(cat "$USERDATA_PATH/PSP-ppsspp/rotation")"
        fi
        SDL_GAMECONTROLLERCONFIG="$(zero28_gamecontroller_map)"
        export SDL_GAMECONTROLLERCONFIG
        echo "DISPLAY_ROTATION=$DISPLAY_ROTATION"
        echo "SDL_GAMECONTROLLERCONFIG=$SDL_GAMECONTROLLERCONFIG"
        setup_zero28_overlay "$1"
        # PPSSPP lays its menus out for about 1000x700 and they overlap at 640x480.
        # Scale them to 2^(-4/8) = 0.71x once; after that the UI size setting
        # in PPSSPP's own menu is the user's.
        if [ ! -f "$USERDATA_PATH/PSP-ppsspp/ui-scale-set" ]; then
            update_ppsspp_setting "UIScaleFactor" "-4"
            touch "$USERDATA_PATH/PSP-ppsspp/ui-scale-set"
        fi
        setalpha 0
        rm -f "$EMU_DIR/.config/ppsspp/PSP/SYSTEM/FailedGraphicsBackends.txt"
        save_cpu_settings 0
        set_cpu_settings 0 ondemand 1608000 1800000

    elif [ "$PLATFORM" = "tg5050" ]; then
        update_ppsspp_setting "DisplayAspectRatio" "1.000000"
        update_ppsspp_setting "GraphicsBackend" "3 (VULKAN)"
        save_cpu_settings 0
        save_cpu_settings 4
        set_cpu_settings 0 ondemand 1416000 1416000
        set_cpu_settings 4 performance 1992000 2160000
    fi

    # minui-power-control reads the power key from a fixed event node that is
    # wrong on the Zero 28 (its key is on axp2202-pek), so it isn't used there.
    use_power_control=true
    [ "$PLATFORM" = "zero28" ] && use_power_control=false

    if $use_power_control && ! command -v minui-power-control >/dev/null 2>&1; then
        show_message "Minui-power-control not found." 3
        exit 1
    fi

    $use_power_control && chmod +x "$PAK_DIR/bin/minui-power-control"

    allowed_platforms="tg5040 tg5050 zero28"
    if ! echo "$allowed_platforms" | grep -q "$PLATFORM"; then
        echo "$PLATFORM is not a supported platform."
        exit 1
    fi

    mkdir -p "$SDCARD_PATH/Saves/PSP"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"
    mount -o bind "$SDCARD_PATH/Saves/PSP" "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"

    mkdir -p "$SHARED_USERDATA_PATH/PSP-ppsspp"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"
    mount -o bind "$SHARED_USERDATA_PATH/PSP-ppsspp" "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"

    # Launch emulator
    if [ "$PLATFORM" = "zero28" ]; then
        run_zero28 "$@"
        return
    fi
    $use_power_control && minui-power-control "${PPSSPP_BIN}_${PLATFORM}" &
    "${PPSSPP_BIN}_${PLATFORM}" "$*" --fullscreen --pause-menu-exit
}

# The Zero 28 runs PPSSPP in the background so zero28-powerd can put it to
# sleep, and has MinUI's syncsettings.elf restore the user's volume: opening
# the audio device leaves the codec at full volume until a volume key is
# pressed. zero28-powerd asks for power off by touching $POWEROFF_FLAG and
# quitting PPSSPP; the bind mounts come off before the device shuts down.
run_zero28() {
    export POWEROFF_FLAG=/tmp/psp_poweroff
    rm -f "$POWEROFF_FLAG"
    system_bin="${SYSTEM_PATH:-$SDCARD_PATH/.system/$PLATFORM}/bin"

    "${PPSSPP_BIN}_${PLATFORM}" "$*" --fullscreen --pause-menu-exit &
    emu_pid=$!
    zero28-powerd "$emu_pid" &
    powerd_pid=$!
    (sleep 2; "$system_bin/syncsettings.elf"; sleep 4; exec "$system_bin/syncsettings.elf") &
    sync_pid=$!
    wait "$emu_pid"
    echo "PPSSPP exited ($?)"

    if [ -f "$POWEROFF_FLAG" ]; then
        rm -f "$POWEROFF_FLAG"
        trap - EXIT INT TERM HUP QUIT
        cleanup
        # As MinUI's PLAT_powerOff: don't relaunch anything, then shut down.
        rm -f /tmp/minui_exec
        sync
        exec "$system_bin/shutdown"
    fi
}

main "$@"
