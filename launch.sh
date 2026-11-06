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
PPSSPP_INI="$PPSSPP_SYSTEM_DIR/ppsspp.ini"
# PPSSPP keeps the RetroAchievements login token outside the ini, in
# SYSTEM/ppsspp_<secret>.dat (see NativeSaveSecret/NativeLoadSecret in PPSSPP).
PPSSPP_RA_TOKEN_FILE="$PPSSPP_SYSTEM_DIR/ppsspp_retroachievements.dat"
NEXTUI_SETTINGS="$SHARED_USERDATA_PATH/minuisettings.txt"

cleanup() {
    rm -f /tmp/stay_awake
    
    restore_cpu_settings 0
    restore_cpu_settings 4

    umount "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA" || true
    umount "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE" || true
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

# Print the value of a key from NextUI's minuisettings.txt ("key=value" lines;
# the last occurrence wins, like NextUI's own parser).
read_nextui_setting() {
    sed -n "s/^$1=//p" "$NEXTUI_SETTINGS" 2>/dev/null | tail -n 1 | tr -d '\r\n'
}

# Set "key = value" inside [section] of an ini file. Unlike
# update_ppsspp_setting this matches the exact key name within the section
# only, inserts the key (and section) when missing, and passes the value
# through the environment so no character in it needs escaping.
set_ini_value() {
    ini_file="$1"
    ini_tmp="$ini_file.tmp.$$"

    INI_SECTION="$2" INI_KEY="$3" INI_VALUE="$4" awk '
        BEGIN {
            section = ENVIRON["INI_SECTION"]
            key = ENVIRON["INI_KEY"]
            value = ENVIRON["INI_VALUE"]
        }
        function emit() {
            print key " = " value
            done = 1
        }
        {
            line = $0
            sub(/\r$/, "", line)
            # Ignore a UTF-8 byte order mark before the first section header.
            if (NR == 1 && index(line, "[") > 1 && index(line, "[") <= 4)
                line = substr(line, index(line, "["))

            if (line ~ /^[ \t]*\[.*\][ \t]*$/) {
                # Leaving the target section without having seen the key.
                if (in_section && !done)
                    emit()
                name = line
                gsub(/^[ \t]*\[|\][ \t]*$/, "", name)
                in_section = (name == section)
                if (in_section)
                    seen = 1
                print
                next
            }

            if (in_section && (eq = index(line, "=")) > 0) {
                k = substr(line, 1, eq - 1)
                gsub(/^[ \t]+|[ \t]+$/, "", k)
                if (k == key) {
                    if (!done)
                        emit()
                    next
                }
            }
            print
        }
        END {
            if (in_section && !done)
                emit()
            if (!seen) {
                print "[" section "]"
                emit()
            }
        }
    ' "$ini_file" >"$ini_tmp" && mv -f "$ini_tmp" "$ini_file"
    status=$?
    rm -f "$ini_tmp"
    return $status
}

set_achievements_setting() {
    set_ini_value "$PPSSPP_INI" "Achievements" "$1" "$2"
}

# Mirror the RetroAchievements settings from the NextUI settings menu into
# PPSSPP. Tracing is suspended while this runs so the login token never ends
# up in the debug log.
sync_retroachievements() {
    case "$-" in
    *x*)
        set +x
        _sync_retroachievements
        set -x
        ;;
    *)
        _sync_retroachievements
        ;;
    esac
    return 0
}

_sync_retroachievements() {
    if [ -f "$USERDATA_PATH/PSP-ppsspp/no-config-changes" ]; then
        echo "RetroAchievements: config changes disabled via no-config-changes flag."
        return
    fi
    if [ -f "$USERDATA_PATH/PSP-ppsspp/no-ra-sync" ]; then
        echo "RetroAchievements: sync disabled via no-ra-sync flag."
        return
    fi
    if [ ! -f "$NEXTUI_SETTINGS" ]; then
        echo "RetroAchievements: no NextUI settings found, leaving PPSSPP config unchanged."
        return
    fi
    if [ ! -f "$PPSSPP_INI" ]; then
        echo "RetroAchievements: $PPSSPP_INI not found."
        return
    fi

    ra_enable="$(read_nextui_setting raEnable)"
    ra_username="$(read_nextui_setting raUsername)"
    ra_token="$(read_nextui_setting raToken)"
    ra_authenticated="$(read_nextui_setting raAuthenticated)"
    ra_hardcore="$(read_nextui_setting raHardcoreMode)"

    if [ "$ra_enable" != "1" ]; then
        echo "RetroAchievements: disabled in NextUI, disabling in PPSSPP."
        set_achievements_setting "AchievementsEnable" "False"
        rm -f "$PPSSPP_RA_TOKEN_FILE"
        return
    fi

    if [ -z "$ra_username" ] || [ -z "$ra_token" ] || [ "$ra_authenticated" = "0" ]; then
        echo "RetroAchievements: enabled in NextUI but not logged in, disabling in PPSSPP."
        echo "RetroAchievements: log in via NextUI Settings > RetroAchievements first."
        set_achievements_setting "AchievementsEnable" "False"
        rm -f "$PPSSPP_RA_TOKEN_FILE"
        return
    fi

    ra_hardcore_value="False"
    [ "$ra_hardcore" = "1" ] && ra_hardcore_value="True"

    echo "RetroAchievements: enabling for user '$ra_username' (hardcore: $ra_hardcore_value)."
    set_achievements_setting "AchievementsEnable" "True"
    set_achievements_setting "AchievementsUserName" "$ra_username"
    set_achievements_setting "AchievementsChallengeMode" "$ra_hardcore_value"

    # PPSSPP reads the token file verbatim, so write it without a newline.
    if [ "$(cat "$PPSSPP_RA_TOKEN_FILE" 2>/dev/null)" != "$ra_token" ]; then
        (umask 077 && printf '%s' "$ra_token" >"$PPSSPP_RA_TOKEN_FILE.tmp") &&
            mv -f "$PPSSPP_RA_TOKEN_FILE.tmp" "$PPSSPP_RA_TOKEN_FILE"
        rm -f "$PPSSPP_RA_TOKEN_FILE.tmp"
    fi

    sync_retroachievements_host
}

# NextUI's offline RetroAchievements support lives inside minarch (it hooks
# rcheevos' server calls in-process); it is not a network service PPSSPP can
# use. PPSSPP therefore talks to retroachievements.org directly, unless the
# user points it at another server (e.g. a local caching proxy) by putting a
# URL in $USERDATA_PATH/PSP-ppsspp/ra-host. Only a host set this way is ever
# reset, so a host configured by hand inside PPSSPP is left alone.
sync_retroachievements_host() {
    ra_host_file="$USERDATA_PATH/PSP-ppsspp/ra-host"
    ra_host_marker="$USERDATA_PATH/PSP-ppsspp/.ra-host-managed"

    ra_host=""
    if [ -f "$ra_host_file" ]; then
        ra_host="$(head -n 1 "$ra_host_file" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    fi

    if [ -n "$ra_host" ]; then
        echo "RetroAchievements: using custom server $ra_host."
        set_achievements_setting "AchievementsHost" "$ra_host"
        touch "$ra_host_marker"
    elif [ -f "$ra_host_marker" ]; then
        echo "RetroAchievements: custom server removed, using retroachievements.org."
        set_achievements_setting "AchievementsHost" ""
        rm -f "$ra_host_marker"
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

    elif [ "$PLATFORM" = "tg5050" ]; then
        update_ppsspp_setting "DisplayAspectRatio" "1.000000"
        update_ppsspp_setting "GraphicsBackend" "3 (VULKAN)"
        save_cpu_settings 0
        save_cpu_settings 4
        set_cpu_settings 0 ondemand 1416000 1416000
        set_cpu_settings 4 performance 1992000 2160000
    fi

    if ! command -v minui-power-control >/dev/null 2>&1; then
        show_message "Minui-power-control not found." 3
        exit 1
    fi

    chmod +x "$PAK_DIR/bin/minui-power-control"

    allowed_platforms="tg5040 tg5050"
    if ! echo "$allowed_platforms" | grep -q "$PLATFORM"; then
        echo "$PLATFORM is not a supported platform."
        exit 1
    fi

    sync_retroachievements

    mkdir -p "$SDCARD_PATH/Saves/PSP"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"
    mount -o bind "$SDCARD_PATH/Saves/PSP" "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA"

    mkdir -p "$SHARED_USERDATA_PATH/PSP-ppsspp"
    mkdir -p "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"
    mount -o bind "$SHARED_USERDATA_PATH/PSP-ppsspp" "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE"

    # Launch emulator
    minui-power-control "${PPSSPP_BIN}_${PLATFORM}" &
    "${PPSSPP_BIN}_${PLATFORM}" "$*" --fullscreen --pause-menu-exit
}

main "$@"
