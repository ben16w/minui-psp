# Rewrites one [SECTION] of an ini file. Used by set_ini_values in scripts/ini.sh:
#   awk -f set_ini_values.awk INI TMP SECTION KEY VALUE [KEY VALUE ...]
# Writes the result to TMP and prints the number of lines it wrote, so the caller can
# check that the file was written completely. Keys are matched by exact name inside
# SECTION; missing keys (and a missing section) are added. CRLF files keep CRLF line
# endings, and a UTF-8 byte order mark before the first section header is kept.
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
