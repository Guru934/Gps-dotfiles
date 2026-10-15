#!/usr/bin/env sh
SSID="$1"
[ -z "$SSID" ] && exit 0

if ! nmcli device wifi connect "$SSID" >/dev/null 2>&1; then
    PASS=$(LC_CTYPE=C.UTF-8 rofi -dmenu -password -p "󰖩 Password for $SSID")
    if [ -n "$PASS" ]; then
        nmcli device wifi connect "$SSID" password "$PASS" >/dev/null 2>&1
    fi
fi

