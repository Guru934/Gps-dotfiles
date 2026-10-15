#!/usr/bin/env fish
# === Aetheric Shell: unified startup orchestrator ===

set -gx LC_CTYPE C.UTF-8
set -g __done_enabled 0

# 1. Stop stale shell, island, and wallpaper processes.
# These are exact process-name matches so unrelated user applications survive.
pkill -9 -x quickshell 2>/dev/null; or true
pkill -9 -x tide-island 2>/dev/null; or true
pkill -9 -x awww-daemon 2>/dev/null; or true
rm -f /tmp/qs-gps.log /tmp/tide-island.log /tmp/gps-theme.log
sleep 0.4

# 2. Start the wallpaper daemon before extracting the initial palette.
if not pgrep -x awww-daemon >/dev/null 2>&1
    nohup awww-daemon >/tmp/awww-daemon.log 2>&1 &
    disown
    sleep 0.3
end

# 3. Extract the current wallpaper theme before launching UI surfaces.
"$HOME/Projects/my-rice/scripts/extract-theme.py" >/tmp/gps-theme.log 2>&1; or true

# 4. Start cliphist clipboard watchers for Tide Island.
if not pgrep -f "wl-paste --type text --watch cliphist store" >/dev/null 2>&1
    nohup wl-paste --type text --watch cliphist store >/tmp/cliphist-text.log 2>&1 &
    disown
end
if not pgrep -f "wl-paste --type image --watch cliphist store" >/dev/null 2>&1
    nohup wl-paste --type image --watch cliphist store >/tmp/cliphist-image.log 2>&1 &
    disown
end

# 5. Launch Tide Island (exclusive notification/OSD owner).
nohup "$HOME/.local/bin/tide-island" >/tmp/tide-island.log 2>&1 &
disown

# 6. Launch the QuickShell master shell.
nohup /usr/bin/quickshell -p "$HOME/Projects/my-rice/shell.qml" >/tmp/qs-gps.log 2>&1 &
disown
