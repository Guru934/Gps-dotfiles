#!/usr/bin/env bash
set -euo pipefail

mode="${1:-chill}"
case "$mode" in
  study|gaming|chill|night) ;;
  *) printf 'unknown vibe: %s\n' "$mode" >&2; exit 2 ;;
esac

# Keep the selected profile available to other shell components. Integrations
# can consume this small state file without making the dashboard own hardware.
printf '%s\n' "$mode" > "${XDG_RUNTIME_DIR:-/tmp}/gps-vibe-mode"
