#!/usr/bin/env fish
# Switch between the installed Tide Island and the GPS project island.
# Exactly one top-center island is allowed to run at a time.

set -l REPO_DIR (realpath (status dirname)/..)
set -l mode $argv[1]
set -l gps_path "$REPO_DIR/island/IslandProduction.qml"
set -l tide_path "$HOME/.local/share/tide-island"
set -l backend_file "$HOME/.config/quickshell/gps-island-backend"

if test "$mode" != gps; and test "$mode" != tide
    echo "usage: switch-island.fish gps|tide" >&2
    exit 2
end

function stop_exact --argument-names pattern label
    set -l pids (pgrep -u (id -u) -f "$pattern" 2>/dev/null)
    for pid in $pids
        if test "$pid" = $fish_pid
            continue
        end
        kill -TERM $pid 2>/dev/null; or true
    end
    for i in (seq 1 20)
        if not pgrep -u (id -u) -f "$pattern" >/dev/null 2>&1
            return 0
        end
        sleep 0.1
    end
    echo "$label did not stop cleanly" >&2
    return 1
end

if test "$mode" = gps
    # Stop only Tide's exact QuickShell command line; never use pkill quickshell.
    stop_exact "/usr/bin/quickshell -p $tide_path" "Tide Island"; or exit 1
    if not pgrep -u (id -u) -f "/usr/bin/quickshell.*IslandProduction.qml" >/dev/null 2>&1
        nohup /usr/bin/quickshell --no-duplicate -p "$gps_path" >/tmp/gps-island.log 2>&1 &
        disown
    end
    sleep 0.6
    if not pgrep -u (id -u) -f "/usr/bin/quickshell.*IslandProduction.qml" >/dev/null 2>&1
        echo "GPS island failed to start; restore Tide with: switch-island.fish tide" >&2
        exit 1
    end
else
    # Stop only the GPS production command line.
    stop_exact "/usr/bin/quickshell.*IslandProduction.qml" "GPS island"; or exit 1
    if not pgrep -u (id -u) -f "/usr/bin/quickshell -p $tide_path" >/dev/null 2>&1
        nohup "$HOME/.local/bin/tide-island" >/tmp/tide-island.log 2>&1 &
        disown
    end
    sleep 0.6
    if not pgrep -u (id -u) -f "/usr/bin/quickshell -p $tide_path" >/dev/null 2>&1
        echo "Tide Island failed to start; inspect /tmp/tide-island.log" >&2
        exit 1
    end
end

mkdir -p (dirname "$backend_file")
printf '%s\n' "$mode" >"$backend_file"
echo "$mode island is running"
