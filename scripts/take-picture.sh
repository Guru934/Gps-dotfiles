#!/usr/bin/env bash
set -euo pipefail

camera_device="${CAMERA_DEVICE:-/dev/video0}"
picture_dir="${PICTURE_DIR:-$HOME/Pictures/Camera}"
timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
picture_path="$picture_dir/photo-$timestamp.jpg"

if [[ ! -e "$camera_device" ]]; then
    printf 'Camera device not found: %s\n' "$camera_device" >&2
    exit 1
fi

mkdir -p "$picture_dir"

ffmpeg -hide_banner -loglevel error \
    -f v4l2 \
    -input_format mjpeg \
    -video_size 1280x720 \
    -i "$camera_device" \
    -frames:v 1 \
    -q:v 2 \
    "$picture_path"

printf '%s\n' "$picture_path"
