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

PPSSPP_BIN="PPSSPPSDL"
PPSSPP_INI="$EMU_DIR/.config/ppsspp/PSP/SYSTEM/ppsspp.ini"

log() {
    echo "[PSP] $*"
}

find_usb_mountpoint() {
    CONFIG_PATH="$USERDATA_PATH/PSP-ppsspp/usb_mount_path"

    if [ -f "$CONFIG_PATH" ]; then
        CANDIDATE=$(head -n 1 "$CONFIG_PATH" | tr -d '\r')
        if [ -n "$CANDIDATE" ] && [ -d "$CANDIDATE" ]; then
            echo "$CANDIDATE"
            return 0
        fi
        log "Configured USB path \"$CANDIDATE\" is not available."
    fi

    if [ ! -r /proc/mounts ]; then
        log "Cannot read /proc/mounts to auto-detect USB mount point."
        return 1
    fi

    while IFS=' ' read -r DEV MOUNT FS REST; do
        case "$MOUNT" in
            /media/*|/mnt/*|/run/media/*)
                if echo "$MOUNT" | grep -qi usb; then
                    echo "$MOUNT"
                    return 0
                fi
                if echo "$DEV" | grep -qiE 'sd[a-z][0-9]*$|usb'; then
                    echo "$MOUNT"
                    return 0
                fi
            ;;
        esac
    done </proc/mounts

    return 1
}

backup_saves_to_usb() {
    DEST_ROOT="$1"

    if [ -n "$DEST_ROOT" ]; then
        if [ ! -d "$DEST_ROOT" ]; then
            log "Destination \"$DEST_ROOT\" does not exist."
            return 1
        fi
    else
        DEST_ROOT=$(find_usb_mountpoint) || {
            log "Unable to locate a USB mount point. Create $USERDATA_PATH/PSP-ppsspp/usb_mount_path with the desired destination if detection fails."
            return 1
        }
    fi

    TIMESTAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null)
    [ -n "$TIMESTAMP" ] || TIMESTAMP=$(date +%s 2>/dev/null)
    [ -n "$TIMESTAMP" ] || TIMESTAMP="backup"

    BACKUP_ROOT="$DEST_ROOT/PSP_Backups"
    BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

    if ! mkdir -p "$BACKUP_DIR"; then
        log "Failed to create backup directory at $BACKUP_DIR."
        return 1
    fi

    log "Backing up saves to $BACKUP_DIR."

    STATUS=0

    if [ -d "$SDCARD_PATH/Saves/PSP" ]; then
        mkdir -p "$BACKUP_DIR/Saves" || STATUS=1
        if ! cp -a "$SDCARD_PATH/Saves/PSP" "$BACKUP_DIR/Saves/" 2>/dev/null; then
            log "Failed to copy game saves."
            STATUS=1
        fi
    else
        log "No game saves found at $SDCARD_PATH/Saves/PSP."
    fi

    if [ -d "$SHARED_USERDATA_PATH/PSP-ppsspp" ]; then
        mkdir -p "$BACKUP_DIR/States" || STATUS=1
        if ! cp -a "$SHARED_USERDATA_PATH/PSP-ppsspp" "$BACKUP_DIR/States/" 2>/dev/null; then
            log "Failed to copy save states."
            STATUS=1
        fi
    else
        log "No save states found at $SHARED_USERDATA_PATH/PSP-ppsspp."
    fi

    sync

    if [ "$STATUS" -eq 0 ]; then
        log "Backed up saves to $BACKUP_DIR."
    else
        log "Backup completed with errors. Check the log for details. Destination: $BACKUP_DIR."
    fi

    return $STATUS
}

configure_aspect_ratio() {
    # Allow users to disable dynamic aspect ratio changes
    if [ -f "$USERDATA_PATH/PSP-ppsspp/no-aspect" ]; then
        echo "Aspect ratio changes disabled via no-aspect flag."
        new_aspect_ratio="1.000000"
    else
        # Detect Trimui model (Brick or Smart Pro)
        trimui_model=$(strings /usr/trimui/bin/MainUI | grep ^Trimui)

        if [ "$trimui_model" = "Trimui Brick" ]; then
            new_aspect_ratio="0.848000"
        else
            new_aspect_ratio="1.000000"
        fi
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
    case "$1" in
        backup-saves)
            shift
            if backup_saves_to_usb "$1"; then
                exit 0
            fi
            exit 1
        ;;
    esac

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
