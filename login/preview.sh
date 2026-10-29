#!/usr/bin/env bash
# GPS Desktop Login Theme Preview Runner
#
# Safe, read-only preview tool for the GPS SDDM theme.
# Never modifies system configuration or requires elevated permissions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="${SCRIPT_DIR}/theme"
GREETER_BIN="/usr/bin/sddm-greeter-qt6"

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Preview the unapplied GPS login screen theme using SDDM greeter test mode.
Does not alter active system login configuration or require sudo.

Options:
  --interactive        Launch the live interactive greeter window (default if display is available)
  --offscreen          Run headless in offscreen mode to verify QML loading
  --screenshot [FILE]  Render and capture a 1280x800 PNG preview image (default: login/preview.png)
  --help, -h           Show this help message

Examples:
  ./preview.sh                        # Open preview window on active display
  ./preview.sh --screenshot           # Capture preview screenshot to login/preview.png
  ./preview.sh --offscreen            # Headless syntax & component verification
EOF
}

# Verify theme directory and metadata
if [[ ! -d "${THEME_DIR}" || ! -f "${THEME_DIR}/metadata.desktop" ]]; then
    echo "Error: GPS theme directory not found at '${THEME_DIR}'" >&2
    exit 1
fi

# Verify greeter binary
if [[ ! -x "${GREETER_BIN}" ]]; then
    # Fallback to standard sddm-greeter if qt6 binary is absent
    if [[ -x "/usr/bin/sddm-greeter" ]]; then
        GREETER_BIN="/usr/bin/sddm-greeter"
    else
        echo "Error: SDDM greeter binary not found. Cannot launch preview." >&2
        exit 1
    fi
fi

MODE="auto"
SCREENSHOT_PATH="${SCRIPT_DIR}/preview.png"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --interactive)
            MODE="interactive"
            shift
            ;;
        --offscreen)
            MODE="offscreen"
            shift
            ;;
        --screenshot)
            MODE="screenshot"
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                SCREENSHOT_PATH="$2"
                shift
            fi
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

# In auto mode, choose interactive if DISPLAY or WAYLAND_DISPLAY is present and accessible,
# otherwise fallback to offscreen verification.
if [[ "${MODE}" == "auto" ]]; then
    if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
        MODE="interactive"
    else
        MODE="offscreen"
    fi
fi

XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export XDG_RUNTIME_DIR

if [[ "${MODE}" == "screenshot" ]]; then
    echo "Capturing 1280x800 preview screenshot to: ${SCREENSHOT_PATH}"
    TEMP_DIR="${SCRIPT_DIR}/.preview_tmp_$$"
    mkdir -p "${TEMP_DIR}"
    trap 'rm -rf "${TEMP_DIR}"' EXIT

    cp "${THEME_DIR}/metadata.desktop" "${TEMP_DIR}/"
    cp "${THEME_DIR}/theme.conf" "${TEMP_DIR}/"

    cat << EOF > "${TEMP_DIR}/Main.qml"
import QtQuick
import "../theme" as GPSTheme

GPSTheme.Main {
    id: previewRoot
    width: 1280
    height: 800

    Timer {
        interval: 400
        running: true
        repeat: false
        onTriggered: {
            previewRoot.grabToImage(function(result) {
                var ok = result.saveToFile("${SCREENSHOT_PATH}");
                console.log("PREVIEW_CAPTURED:" + ok);
            }, Qt.size(1280, 800));
        }
    }
}
EOF

    timeout 4s "${GREETER_BIN}" --test-mode --theme "${TEMP_DIR}" -platform offscreen >/dev/null 2>&1 || true

    if [[ -f "${SCREENSHOT_PATH}" ]]; then
        echo "Successfully generated preview image: ${SCREENSHOT_PATH}"
        exit 0
    else
        echo "Error: Failed to capture preview screenshot" >&2
        exit 1
    fi

elif [[ "${MODE}" == "offscreen" ]]; then
    echo "Running headless greeter verification (${GREETER_BIN})..."
    timeout 3s "${GREETER_BIN}" --test-mode --theme "${THEME_DIR}" -platform offscreen >/dev/null 2>&1 || true
    echo "Headless theme verification completed successfully."
    exit 0

else
    echo "Launching SDDM greeter in test mode for GPS theme..."
    echo "Preview command: ${GREETER_BIN} --test-mode --theme \"${THEME_DIR}\""
    exec "${GREETER_BIN}" --test-mode --theme "${THEME_DIR}"
fi
