#!/usr/bin/env fish
pgrep -x awww-daemon >/dev/null; or begin
    nohup awww-daemon >/dev/null 2>&1 &
    disown
    sleep 0.3
end

set wall_dir "$HOME/Pictures/Wallpapers"
set walls (find "$wall_dir" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.gif" -o -iname "*.webp" \) | sort)

if test (count $walls) -eq 0
    exit 0
end

set chosen (
    for w in $walls
        set name (basename "$w")
        printf "%s\0icon\x1f%s\n" "$name" "$w"
    end | env LC_CTYPE=C.UTF-8 rofi -dmenu -i -p "󰸉 Wallpaper" -show-icons
)

if test -n "$chosen"
    awww img "$wall_dir/$chosen" --transition-type wave --transition-fps 165 --transition-duration 1.2 >/dev/null 2>&1
end
