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
    # Temp files left behind if a signal interrupted an ini/token write.
    rm -f "$PPSSPP_INI.tmp.$$" "$PPSSPP_RA_TOKEN_FILE.tmp.$$"
    
    restore_cpu_settings 0
    restore_cpu_settings 4

    umount "$EMU_DIR/.config/ppsspp/PSP/SAVEDATA" || true
    umount "$EMU_DIR/.config/ppsspp/PSP/PPSSPP_STATE" || true
}

# Succeeds (and says so) when the user opted out of config changes.
config_changes_disabled() {
    [ -f "$USERDATA_PATH/PSP-ppsspp/no-config-changes" ] || return 1
    echo "${1}Config changes disabled via no-config-changes flag."
}

# Set one or more keys in the [Graphics] section of ppsspp.ini:
#   update_ppsspp_graphics KEY VALUE [KEY VALUE ...]
# Missing keys are added to the section.
update_ppsspp_graphics() {
    config_changes_disabled && return

    if [ ! -f "$PPSSPP_INI" ]; then
        echo "Error: $PPSSPP_INI not found."
        exit 1
    fi

    set_ini_values "$PPSSPP_INI" "Graphics" "$@"
}

# Set "KEY = VALUE" pairs inside [SECTION] of an ini file in a single pass:
#   set_ini_values FILE SECTION KEY VALUE [KEY VALUE ...]
# Keys are matched by exact name within the section only. Missing keys (and
# the section) are inserted. Values are passed to awk as plain arguments, so
# no character in them needs escaping. CRLF files keep CRLF line endings.
# The file is only replaced when its content changes, and only after the new
# content has been verified to be written completely (a full SD card must
# not truncate the user's settings).
set_ini_values() {
    ini_file="$1"
    ini_section="$2"
    shift 2
    ini_tmp="$ini_file.tmp.$$"

    ini_lines="$(awk -- '
        BEGIN {
            out = ARGV[2]
            section = ARGV[3]
            n = 0
            for (i = 4; i + 1 < ARGC; i += 2) {
                n++
                keys[n] = ARGV[i]
                values[n] = ARGV[i + 1]
            }
            for (i = 2; i < ARGC; i++)
                delete ARGV[i]
            written = 0
        }
        function out_line(s) {
            print s > out
            written++
        }
        # Print the keys of the target section that were not found in it.
        function emit_missing(   j) {
            for (j = 1; j <= n; j++)
                if (!done[j]) {
                    out_line(keys[j] " = " values[j] eol)
                    done[j] = 1
                }
        }
        {
            line = $0
            if (sub(/\r$/, "", line) && NR == 1)
                eol = "\r"
            # Ignore a UTF-8 byte order mark before the first section header.
            if (NR == 1 && index(line, "[") > 1 && index(line, "[") <= 4)
                line = substr(line, index(line, "["))

            if (line ~ /^[ \t]*\[.*\][ \t]*$/) {
                # Leaving the target section: add the keys it lacked.
                if (in_section)
                    emit_missing()
                name = line
                gsub(/^[ \t]*\[|\][ \t]*$/, "", name)
                in_section = (name == section)
                if (in_section)
                    seen = 1
                out_line($0)
                next
            }

            if (in_section && (eq = index(line, "=")) > 0) {
                k = substr(line, 1, eq - 1)
                gsub(/^[ \t]+|[ \t]+$/, "", k)
                for (j = 1; j <= n; j++)
                    if (k == keys[j]) {
                        if (!done[j]) {
                            out_line(keys[j] " = " values[j] eol)
                            done[j] = 1
                        }
                        # Drop duplicates of a managed key.
                        next
                    }
            }
            out_line($0)
        }
        END {
            if (in_section)
                emit_missing()
            if (!seen) {
                out_line("[" section "]" eol)
                emit_missing()
            }
            if (close(out) != 0)
                exit 1
            print written
        }
    ' "$ini_file" "$ini_tmp" "$ini_section" "$@")"
    ini_status=$?

    if [ "$ini_status" -eq 0 ] && cmp -s "$ini_tmp" "$ini_file"; then
        # Nothing changed; leave the file (and its timestamp) alone.
        rm -f "$ini_tmp"
        return 0
    fi

    if [ "$ini_status" -ne 0 ] || [ -z "$ini_lines" ] || [ "$ini_lines" -eq 0 ] ||
        [ "$(wc -l <"$ini_tmp")" -ne "$ini_lines" ]; then
        echo "Error: could not write $ini_file (disk full?), leaving it unchanged."
        rm -f "$ini_tmp"
        return 1
    fi

    mv -f "$ini_tmp" "$ini_file" || {
        rm -f "$ini_tmp"
        return 1
    }
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

# Read the RetroAchievements keys from NextUI's minuisettings.txt ("key=value"
# lines; the last occurrence wins, like NextUI's own parser) in one pass,
# without spawning any process.
read_nextui_ra_settings() {
    cr="$(printf '\r')"
    ra_enable_set=0
    ra_enable=""
    ra_username=""
    ra_token=""
    ra_authenticated=""
    ra_hardcore=""
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%"$cr"}"
        case "$line" in
        raEnable=*)
            ra_enable="${line#*=}"
            ra_enable_set=1
            ;;
        raUsername=*) ra_username="${line#*=}" ;;
        raToken=*) ra_token="${line#*=}" ;;
        raAuthenticated=*) ra_authenticated="${line#*=}" ;;
        raHardcoreMode=*) ra_hardcore="${line#*=}" ;;
        esac
    done <"$NEXTUI_SETTINGS"
}

# Turn RetroAchievements off in PPSSPP and log the previous account out.
disable_retroachievements() {
    echo "RetroAchievements: $1, disabling in PPSSPP."
    set_ini_values "$PPSSPP_INI" "Achievements" \
        "AchievementsEnable" "False" \
        "AchievementsUserName" ""
    rm -f "$PPSSPP_RA_TOKEN_FILE"
}

_sync_retroachievements() {
    config_changes_disabled "RetroAchievements: " && return
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

    read_nextui_ra_settings

    # NextUI always saves raEnable; without it the settings file predates
    # RetroAchievements support, so there is no preference to mirror.
    if [ "$ra_enable_set" != "1" ]; then
        echo "RetroAchievements: not configured in NextUI, leaving PPSSPP config unchanged."
        return
    fi

    if [ "$ra_enable" != "1" ]; then
        disable_retroachievements "disabled in NextUI"
        return
    fi

    # NextUI saves raAuthenticated=1 only after a successful login (it
    # defaults to 0), and its own frontend requires it together with a token.
    if [ -z "$ra_username" ] || [ -z "$ra_token" ] || [ "$ra_authenticated" != "1" ]; then
        disable_retroachievements "enabled in NextUI but not logged in"
        echo "RetroAchievements: log in via NextUI Settings > RetroAchievements first."
        return
    fi

    ra_hardcore_value="False"
    [ "$ra_hardcore" = "1" ] && ra_hardcore_value="True"

    printf "RetroAchievements: enabling for user '%s' (hardcore: %s).\n" "$ra_username" "$ra_hardcore_value"
    set -- \
        "AchievementsEnable" "True" \
        "AchievementsUserName" "$ra_username" \
        "AchievementsChallengeMode" "$ra_hardcore_value"

    # NextUI's offline RetroAchievements support lives inside minarch (it
    # hooks rcheevos' server calls in-process); it is not a network service
    # PPSSPP can use. PPSSPP therefore talks to retroachievements.org
    # directly, unless the user points it at another server (e.g. a local
    # caching proxy) by putting a URL in $USERDATA_PATH/PSP-ppsspp/ra-host.
    # Only a host set this way is ever reset, so a host configured by hand
    # inside PPSSPP is left alone.
    ra_host_file="$USERDATA_PATH/PSP-ppsspp/ra-host"
    ra_host_marker="$USERDATA_PATH/PSP-ppsspp/.ra-host-managed"
    ra_host=""
    if [ -f "$ra_host_file" ]; then
        ra_host="$(head -n 1 "$ra_host_file" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    fi
    if [ -n "$ra_host" ]; then
        printf 'RetroAchievements: using custom server %s.\n' "$ra_host"
        set -- "$@" "AchievementsHost" "$ra_host"
    elif [ -f "$ra_host_marker" ]; then
        echo "RetroAchievements: custom server removed, using retroachievements.org."
        set -- "$@" "AchievementsHost" ""
    fi

    if set_ini_values "$PPSSPP_INI" "Achievements" "$@"; then
        if [ -n "$ra_host" ]; then
            touch "$ra_host_marker"
        else
            rm -f "$ra_host_marker"
        fi
    fi

    # PPSSPP reads the token file verbatim, so write it without a newline,
    # and compare byte for byte so a stray trailing newline gets fixed.
    if ! printf '%s' "$ra_token" | cmp -s - "$PPSSPP_RA_TOKEN_FILE"; then
        ra_token_tmp="$PPSSPP_RA_TOKEN_FILE.tmp.$$"
        (umask 077 && printf '%s' "$ra_token" >"$ra_token_tmp") &&
            mv -f "$ra_token_tmp" "$PPSSPP_RA_TOKEN_FILE"
        rm -f "$ra_token_tmp"
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
        aspect_ratio="1.000000"
        if [ "$trimui_model" = "Trimui Brick" ]; then
            aspect_ratio="0.848000"
        fi

        update_ppsspp_graphics \
            "DisplayAspectRatio" "$aspect_ratio" \
            "GraphicsBackend" "0 (OPENGL)"
        export SDL_VIDEODRIVER=mali
        setalpha 0
        rm -f "$EMU_DIR/.config/ppsspp/PSP/SYSTEM/FailedGraphicsBackends.txt"
        save_cpu_settings 0
        set_cpu_settings 0 ondemand 1608000 1800000

    elif [ "$PLATFORM" = "tg5050" ]; then
        update_ppsspp_graphics \
            "DisplayAspectRatio" "1.000000" \
            "GraphicsBackend" "3 (VULKAN)"
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
