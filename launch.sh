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
export EMU_DIR="$PAK_DIR/PPSSPPSDL"

export PATH="$EMU_DIR:$PAK_DIR/bin/$architecture:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"
export HOME="$EMU_DIR"

PPSSPP_BIN="PPSSPPSDL"
PPSSPP_INI="$EMU_DIR/.config/ppsspp/PSP/SYSTEM/ppsspp.ini"

configure_aspect_ratio() {
    # Detect Trimui model (Brick or Smart Pro)
    trimui_model=$(strings /usr/trimui/bin/MainUI | grep ^Trimui)

    if [ "$trimui_model" = "Trimui Brick" ]; then
        new_aspect_ratio="0.848000"
    else
        new_aspect_ratio="1.000000"
    fi

    if [ ! -f "$PPSSPP_INI" ]; then
        echo "Error: $PPSSPP_INI not found."
        exit 1
    fi

    if [ -n "$new_aspect_ratio" ]; then
        if grep -q ^DisplayAspectRatio "$PPSSPP_INI"; then
            sed -i "s/^DisplayAspectRatio *= *.*/DisplayAspectRatio = $new_aspect_ratio/" "$PPSSPP_INI"
        else
            echo "DisplayAspectRatio = $new_aspect_ratio" >> "$PPSSPP_INI"
        fi
    fi
}

cleanup() {
    rm -f /tmp/stay_awake

    if [ -f "$USERDATA_PATH/PSP-ppsspp/cpu_governor.txt" ]; then
        cat "$USERDATA_PATH/PSP-ppsspp/cpu_governor.txt" >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        rm -f "$USERDATA_PATH/PSP-ppsspp/cpu_governor.txt"
    fi
    if [ -f "$USERDATA_PATH/PSP-ppsspp/cpu_min_freq.txt" ]; then
        cat "$USERDATA_PATH/PSP-ppsspp/cpu_min_freq.txt" >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
        rm -f "$USERDATA_PATH/PSP-ppsspp/cpu_min_freq.txt"
    fi
    if [ -f "$USERDATA_PATH/PSP-ppsspp/cpu_max_freq.txt" ]; then
        cat "$USERDATA_PATH/PSP-ppsspp/cpu_max_freq.txt" >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        rm -f "$USERDATA_PATH/PSP-ppsspp/cpu_max_freq.txt"
    fi

    umount "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA" || true
    umount "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE" || true
}

main() {
    echo "1" >/tmp/stay_awake
    trap "cleanup" EXIT INT TERM HUP QUIT

    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor >"$USERDATA_PATH/PSP-ppsspp/cpu_governor.txt"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq >"$USERDATA_PATH/PSP-ppsspp/cpu_min_freq.txt"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq >"$USERDATA_PATH/PSP-ppsspp/cpu_max_freq.txt"
    echo ondemand >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo 1608000 >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
    echo 1800000 >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq

    mkdir -p "$SDCARD_PATH/Saves/PSP"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"
    mount -o bind "$SDCARD_PATH/Saves/PSP" "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"

    mkdir -p "$SHARED_USERDATA_PATH/PSP-ppsspp"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"
    mount -o bind "$SHARED_USERDATA_PATH/PSP-ppsspp" "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"

    # Apply dynamic configuration of aspect ratio
    configure_aspect_ratio

    # Launch emulator
    minui-power-control "$PPSSPP_BIN" &
    "$PPSSPP_BIN" "$*"
}

main "$@"
