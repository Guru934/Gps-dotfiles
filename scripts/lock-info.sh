#!/usr/bin/env bash
# lock-info.sh — real system values for the hyprlock config.
# hyprlock config values cannot contain "$(...)" or "#" (parsed as
# expression/comment), so every dynamic line lives here instead.
# Modes: bat | net | kb | caps | clients
#        | media-title | media-artist | media-vol
#        | user | host | auth | howdy-status
set -u

truncate_text() {
    local text="$1"
    local max_len="$2"
    text=$(printf '%s' "$text" | tr '\r\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')
    if [ "${#text}" -le "$max_len" ]; then
        printf '%s\n' "$text"
    else
        local cutoff=$((max_len - 1))
        printf '%s…\n' "${text:0:$cutoff}"
    fi
}

case "${1:-}" in
bat)
    for f in /sys/class/power_supply/BAT*/capacity; do
        [ -r "$f" ] || continue
        c=$(head -1 "$f")
        d=$(dirname "$f")
        icon=󰁹
        w=""
        if [ -r "$d/status" ] && [ "$(head -1 "$d/status")" = "Charging" ]; then
            icon=󰂄
        fi
        if [ -r "$d/power_now" ]; then
            pw=$(head -1 "$d/power_now")
            if [ "${pw:-0}" -gt 0 ] 2>/dev/null; then
                w=$(awk -v p="$pw" 'BEGIN{printf " · %.1fW", p/1000000}')
            fi
        fi
        printf '%s %s%%%s\n' "$icon" "$c" "$w"
        exit 0
    done
    ;;
net)
    line=$(nmcli -t -f IN-USE,SSID,RATE device wifi 2>/dev/null | grep '^\*' | head -1)
    if [ -n "$line" ]; then
        ssid=$(printf '%s\n' "$line" | cut -d: -f2- | sed 's/:[0-9]* M.*$//')
        rate=$(printf '%s\n' "$line" | awk -F: '{print $NF}' | grep -oE '^[0-9]+')
        if [ -n "$rate" ]; then
            printf '%s %s · %s Mbps\n' "󰖩" "$ssid" "$rate"
        else
            printf '%s %s\n' "󰖩" "$ssid"
        fi
    else
        printf '%s offline\n' "󰖪"
    fi
    ;;
kb)
    lay=$(hyprctl -j devices 2>/dev/null | jq -r '[.keyboards[] | select(.main == true) | .layout] | first // empty' 2>/dev/null | tr '[:lower:]' '[:upper:]')
    [ -n "$lay" ] && printf '⌨ %s\n' "$lay"
    ;;
caps)
    st=$(hyprctl -j devices 2>/dev/null | jq -r '[.keyboards[] | select(.main == true) | .capsLock] | first | tostring' 2>/dev/null)
    case "$st" in
        true)  echo 'CAPS: ON' ;;
        false) echo 'CAPS: OFF' ;;
    esac
    ;;
clients)
    ws=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
    [ -n "$ws" ] || exit 0
    info=$(hyprctl -j clients 2>/dev/null | jq -r --argjson ws "$ws" \
        '[.[] | select(.workspace.id == $ws)] | "\(length) \(map(.class) | unique | join(" "))"' 2>/dev/null)
    n=${info%% *}
    apps=${info#* }
    apps=$(printf '%s' "$apps" | cut -c1-30)
    if [ -n "$apps" ]; then
        printf '󰍹 Workspace %s · %s clients: %s\n' "$ws" "$n" "$apps"
    else
        printf '󰍹 Workspace %s · %s clients\n' "$ws" "$n"
    fi
    ;;
media-title)
    st=$(playerctl status 2>/dev/null | head -1)
    if [ "$st" != "Playing" ] && [ "$st" != "Paused" ]; then
        if [ "${2:-}" = "--always" ]; then
            echo 'Nothing playing'
        fi
        exit 0
    fi
    raw_title=$(playerctl metadata --format '{{title}}' 2>/dev/null | head -1)
    if [ -z "$raw_title" ]; then
        raw_title="Unknown Title"
    fi
    if [ "$st" = "Paused" ]; then
        truncate_text "⏸ $raw_title" 22
    else
        truncate_text "$raw_title" 22
    fi
    ;;
media-artist)
    st=$(playerctl status 2>/dev/null | head -1)
    if [ "$st" != "Playing" ] && [ "$st" != "Paused" ]; then
        exit 0
    fi
    raw_artist=$(playerctl metadata --format '{{artist}}' 2>/dev/null | head -1)
    if [ -z "$raw_artist" ]; then
        if [ "$st" = "Paused" ]; then
            echo 'Paused'
        fi
        exit 0
    fi
    truncate_text "$raw_artist" 26
    ;;
media-vol|vol)
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    vol_raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
    if [ -z "$vol_raw" ]; then
        exit 0
    fi
    is_muted=0
    case "$vol_raw" in
        *"[MUTED]"*) is_muted=1 ;;
    esac
    vol_num=$(printf '%s\n' "$vol_raw" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    if [ -z "$vol_num" ]; then
        exit 0
    fi
    pct=$(awk -v v="$vol_num" 'BEGIN{printf "%d", (v * 100) + 0.5}')
    if [ "$is_muted" -eq 1 ]; then
        printf '%s%% (muted)\n' "$pct"
    else
        printf '%s%% Volume\n' "$pct"
    fi
    ;;
user)
    whoami
    ;;
host)
    printf '%s@%s\n' "$(whoami)" "$(hostname)"
    ;;
auth)
    grp=$(id -gn 2>/dev/null || echo rice)
    if grep -q pam_howdy /etc/pam.d/hyprlock 2>/dev/null; then
        printf '%s // pam_howdy + unix\n' "$grp"
    elif [ -f /etc/pam.d/hyprlock ]; then
        printf '%s // pam_unix\n' "$grp"
    else
        printf '%s // pam_unix (su)\n' "$grp"
    fi
    ;;
howdy-status)
    model="/etc/howdy/models/$(whoami).dat"
    wired=no
    grep -q pam_howdy /etc/pam.d/hyprlock 2>/dev/null && wired=yes
    if [ -f "$model" ] && [ "$wired" = yes ]; then
        echo 'Armed // /dev/video0'
    elif [ "$wired" = yes ]; then
        echo 'Ready — enroll: sudo howdy add'
    else
        echo 'Not configured // see README'
    fi
    ;;
sockets)
    if grep -q pam_howdy /etc/pam.d/hyprlock 2>/dev/null; then
        echo '1 SOCKET ONLINE'
    else
        echo '0 SOCKETS ONLINE'
    fi
    ;;
esac
