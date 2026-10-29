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

set state_file "/tmp/gps_wall_idx_$USER"
set idx 1
if test -f "$state_file"
    set idx (math (cat "$state_file") + 1)
end
if test $idx -gt (count $walls)
    set idx 1
end
echo $idx > "$state_file"

set -l script_dir (status dirname)
$script_dir/set-wallpaper "$walls[$idx]" --transition-type outer --transition-pos 0.92,0.06 --transition-fps 165 --transition-duration 1.1 >/dev/null 2>&1
