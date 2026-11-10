# shellcheck shell=sh
# RetroAchievements sync from NextUI to PPSSPP, sourced by launch.sh.
# Uses PPSSPP_SYSTEM_DIR, PPSSPP_INI, USERDATA_PATH and SHARED_USERDATA_PATH,
# config_changes_disabled from launch.sh and set_ini_values from scripts/ini.sh.

# PPSSPP keeps the RetroAchievements login token outside the ini, in
# SYSTEM/ppsspp_<secret>.dat (see NativeSaveSecret/NativeLoadSecret in PPSSPP).
PPSSPP_RA_TOKEN_FILE="$PPSSPP_SYSTEM_DIR/ppsspp_retroachievements.dat"
NEXTUI_SETTINGS="$SHARED_USERDATA_PATH/minuisettings.txt"

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
    # NextUI's offline RetroAchievements support lives inside minarch (it
    # hooks rcheevos' server calls in-process); it is not a network service
    # PPSSPP can use, so PPSSPP talks to retroachievements.org directly.
    # AchievementsHost is left as it is.
    set_ini_values "$PPSSPP_INI" "Achievements" \
        "AchievementsEnable" "True" \
        "AchievementsUserName" "$ra_username" \
        "AchievementsChallengeMode" "$ra_hardcore_value"

    # PPSSPP reads the token file verbatim, so write it without a newline,
    # and compare byte for byte so a stray trailing newline gets fixed. The
    # temp file is checked before it replaces the old token, so a full SD
    # card cannot leave a truncated token behind.
    if ! printf '%s' "$ra_token" | cmp -s - "$PPSSPP_RA_TOKEN_FILE"; then
        ra_token_tmp="$PPSSPP_RA_TOKEN_FILE.tmp.$$"
        if (umask 077 && printf '%s' "$ra_token" >"$ra_token_tmp") &&
            printf '%s' "$ra_token" | cmp -s - "$ra_token_tmp" &&
            mv -f "$ra_token_tmp" "$PPSSPP_RA_TOKEN_FILE"; then
            echo "RetroAchievements: login token updated."
        else
            echo "Error: could not write the RetroAchievements token (disk full?)."
        fi
        rm -f "$ra_token_tmp"
    fi
}
