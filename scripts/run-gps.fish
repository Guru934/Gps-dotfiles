#!/usr/bin/env fish
# === Aetheric Shell: unified startup orchestrator ===

# Advisory concurrency protection: serialize startup passes using flock
set -l gps_runtime_root "$XDG_RUNTIME_DIR"
if test -z "$gps_runtime_root" -o ! -d "$gps_runtime_root"
    set gps_runtime_root "/tmp/gps-"(id -u)
end
set -l gps_lock_dir "$gps_runtime_root/gps"
mkdir -p -m 0700 "$gps_lock_dir" 2>/dev/null; or true
set -l gps_startup_lock "$gps_lock_dir/startup.lock"

if not set -q _GPS_STARTUP_LOCKED
    if command -v flock >/dev/null 2>&1
        set -gx _GPS_STARTUP_LOCKED 1
        flock -o -n "$gps_startup_lock" fish (status filename) $argv
        set -l flock_rc $status
        if test $flock_rc -eq 1
            # Lock contention: another startup pass is already in progress
            printf '[%s] GPS startup: another startup pass is in progress (lock held at %s). Skipping duplicate.\n' (date '+%Y-%m-%d %H:%M:%S') "$gps_startup_lock" >>"$HOME/.config/quickshell/startup.log" 2>/dev/null; or true
            echo "GPS startup: another startup pass is in progress. Skipping duplicate." >&2
            exit 0
        end
        exit $flock_rc
    else
        printf '[%s] WARN: flock not found; proceeding without startup concurrency lock\n' (date '+%Y-%m-%d %H:%M:%S') >>"$HOME/.config/quickshell/startup.log" 2>/dev/null; or true
    end
end

set -l REPO_DIR (realpath (status dirname)/..)

set -gx LC_CTYPE C.UTF-8
set -gx GPS_ROOT "$REPO_DIR"
set -gx QML2_IMPORT_PATH "$REPO_DIR"
set -gx QML_IMPORT_PATH "$REPO_DIR"
set -g __done_enabled 0

if command -v hyprctl >/dev/null 2>&1
    hyprctl setenv GPS_ROOT "$REPO_DIR" >/dev/null 2>&1; or true
end

mkdir -p "$HOME/.config/quickshell"

# Keep runtime diagnostics in a user-owned cache directory rather than shared
# /tmp paths, which may belong to another user or a previous sandbox session.
set -l gps_cache_root "$HOME/.cache"
if set -q XDG_CACHE_HOME; and test -n "$XDG_CACHE_HOME"
    set gps_cache_root "$XDG_CACHE_HOME"
end
set -l gps_log_dir "$gps_cache_root/gps/logs"
mkdir -p "$gps_log_dir"
set -l gps_shell_log "$gps_log_dir/qs-gps.log"

# Ensure repository-managed user fontconfig is installed
if not test -e "$HOME/.config/fontconfig/fonts.conf"
    "$REPO_DIR/scripts/setup-fonts.sh" --no-cache >/dev/null 2>&1; or true
end

# Ensure repository-managed UWSM environment configuration is installed
if not test -e "$HOME/.config/uwsm/env"
    "$REPO_DIR/scripts/setup-uwsm.sh" >/dev/null 2>&1; or true
end

# Ensure consistent cursor configuration across GTK, Qt, and XWayland
"$REPO_DIR/scripts/setup-cursor.sh" >/dev/null 2>&1; or true

# Visible startup log: every run appends here so a startup failure leaves a
# trace even after the previous QuickShell log is rotated by the next run.
function log --argument-names msg
    printf '[%s] %s\n' (date '+%Y-%m-%d %H:%M:%S') "$msg" >>"$HOME/.config/quickshell/startup.log"
end
log "run-gps.fish starting (user "(whoami)")"

# Graceful process stop: sends SIGTERM, waits up to 1.5s, then SIGKILL fallback.
function stop_pattern --argument-names pattern label
    set -l pids (pgrep -u (id -u) -f "$pattern" 2>/dev/null)
    if test (count $pids) -eq 0
        return 0
    end
    for pid in $pids
        if test "$pid" = $fish_pid
            continue
        end
        kill -TERM $pid 2>/dev/null; or true
    end
    for i in (seq 1 15)
        if not pgrep -u (id -u) -f "$pattern" >/dev/null 2>&1
            log "stopped $label gracefully"
            return 0
        end
        sleep 0.1
    end
    for pid in (pgrep -u (id -u) -f "$pattern" 2>/dev/null)
        kill -9 $pid 2>/dev/null; or true
    end
    log "force-killed $label after 1.5s timeout"
    return 0
end

# Safe stop for GPS device watcher: strictly verifies UID ownership and exact
# script command line before signalling, preventing accidental termination of
# unrelated processes. Also removes stale PID files.
function stop_device_watcher --argument-names label
    set -l my_uid (id -u)
    set -l pid_file "$XDG_RUNTIME_DIR/gps/device-watcher.pid"
    if test -z "$XDG_RUNTIME_DIR" -o ! -d "$XDG_RUNTIME_DIR"
        set pid_file "/tmp/gps-$my_uid/device-watcher.pid"
    end

    set -l target_pids

    # 1. Read PID file if present
    if test -f "$pid_file"
        set -l file_pid (cat "$pid_file" 2>/dev/null | string trim)
        if test -n "$file_pid" -a -d "/proc/$file_pid"
            set -a target_pids $file_pid
        end
    end

    # 2. Inspect candidate PIDs for this user matching gps-device-watcher
    for p in (pgrep -u $my_uid -f "gps-device-watcher" 2>/dev/null)
        if test "$p" = $fish_pid
            continue
        end
        if not contains $p $target_pids
            set -a target_pids $p
        end
    end

    set -l confirmed_pids
    for pid in $target_pids
        if not test -d "/proc/$pid"
            continue
        end
        set -l p_uid (stat -c '%u' "/proc/$pid" 2>/dev/null)
        if test "$p_uid" != "$my_uid"
            continue
        end
        set -l cmdline (tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)
        if not string match -q "*gps-device-watcher*" "$cmdline"
            continue
        end
        set -a confirmed_pids $pid
    end

    if test (count $confirmed_pids) -eq 0
        rm -f "$pid_file"
        return 0
    end

    for pid in $confirmed_pids
        kill -TERM $pid 2>/dev/null; or true
    end

    for i in (seq 1 15)
        set -l any_alive 0
        for pid in $confirmed_pids
            if test -d "/proc/$pid"
                set any_alive 1
                break
            end
        end
        if test $any_alive -eq 0
            rm -f "$pid_file"
            log "stopped $label gracefully"
            return 0
        end
        sleep 0.1
    end

    for pid in $confirmed_pids
        if test -d "/proc/$pid"
            set -l p_uid (stat -c '%u' "/proc/$pid" 2>/dev/null)
            if test "$p_uid" = "$my_uid"
                kill -9 $pid 2>/dev/null; or true
            end
        end
    end
    rm -f "$pid_file"
    log "force-killed $label after 1.5s timeout"
    return 0
end

# 0. Wait until the compositor accepts Wayland clients. hyprland.start can
#    fire a moment before the socket is ready; launching early crashed every
#    GUI process at login with "wl_display: Connection refused".
set -l ready_tries 0
while not hyprctl version >/dev/null 2>&1
    set ready_tries (math $ready_tries + 1)
    if test $ready_tries -ge 200
        log "WARN: compositor not reachable after 10s - continuing anyway"
        break
    end
    sleep 0.05
end
if test $ready_tries -gt 0
    log "compositor ready after ~"(math "0.05 * $ready_tries")"s of waiting"
end

# 1. Stop only the stale GPS shell, device watcher, and wallpaper daemon.
# GPS Island is also a QuickShell process, so never kill all quickshell PIDs.
stop_pattern "quickshell.*shell\.qml" "GPS master shell"
stop_device_watcher "GPS device watcher"
stop_pattern "awww-daemon" "awww-daemon"
stop_pattern "mpvpaper" "mpvpaper"
stop_pattern "wl-paste.*cliphist store" "stale cliphist watcher"
stop_pattern "wl-paste.*gps-clip-store" "GPS clip store watcher"
rm -f "$gps_shell_log" "$HOME/.config/quickshell/theme.log"

# 1b. Start Polkit authentication agent once across the session.
# Does not terminate on shell restart so elevation sessions are preserved.
set -l polkit_pat "hyprpolkitagent|polkit-kde-authentication-agent-1|polkit-gnome-authentication-agent-1|polkit-mate-authentication-agent-1|pantheon-polkit-agent|lxpolkit"
if test -n "$POLKIT_AGENT_PATTERN"
    set polkit_pat "$POLKIT_AGENT_PATTERN|$polkit_pat"
end
if test -n "$POLKIT_AGENT_BIN"
    set -l custom_name (basename "$POLKIT_AGENT_BIN")
    set polkit_pat "$custom_name|$polkit_pat"
end

set -l existing_polkit ""
for pid in (pgrep -u (id -u) -f "$polkit_pat" 2>/dev/null)
    if test "$pid" = $fish_pid
        continue
    end
    set -l comm (cat /proc/$pid/comm 2>/dev/null)
    if test "$comm" = fish -o "$comm" = bash -o "$comm" = sh
        continue
    end
    set existing_polkit $pid
    break
end
if test -z "$existing_polkit"
    set -l polkit_started 0
    if systemctl --user is-enabled hyprpolkitagent.service >/dev/null 2>&1
        if systemctl --user start hyprpolkitagent.service >/dev/null 2>&1
            log "started polkit agent via hyprpolkitagent.service"
            set polkit_started 1
        end
    end
    if test $polkit_started -eq 0
        set -l candidate_agents \
            "$POLKIT_AGENT_BIN" \
            /usr/lib/hyprpolkitagent/hyprpolkitagent \
            /usr/lib/hyprpolkitagent \
            (command -v hyprpolkitagent 2>/dev/null) \
            /usr/lib/polkit-kde-authentication-agent-1 \
            /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
            /usr/libexec/polkit-gnome-authentication-agent-1 \
            /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 \
            /usr/lib/pantheon-polkit-agent
        for agent in $candidate_agents
            if test -n "$agent" -a -f "$agent" -a -x "$agent"
                nohup "$agent" >/tmp/polkit-agent.log 2>&1 &
                disown
                set polkit_started 1
                log "started polkit agent: $agent"
                break
            end
        end
        if test $polkit_started -eq 0
            log "WARN: no polkit authentication agent binary found on system"
        end
    end
else
    log "polkit agent already active (pid $existing_polkit) - not duplicating"
end

# 2. Start the wallpaper daemon before extracting the initial palette.
if not pgrep -x awww-daemon >/dev/null 2>&1
    nohup awww-daemon >"$gps_log_dir/awww-daemon.log" 2>&1 &
    disown
    for i in (seq 1 30)
        if awww query >/dev/null 2>&1
            break
        end
        sleep 0.05
    end
end

# 2b. Re-apply the last wallpaper: awww-daemon starts blank, so without this
# every shell restart would leave the background empty until a manual pick.
if test -x "$REPO_DIR/scripts/gps-wallpaper"
    "$REPO_DIR/scripts/gps-wallpaper" restore >/dev/null 2>&1
    log "wallpaper restored via gps-wallpaper"
else
    set -l last_wall_file "$HOME/.config/quickshell/gps-last-wall.txt"
    if test -f "$last_wall_file"
        set last_wall (cat "$last_wall_file")
        if test -f "$last_wall"
            awww img "$last_wall" --transition-type none >/dev/null 2>&1
            log "wallpaper re-applied: $last_wall"
        else
            log "WARN: last wallpaper file missing: $last_wall"
        end
    end
end

# 3. Extract the current wallpaper theme before launching UI surfaces.
"$REPO_DIR/scripts/extract-theme.py" >"$HOME/.config/quickshell/theme.log" 2>&1; or true

# 4. Start clipboard watchers using the GPS privacy-preserving clip-store wrapper.
set -l clip_store "$REPO_DIR/scripts/gps-clip-store"
if not pgrep -f "wl-paste --type text --watch .*gps-clip-store" >/dev/null 2>&1
    setsid wl-paste --type text --watch "$clip_store" </dev/null >"$gps_log_dir/cliphist-text.log" 2>&1 &
    disown
end
if not pgrep -f "wl-paste --type image --watch .*gps-clip-store" >/dev/null 2>&1
    setsid wl-paste --type image --watch "$clip_store" </dev/null >"$gps_log_dir/cliphist-image.log" 2>&1 &
    disown
end

# 5. Keep the GPS island untouched; start it only if absent. GPS Island
#    is the sole top-center island and D-Bus notification owner.
set -l gps_path "$REPO_DIR/island/IslandProduction.qml"
set -l island_pid (pgrep -u (id -u) -f "quickshell.*IslandProduction\.qml" | head -1)
set -l island_label "GPS island"
if test -z "$island_pid"
    nohup /usr/bin/quickshell --no-duplicate -d -p "$gps_path" >"$HOME/.config/quickshell/island.log" 2>&1 &
    disown
    for i in (seq 1 30)
        set island_pid (pgrep -u (id -u) -f "quickshell.*IslandProduction\.qml" | head -1)
        if test -n "$island_pid"
            break
        end
        sleep 0.05
    end
end
if test -n "$island_pid"
    log "$island_label up (pid $island_pid)"
else
    log "ERROR: $island_label is not running"
    if test -f "$HOME/.config/quickshell/island.log"
        set -l err_tail (tail -n 3 "$HOME/.config/quickshell/island.log" 2>/dev/null | string join " | ")
        if test -n "$err_tail"
            log "  island.log: $err_tail"
        end
    end
end

# 6. Launch the QuickShell master shell.
set -l shell_pid (pgrep -u (id -u) -f "quickshell.*shell\.qml" | head -1)
if test -z "$shell_pid"
    /usr/bin/quickshell --no-duplicate --daemonize --path "$GPS_ROOT/shell.qml"
    for i in (seq 1 40)
        set shell_pid (pgrep -u (id -u) -f "quickshell.*shell\.qml" | head -1)
        if test -n "$shell_pid"
            break
        end
        sleep 0.05
    end
end
if test -n "$shell_pid"
    log "GPS shell up (pid $shell_pid)"
else
    log "ERROR: GPS shell exited during startup - see $gps_shell_log"
    if test -f "$gps_shell_log"
        set -l err_tail (tail -n 3 "$gps_shell_log" 2>/dev/null | string join " | ")
        if test -n "$err_tail"
            log "  qs-gps.log: $err_tail"
        end
    end
end

# 7. Start the local screen-time tracker (ActivityWatch-compatible awatcher
# bundle) if it is not already running. Server binds 127.0.0.1:5600 only.
if not pgrep -x awatcher >/dev/null 2>&1
    nohup "$HOME/.local/opt/awatcher/awatcher" --no-tray >"$gps_log_dir/awatcher.log" 2>&1 &
    disown
end

# 8. Start external GPS watchdog in observation mode.
# Starts only after Island and main shell are confirmed ready.
# Explicitly uses --mode observe. Never blocks startup.
if test -n "$island_pid" -a -n "$shell_pid" -a -d "/proc/$island_pid" -a -d "/proc/$shell_pid"
    set -l watchdog_pid_file "$gps_lock_dir/watchdog.pid"
    set -l watchdog_running 0
    if test -f "$watchdog_pid_file"
        set -l w_pid (cat "$watchdog_pid_file" 2>/dev/null | string trim)
        if test -n "$w_pid" -a -d "/proc/$w_pid"
            set -l w_uid (stat -c '%u' "/proc/$w_pid" 2>/dev/null)
            if test "$w_uid" = (id -u)
                set -l w_cmd (tr '\0' ' ' <"/proc/$w_pid/cmdline" 2>/dev/null)
                if string match -q "*gps-watchdog*" "$w_cmd"
                    set watchdog_running 1
                    log "GPS watchdog already active (pid $w_pid) - not duplicating"
                end
            end
        end
    end
    if test $watchdog_running -eq 0
        set -l target_mode "observe"
        set -l flag_file "$HOME/.config/quickshell/gps-watchdog-auto"
        if test -f "$flag_file"
            set -l flag_content (cat "$flag_file" 2>/dev/null | string trim | string lower)
            if test $status -eq 0
                if test -z "$flag_content" -o "$flag_content" = "auto" -o "$flag_content" = "1" -o "$flag_content" = "true" -o "$flag_content" = "enabled"
                    set target_mode "auto"
                else
                    log "WARN: gps-watchdog-auto contains '$flag_content'; falling back to observe mode"
                end
            else
                log "WARN: gps-watchdog-auto is unreadable; falling back to observe mode"
            end
        end
        if test "$target_mode" = "auto"
            setsid python3 "$REPO_DIR/scripts/gps-watchdog" --mode auto </dev/null >/dev/null 2>&1 &
        else
            setsid python3 "$REPO_DIR/scripts/gps-watchdog" --mode observe </dev/null >/dev/null 2>&1 &
        end
        disown
        log "GPS watchdog launched in $target_mode mode"
    end
else
    log "WARN: skipping watchdog startup; Island or main shell is not ready"
end

log "startup pass complete"
