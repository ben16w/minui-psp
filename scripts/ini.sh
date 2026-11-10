# shellcheck shell=sh
# ini file helpers, sourced by launch.sh (uses $PAK_DIR).

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

    ini_lines="$(awk -f "$PAK_DIR/scripts/set_ini_values.awk" "$ini_file" "$ini_tmp" "$ini_section" "$@")"
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
