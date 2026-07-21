#!/bin/sh
set -eu

SKETCH_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PORT=${1:?usage: $0 /dev/tty.usbmodemXXXX}
FQBN='esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=8M,PartitionScheme=default_8MB,PSRAM=opi'

arduino-cli core install esp32:esp32@3.3.0
arduino-cli compile --clean --fqbn "$FQBN" "$SKETCH_DIR"
arduino-cli upload -p "$PORT" --fqbn "$FQBN" "$SKETCH_DIR"
