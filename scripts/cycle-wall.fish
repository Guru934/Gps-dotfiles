#!/usr/bin/env fish
if not pgrep -x awww-daemon >/dev/null
    nohup awww-daemon >/dev/null 2>&1 &
    disown
    sleep 0.3
end

set wall_dir "$HOME/Pictures/Wallpapers"
set walls (find "$wall_dir" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.gif" -o -iname "*.webp" \) | sort)

if test (count $walls) -eq 0
    exit 0
end

set direction "next"
if test (count $argv) -gt 0
    if test "$argv[1]" = "prev" -o "$argv[1]" = "previous" -o "$argv[1]" = "--prev"
        set direction "prev"
    end
end

set state_file "/tmp/gps_wall_idx_$USER"
set total (count $walls)
set idx 1

if test "$direction" = "prev"
    if test -f "$state_file"
        set idx (math (cat "$state_file") - 1)
    else
        set idx $total
    end
    if test $idx -lt 1
        set idx $total
    end
else
    if test -f "$state_file"
        set idx (math (cat "$state_file") + 1)
    end
    if test $idx -gt $total
        set idx 1
    end
end
echo $idx > "$state_file"

set -l script_dir (status dirname)
$script_dir/set-wallpaper "$walls[$idx]" --transition-type outer --transition-pos 0.92,0.06 --transition-fps 165 --transition-duration 1.1 >/dev/null 2>&1
