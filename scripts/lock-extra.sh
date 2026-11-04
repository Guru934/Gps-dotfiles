#!/usr/bin/env bash
# ============================================================================
# lock-extra.sh — extra live data for the GPS hyprlock redesign.
# Companion to lock-info.sh (which stays untouched). Every value shown on the
# lock screen comes from here or from lock-info.sh — nothing is typed into
# hyprlock.conf as a fake demo value.
#
# Usage: lock-extra.sh <greeting|profile|volume|media-state|media-player|
#                       media-bar|media-pos|media-len|media-art>
#
# Rules: never fail loudly, never block. A broken label must not break the lock.
# Optional env:  GPS_LOCK_BAR_WIDTH (default 34)   GPS_LOCK_ART_FALLBACK
# ============================================================================
set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gps/lock"
ART_FALLBACK="${GPS_LOCK_ART_FALLBACK:-$CACHE_DIR/art-default.png}"
BAR_WIDTH="${GPS_LOCK_BAR_WIDTH:-34}"

have() { command -v "$1" >/dev/null 2>&1; }

# playerctl wrapper: prefer a playing player, otherwise any player.
pc() {
    have playerctl || return 1
    local playing
    playing="$(playerctl -a status -f '{{playerName}} {{status}}' 2>/dev/null | awk '$2=="Playing"{print $1; exit}')"
    if [ -n "$playing" ]; then
        playerctl -p "$playing" "$@" 2>/dev/null
    else
        playerctl "$@" 2>/dev/null
    fi
}

fmt_time() {   # seconds (float) -> MM:SS or H:MM:SS
    awk -v s="${1:-0}" 'BEGIN{
        s=int(s+0); h=int(s/3600); m=int((s%3600)/60); r=s%60;
        if(h>0) printf "%d:%02d:%02d\n", h,m,r; else printf "%02d:%02d\n", m,r }'
}

case "${1:-}" in
greeting)
    h="$(date +%H)"; h=$((10#$h))
    if   [ "$h" -lt 5 ];  then g="Late night"
    elif [ "$h" -lt 12 ]; then g="Good morning"
    elif [ "$h" -lt 17 ]; then g="Good afternoon"
    elif [ "$h" -lt 22 ]; then g="Good evening"
    else g="Good night"; fi
    printf '%s, %s\n' "$g" "${USER:-$(id -un)}"
    ;;

profile)
    p=""
    if [ -r /sys/firmware/acpi/platform_profile ]; then
        p="$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)"
    elif have powerprofilesctl; then
        p="$(powerprofilesctl get 2>/dev/null)"
    fi
    [ -z "$p" ] && [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ] && p="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
    printf 'Profile: %s\n' "${p:-unknown}"
    ;;

volume)
    if have wpctl; then
        out="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)"
        if [ -n "$out" ]; then
            if printf '%s' "$out" | grep -q MUTED; then
                echo "Muted"
            else
                awk '{printf "%d%% Volume\n", $2*100+0.5}' <<<"$out"
            fi
            exit 0
        fi
    fi
    if have pactl; then
        v="$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o '[0-9]*%' | head -n1)"
        [ -n "$v" ] && { echo "$v Volume"; exit 0; }
    fi
    echo "Volume n/a"
    ;;

media-state)
    case "$(pc status)" in
        Playing) echo "NOW PLAYING" ;;
        Paused)  echo "PAUSED" ;;
        *)       echo "NO MEDIA PLAYING" ;;
    esac
    ;;

media-btn-prev)
    st="$(pc status)"
    case "$st" in
        Playing|Paused) echo " 󰒮 " ;;
        *) exit 0 ;;
    esac
    ;;

media-btn-play-pause)
    st="$(pc status)"
    case "$st" in
        Playing) echo " 󰏤 " ;;
        Paused)  echo " 󰐊 " ;;
        *) exit 0 ;;
    esac
    ;;

media-btn-next)
    st="$(pc status)"
    case "$st" in
        Playing|Paused) echo " 󰒭 " ;;
        *) exit 0 ;;
    esac
    ;;

media-player)
    have playerctl || { echo "playerctl not installed"; exit 0; }
    name="$(pc metadata --format '{{playerName}}')"
    if [ -n "$name" ]; then echo "${name%%.*}"; else echo "MPRIS standby"; fi
    ;;

media-pos)
    pos="$(pc position)"
    if [ -n "$pos" ]; then fmt_time "$pos"; else echo "--:--"; fi
    ;;

media-len)
    len="$(pc metadata mpris:length)"   # microseconds
    if [ -n "$len" ] && [ "$len" -gt 0 ] 2>/dev/null; then
        fmt_time "$(awk -v l="$len" 'BEGIN{print l/1000000}')"
    else
        echo "--:--"
    fi
    ;;

media-bar)
    pos="$(pc position)"; len="$(pc metadata mpris:length)"
    awk -v p="${pos:-0}" -v l="${len:-0}" -v w="$BAR_WIDTH" 'BEGIN{
        if (l+0 <= 0) { for(i=0;i<w;i++) printf "─"; printf "\n"; exit }
        f = p/(l/1000000); if (f<0) f=0; if (f>1) f=1;
        k = int(f*(w-1)+0.5);
        for(i=0;i<w;i++){ if(i<k) printf "━"; else if(i==k) printf "●"; else printf "─" }
        printf "\n" }'
    ;;

media-art)
    # Prints a local image path for hyprlock's image widget (reload_cmd).
    url="$(pc metadata mpris:artUrl)"
    case "$url" in
        file://*)
            f="${url#file://}"
            f="$(printf '%b' "${f//%/\\x}")"      # decode %20 etc.
            if [ -r "$f" ]; then echo "$f"; exit 0; fi
            ;;
        http://*|https://*)
            mkdir -p "$CACHE_DIR" 2>/dev/null
            key="$(printf '%s' "$url" | md5sum | cut -c1-16)"
            dest="$CACHE_DIR/art-$key.img"
            if [ ! -s "$dest" ] && have curl; then
                curl -fsL --max-time 3 -o "$dest" "$url" 2>/dev/null || rm -f "$dest"
            fi
            if [ -s "$dest" ]; then
                find "$CACHE_DIR" -name 'art-*.img' ! -name "art-$key.img" -mmin +30 -delete 2>/dev/null
                echo "$dest"; exit 0
            fi
            ;;
    esac
    echo "$ART_FALLBACK"
    ;;

*)
    echo "usage: $(basename "$0") greeting|profile|volume|media-state|media-player|media-bar|media-pos|media-len|media-art|media-btn-prev|media-btn-play-pause|media-btn-next" >&2
    ;;
esac
exit 0

