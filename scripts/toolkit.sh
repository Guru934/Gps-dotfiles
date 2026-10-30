#!/bin/bash
# Dashboard Tools-tab helper: capture and color-pick actions.
#
# Runs detached from the shell so a drawer auto-hide can never kill a
# running slurp/swappy/hyprpicker. Every path guards the slurp selection:
# a cancelled or empty selection exits 3 without touching the editor or the
# clipboard. The real outcome is written as a single line to $STATUS_FILE and
# read back by ToolsTab.qml (nothing is fabricated in QML).
#
# Exit codes: 0 = ok, 1 = failed, 3 = cancelled.
set -u

STATUS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/tools-last"
SNIP_FILE="${XDG_RUNTIME_DIR:-/tmp}/tools-snip-${UID:-1000}.png"

write_status() {
    mkdir -p "$(dirname "$STATUS_FILE")"
    printf '%s\n' "$1" > "$STATUS_FILE"
}

select_region() {
    local r
    r=$(slurp 2>/dev/null) || return 3
    [ -n "$r" ] || return 3
    printf '%s' "$r"
}

case "${1:-}" in
snip-edit)
    r=$(select_region) || exit 3
    if ! grim -g "$r" "$SNIP_FILE" 2>/dev/null; then
        write_status "region capture failed"
        exit 1
    fi
    write_status "region snip opened in Swappy"
    # Feed the validated file through stdin so Swappy still offers a save
    # dialog (an unnamed image) instead of silently overwriting the temp file.
    swappy -f - < "$SNIP_FILE"
    rm -f "$SNIP_FILE"
    ;;
snip-copy)
    r=$(select_region) || exit 3
    if ! ( set -o pipefail; grim -g "$r" - 2>/dev/null | wl-copy -t image/png ); then
        write_status "region copy failed"
        exit 1
    fi
    write_status "region copied to clipboard"
    ;;
full-edit)
    if ! grim "$SNIP_FILE" 2>/dev/null; then
        write_status "full-screen capture failed"
        exit 1
    fi
    write_status "full-screen snip opened in Swappy"
    swappy -f - < "$SNIP_FILE"
    rm -f "$SNIP_FILE"
    ;;
full-copy)
    if ! ( set -o pipefail; grim - 2>/dev/null | wl-copy -t image/png ); then
        write_status "full screen copy failed"
        exit 1
    fi
    write_status "full screen copied to clipboard"
    ;;
picker)
    c=$(hyprpicker -b 2>/dev/null) || exit 3
    c=$(printf '%s' "$c" | tr -d '[:space:]')
    [ -n "$c" ] || exit 3
    if ! printf '%s' "$c" | wl-copy 2>/dev/null; then
        write_status "color pick copy failed"
        exit 1
    fi
    write_status "color $c copied to clipboard"
    ;;
*)
    exit 64
    ;;
esac
exit 0
