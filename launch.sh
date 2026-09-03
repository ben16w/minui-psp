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
export LD_LIBRARY_PATH="$EMU_DIR:$PAK_DIR/lib:/usr/trimui/lib:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG_FILE="$EMU_DIR/assets/gamecontrollerdb.txt"

PPSSPP_BIN="PPSSPPSDL"
PPSSPP_SYSTEM_DIR="$EMU_DIR/.config/ppsspp/PSP/SYSTEM"
PPSSPP_CONFIG_DIR="$PAK_DIR/config"
PPSSPP_INI="$PPSSPP_SYSTEM_DIR/ppsspp.ini"
PPSSPP_PROFILE=

cleanup() {
    rm -f /tmp/stay_awake

    save_ppsspp_config

    restore_cpu_settings 0
    restore_cpu_settings 4

    umount "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA" || true
    umount "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE" || true
}

detect_ppsspp_profile() {
    case "$PLATFORM" in
        tg5050)
            PPSSPP_PROFILE="SmartProS"
            ;;
        tg5040)
            trimui_model=$(strings /usr/trimui/bin/MainUI | grep '^Trimui' | head -n 1)
            if [ "$trimui_model" = "Trimui Brick" ]; then
                PPSSPP_PROFILE="Brick"
            else
                PPSSPP_PROFILE="SmartPro"
            fi
            ;;
        *)
            echo "$PLATFORM is not a supported platform."
            exit 1
            ;;
    esac
}

load_ppsspp_config() {
    controls_src="$PPSSPP_CONFIG_DIR/controls-$PPSSPP_PROFILE.ini"
    ppsspp_src="$PPSSPP_CONFIG_DIR/ppsspp-$PPSSPP_PROFILE.ini"

    if [ ! -f "$controls_src" ] || [ ! -f "$ppsspp_src" ]; then
        echo "Missing PPSSPP config for profile $PPSSPP_PROFILE."
        exit 1
    fi

    mkdir -p "$PPSSPP_SYSTEM_DIR"
    cp -f "$controls_src" "$PPSSPP_SYSTEM_DIR/controls.ini"
    cp -f "$ppsspp_src" "$PPSSPP_INI"
}

save_ppsspp_config() {
    [ -n "$PPSSPP_PROFILE" ] || return

    controls_dst="$PPSSPP_CONFIG_DIR/controls-$PPSSPP_PROFILE.ini"
    ppsspp_dst="$PPSSPP_CONFIG_DIR/ppsspp-$PPSSPP_PROFILE.ini"

    [ -f "$PPSSPP_SYSTEM_DIR/controls.ini" ] && cp -f "$PPSSPP_SYSTEM_DIR/controls.ini" "$controls_dst"
    [ -f "$PPSSPP_INI" ] && cp -f "$PPSSPP_INI" "$ppsspp_dst"
}

update_ppsspp_setting() {
    setting_name="$1"
    setting_value="$2"

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

main() {
    echo "1" >/tmp/stay_awake
    trap "cleanup" EXIT INT TERM HUP QUIT

    if [ "$PLATFORM" = "tg3040" ] && [ -z "$DEVICE" ]; then
        export PLATFORM="tg5040"
    fi

    detect_ppsspp_profile
    load_ppsspp_config

    case "$PPSSPP_PROFILE" in
        Brick)
            update_ppsspp_setting "DisplayAspectRatio" "0.848000"
            export SDL_VIDEODRIVER=mali
            setalpha 0
            rm -f "$PPSSPP_SYSTEM_DIR/FailedGraphicsBackends.txt"
            save_cpu_settings 0
            set_cpu_settings 0 ondemand 1608000 1800000
            ;;
        SmartPro)
            update_ppsspp_setting "DisplayAspectRatio" "1.000000"
            export SDL_VIDEODRIVER=mali
            setalpha 0
            rm -f "$PPSSPP_SYSTEM_DIR/FailedGraphicsBackends.txt"
            save_cpu_settings 0
            set_cpu_settings 0 ondemand 1608000 1800000
            ;;
        SmartProS)
            update_ppsspp_setting "DisplayAspectRatio" "1.000000"
            save_cpu_settings 0
            save_cpu_settings 4
            set_cpu_settings 0 ondemand 1416000 1416000
            set_cpu_settings 4 performance 1992000 2160000
            ;;
    esac

    if ! command -v minui-power-control >/dev/null 2>&1; then
        show_message "Minui-power-control not found." 3
        exit 1
    fi

    chmod +x "$PAK_DIR/bin/minui-power-control"

    mkdir -p "$SDCARD_PATH/Saves/PSP"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"
    mount -o bind "$SDCARD_PATH/Saves/PSP" "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"

    mkdir -p "$SHARED_USERDATA_PATH/PSP-ppsspp"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"
    mount -o bind "$SHARED_USERDATA_PATH/PSP-ppsspp" "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"

    minui-power-control "${PPSSPP_BIN}_${PLATFORM}" &
    "${PPSSPP_BIN}_${PLATFORM}" "$*" --fullscreen --pause-menu-exit
}

main "$@"
