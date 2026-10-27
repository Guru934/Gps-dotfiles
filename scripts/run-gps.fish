#!/usr/bin/env fish
# === Aetheric Shell: unified startup orchestrator ===

set -gx LC_CTYPE C.UTF-8
set -g __done_enabled 0

# Visible startup log: every run appends here so a startup failure leaves a
# trace even after /tmp/qs-gps.log is rotated by the next run.
function log --argument-names msg
    printf '[%s] %s\n' (date '+%Y-%m-%d %H:%M:%S') "$msg" >>/tmp/gps-startup.log
end
log "run-gps.fish starting (user "(whoami)")"

# 0. Wait until the compositor accepts Wayland clients. hyprland.start can
#    fire a moment before the socket is ready; launching early crashed every
#    GUI process at login with "wl_display: Connection refused".
set -l ready_tries 0
while not hyprctl version >/dev/null 2>&1
    set ready_tries (math $ready_tries + 1)
    if test $ready_tries -ge 50
        log "WARN: compositor not reachable after 10s - continuing anyway"
        break
    end
    sleep 0.2
end
if test $ready_tries -gt 0
    log "compositor ready after ~"(math "0.2 * $ready_tries")"s of waiting"
end

# 1. Stop only the stale GPS shell and wallpaper daemon.
# Tide Island is also a QuickShell process, so never kill all quickshell PIDs.
pkill -9 -f "/home/rice/Projects/my-rice/shell.qml" 2>/dev/null; or true
pkill -9 -x awww-daemon 2>/dev/null; or true
rm -f /tmp/qs-gps.log /tmp/gps-theme.log
# /tmp/tide-island.log is NOT deleted here: a preserved island keeps writing
# to it; when the island is (re)started its redirect truncates the file.
sleep 0.4

# 2. Start the wallpaper daemon before extracting the initial palette.
if not pgrep -x awww-daemon >/dev/null 2>&1
    nohup awww-daemon >/tmp/awww-daemon.log 2>&1 &
    disown
    sleep 0.3
end

# 2b. Re-apply the last wallpaper: awww-daemon starts blank, so without this
# every shell restart would leave the background empty until a manual pick.
if test -f /tmp/gps-last-wall.txt
    set last_wall (cat /tmp/gps-last-wall.txt)
    if test -f "$last_wall"
        awww img "$last_wall" --transition-type none >/dev/null 2>&1
        log "wallpaper re-applied: $last_wall"
    else
        log "WARN: last wallpaper file missing: $last_wall"
    end
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

# 5. Keep the selected island untouched; start it only if absent.  Tide is
#    the safe default because the existing GPS shell still routes clipboard
#    and notification-center IPC to Tide.  A deliberate production cutover
#    uses: scripts/switch-island.fish gps
# The running process is `quickshell -p <prefix>/share/tide-island` (there is
# no shell.qml in its cmdline), so match the install path instead.
set -l backend_file "$HOME/.config/quickshell/gps-island-backend"
set -l island_backend "$GPS_ISLAND_BACKEND"
if test -z "$island_backend"; and test -f "$backend_file"
    set island_backend (string lower -- (string trim (cat "$backend_file")))
end
if test "$island_backend" = gps
    set -l gps_path "$HOME/Projects/my-rice/island/IslandProduction.qml"
    if not pgrep -f "/usr/bin/quickshell.*IslandProduction.qml" >/dev/null 2>&1
        nohup /usr/bin/quickshell --no-duplicate -p "$gps_path" >/tmp/gps-island.log 2>&1 &
        disown
    end
    sleep 0.5
    set -l island_pid (pgrep -f "my-rice/island/IslandProduction.qml" | head -1)
    set -l island_label "GPS island"
else
    if not pgrep -f "share/tide-[i]sland" >/dev/null 2>&1
        nohup "$HOME/.local/bin/tide-island" >/tmp/tide-island.log 2>&1 &
        disown
    end
    sleep 0.5
    set -l island_pid (pgrep -f 'share/tide-[i]sland' | head -1)
    set -l island_label "Tide Island"
end
if test -n "$island_pid"
    log "$island_label up (pid $island_pid)"
else
    log "ERROR: $island_label is not running"
end

# 6. Launch the QuickShell master shell.
nohup /usr/bin/quickshell -p "$HOME/Projects/my-rice/shell.qml" >/tmp/qs-gps.log 2>&1 &
disown
sleep 1
set -l shell_pid (pgrep -f 'my-rice/she[l]l.qml' | head -1)
if test -n "$shell_pid"
    log "GPS shell up (pid $shell_pid)"
else
    log "ERROR: GPS shell exited during startup - see /tmp/qs-gps.log"
end

# 7. Start the local screen-time tracker (ActivityWatch-compatible awatcher
# bundle) if it is not already running. Server binds 127.0.0.1:5600 only.
if not pgrep -x awatcher >/dev/null 2>&1
    nohup "$HOME/.local/opt/awatcher/awatcher" --no-tray >/tmp/awatcher.log 2>&1 &
    disown
end

log "startup pass complete"
