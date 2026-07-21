#!/bin/sh
set -eu

SKETCH_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT=${1:?usage: $0 /dev/tty.usbmodemXXXX A|B|R}
ROLE=${2:?usage: $0 /dev/tty.usbmodemXXXX A|B|R}
FQBN='esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=opi'

case "$ROLE" in
  A) INDEX=0 ;;
  B) INDEX=1 ;;
  R) INDEX=2 ;;
  *) echo "role must be A, B or R" >&2; exit 2 ;;
esac

arduino-cli core install esp32:esp32@3.3.0
arduino-cli compile --clean --fqbn "$FQBN" \
  --build-property "compiler.cpp.extra_flags=-DPLEOS_LINK_INDEX=$INDEX" "$SKETCH_DIR"
arduino-cli upload -p "$PORT" --fqbn "$FQBN" "$SKETCH_DIR"
