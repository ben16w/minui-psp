#!/bin/sh
set -eo pipefail
set -x

rm -f "$LOGS_PATH/PSP.txt"
exec >>"$LOGS_PATH/PSP.txt"
exec 2>&1

echo $0 $*

mkdir -p "$USERDATA_PATH/PSP-ppsspp"
EMU_DIR="$SDCARD_PATH/Emus/$PLATFORM/PSP.pak/PPSSPPSDL"
PAK_DIR="$SDCARD_PATH/Emus/$PLATFORM/PSP.pak"

export PATH="$EMU_DIR:$PAK_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$EMU_DIR/libs:$PAK_DIR/lib:$LD_LIBRARY_PATH"

PPSSPP_BIN="PPSSPPSDL"

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

    cd "$EMU_DIR"
    export HOME="$EMU_DIR"

    mkdir -p "$SDCARD_PATH/Saves/PSP"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"
    mount -o bind "$SDCARD_PATH/Saves/PSP" "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"

    mkdir -p "$SHARED_USERDATA_PATH/PSP-ppsspp"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"
    mount -o bind "$SHARED_USERDATA_PATH/PSP-ppsspp" "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"

	PROCESS_PID="$(pgrep -f "$PPSSPP_BIN" | tail -n 1)"
	if [ -f "$PAK_DIR/bin/$PLATFORM/handle-power-button" ]; then
		chmod +x "$PAK_DIR/bin/$PLATFORM/handle-power-button"
		handle-power-button "$PROCESS_PID" &
	fi

    "$EMU_DIR/PPSSPPSDL" "$*"
}

main "$@"
