#!/usr/bin/env bash
set -euo pipefail

directory="${1:-${AIKE_FACE_MODELS_DIR:-$(cd "$(dirname "$0")/.." && pwd)/var/models}}"
base="https://github.com/opencv/opencv_zoo/raw/main/models"

models=(
  "face_detection_yunet/face_detection_yunet_2023mar.onnx 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"
  "face_recognition_sface/face_recognition_sface_2021dec.onnx 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"
)

mkdir -p "$directory"

for entry in "${models[@]}"; do
  read -r path sha256 <<< "$entry"
  target="$directory/$(basename "$path")"

  if [ -f "$target" ] && echo "$sha256  $target" | sha256sum --check --status; then
    echo "ok       $(basename "$path")"
    continue
  fi

  curl -fsSL --retry 3 -o "$target.part" "$base/$path"

  if ! echo "$sha256  $target.part" | sha256sum --check --status; then
    rm -f "$target.part"
    echo "SHA-256 mismatch for $(basename "$path"); refusing the file" >&2
    exit 1
  fi

  mv "$target.part" "$target"
  echo "fetched  $(basename "$path")"
done
