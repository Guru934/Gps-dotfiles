#!/usr/bin/env bash
# ==============================================================================
# GPS Desktop Boot Splash Theme Preview Utility
#
# Allows live interactive previewing of the GPS Plymouth theme in a TTY.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="${SCRIPT_DIR}/theme"

print_help() {
    cat << 'EOF'
GPS Plymouth Splash Preview Tool
================================

To preview the GPS boot splash theme without rebooting:

1. Switch to a free text console (TTY):
   Press: Ctrl + Alt + F3 (or F4)
   Log in with your normal user account or root.

2. Run this preview script with elevated privileges:
   sudo ./boot/preview.sh

   Or run the raw Plymouth commands directly:
   sudo plymouthd --mode=boot --theme=gps --debug --debug-file=/tmp/plymouth.log
   sudo plymouth show-splash
   sudo plymouth message --text="Starting GPS Desktop..."
   sudo plymouth update --status="Loading kernel modules..."
   # Sleep or test password prompt:
   sudo plymouth ask-for-password --prompt="Passphrase:"
   sudo plymouth quit

3. Switch back to your graphical desktop:
   Press: Ctrl + Alt + F2 (or F1)

SAFETY WARNING:
Do not run plymouth show-splash from inside an active Wayland compositor
(Hyprland) as it requests DRM Master access which will conflict with the
running display server.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    print_help
    exit 0
fi

# Detect if running inside a Wayland or X11 graphical session
if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
    echo "======================================================================"
    echo "WARNING: Graphical desktop environment detected (${WAYLAND_DISPLAY:-${DISPLAY}})."
    echo "Plymouth requires direct framebuffer / DRM master access."
    echo "Running it inside Wayland or X11 may corrupt the display or freeze."
    echo ""
    echo "Please switch to a virtual console (TTY3):"
    echo "  1. Press Ctrl + Alt + F3"
    echo "  2. Log in"
    echo "  3. Run: sudo ./boot/preview.sh"
    echo "  4. Return to desktop: Ctrl + Alt + F2"
    echo "======================================================================"
    read -rp "Run interactive simulation in terminal instead? [y/N]: " choice
    case "${choice,,}" in
        y|yes)
            echo "Simulating boot splash sequence..."
            echo "[Theme] GPS Plymouth (Theme.surfaceDeep #0F131C, Accent #2DD4BF)"
            echo "  -> Loading watermark.png (GPS Diamond Logo)"
            echo "  -> Initializing 4px slim progress bar at 58% height"
            echo "  -> Animating 24-frame teal throbber (32x32)"
            for i in {1..5}; do
                echo "  -> Boot progress: $((i * 20))%"
                sleep 0.2
            done
            echo "[Theme] Handing off to SDDM greeter..."
            exit 0
            ;;
        *)
            exit 1
            ;;
    esac
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: Previewing Plymouth directly on a TTY requires root privileges." >&2
    echo "Please run: sudo $0" >&2
    exit 1
fi

echo "Starting Plymouth daemon with GPS theme..."
plymouthd --mode=boot --theme=gps --debug --debug-file=/tmp/plymouth-debug.log || {
    # If GPS theme is not installed in /usr/share/plymouth/themes/gps, point to local directory
    plymouthd --mode=boot --debug --debug-file=/tmp/plymouth-debug.log
}

plymouth show-splash
sleep 1
plymouth message --text="GPS Desktop OS — Initializing"
sleep 1.5

for pct in 15 30 50 75 90 100; do
    plymouth update --status="Loading user services (${pct}%)..."
    sleep 0.5
done

sleep 1
plymouth quit
echo "Preview finished. Debug log written to /tmp/plymouth-debug.log"
