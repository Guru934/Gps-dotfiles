#!/usr/bin/env fish
# === GPS Desktop Left Sidebar + Tide Island Launcher ===

# 1. Stop old instances and clear stale logs
pkill -f "my-rice/shell.qml" 2>/dev/null; or true
pkill -f "share/tide-island" 2>/dev/null; or true
rm -f /tmp/qs-gps.log /tmp/tide-island.log
sleep 0.4

# 2. Start awww wallpaper daemon silently
if not pgrep -x awww-daemon >/dev/null
    nohup awww-daemon >/dev/null 2>&1 &
    disown
end

# 3. Start cliphist clipboard watchers for Tide Island
if not pgrep -f "cliphist store" >/dev/null
    nohup wl-paste --type text --watch cliphist store >/dev/null 2>&1 &
    disown
    nohup wl-paste --type image --watch cliphist store >/dev/null 2>&1 &
    disown
end

# 4. Launch Tide Island (Top-Center Dynamic Island)
nohup "$HOME/.local/bin/tide-island" >/tmp/tide-island.log 2>&1 &
disown

# 5. Launch GPS Desktop Left Sidebar & Isolated Popups
nohup /usr/bin/quickshell -p "$HOME/Projects/my-rice/shell.qml" >/tmp/qs-gps.log 2>&1 &
disown
