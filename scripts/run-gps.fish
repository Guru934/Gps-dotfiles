#!/usr/bin/env fish
# === Aetheric Shell: unified startup orchestrator ===

set -gx LC_CTYPE C.UTF-8
set -g __done_enabled 0

# 1. Stop only the stale GPS shell and wallpaper daemon.
# Tide Island is also a QuickShell process, so never kill all quickshell PIDs.
pkill -9 -f "/home/rice/Projects/my-rice/shell.qml" 2>/dev/null; or true
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

# 5. Keep an already-running Tide Island untouched; start it only if absent.
if not pgrep -f "tide-island/shell.qml" >/dev/null 2>&1
    nohup "$HOME/.local/bin/tide-island" >/tmp/tide-island.log 2>&1 &
    disown
end

# 6. Launch the QuickShell master shell.
nohup /usr/bin/quickshell -p "$HOME/Projects/my-rice/shell.qml" >/tmp/qs-gps.log 2>&1 &
disown
