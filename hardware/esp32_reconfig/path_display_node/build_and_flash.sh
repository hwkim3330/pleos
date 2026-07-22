#!/bin/sh
set -eu

SKETCH_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT=${1:?usage: $0 /dev/cu.usbserial-XXXX PATH1|PATH2|PATH3}
ROLE=${2:?usage: $0 /dev/cu.usbserial-XXXX PATH1|PATH2|PATH3}
FQBN='esp32:esp32:esp32:FlashSize=4M,PartitionScheme=huge_app,UploadSpeed=460800'

case "$ROLE" in
  PATH1) INDEX=0 ;;
  PATH2) INDEX=1 ;;
  PATH3) INDEX=2 ;;
  *) echo "role must be PATH1, PATH2, or PATH3" >&2; exit 2 ;;
esac

arduino-cli core install esp32:esp32@3.3.0
arduino-cli lib install "Adafruit GFX Library@1.12.6" "Adafruit ST7735 and ST7789 Library@1.11.0"
arduino-cli compile --clean --fqbn "$FQBN" \
  --build-property "compiler.cpp.extra_flags=-DPLEOS_PATH_INDEX=$INDEX" "$SKETCH_DIR"
arduino-cli upload -p "$PORT" --fqbn "$FQBN" "$SKETCH_DIR"
