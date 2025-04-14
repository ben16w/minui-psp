#!/bin/sh
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
set -x

rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1

echo "$0" "$@"
cd "$PAK_DIR" || exit 1
mkdir -p "$USERDATA_PATH/$PAK_NAME"

architecture=arm
if uname -m | grep -q '64'; then
	architecture=arm64
fi

export EMU_DIR="$SDCARD_PATH/Emus/$PLATFORM/PSP.pak/PPSSPPSDL"
export PAK_DIR="$SDCARD_PATH/Emus/$PLATFORM/PSP.pak"
export HOME="$EMU_DIR"
export PATH="$EMU_DIR:$PAK_DIR/bin/$architecture:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"
export LD_LIBRARY_PATH="$EMU_DIR/libs:$PAK_DIR/lib:$LD_LIBRARY_PATH"

PPSSPP_BIN="PPSSPPSDL"
POWER_BUTTON_SUPPORTED=false
if [ -f "$PAK_DIR/bin/$PLATFORM/handle-power-button" ]; then
    POWER_BUTTON_SUPPORTED=true
    chmod +x "$PAK_DIR/bin/$PLATFORM/handle-power-button"
fi

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

    if [ -n "$HANDLE_POWER_LOOP_PID" ]; then
        kill "$HANDLE_POWER_LOOP_PID" || true  # Stop the background loop
        wait "$HANDLE_POWER_LOOP_PID" || true
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

    PPSSPPSDL "$*" &
	PROCESS_PID="$(pgrep -f "$PPSSPP_BIN" | tail -n 1)"

    if [ "$POWER_BUTTON_SUPPORTED" = true ]; then
        while true; do
            handle-power-button "$PROCESS_PID"
            sleep 1
        done &
        HANDLE_POWER_LOOP_PID=$!
	fi

	while kill -0 "$PROCESS_PID" 2>/dev/null; do
		sleep 1
	done
}

main "$@"
