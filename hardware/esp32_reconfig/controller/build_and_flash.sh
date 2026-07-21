#!/bin/sh
set -eu

SKETCH_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SKETCH_DIR/../.." && pwd)
PANEL_CONF="$HOME/Documents/Arduino/libraries/ESP32_Display_Panel/esp_panel_board_supported_conf.h"
PORT=${1:-/dev/tty.usbmodem59580282341}
FQBN='esp32:esp32:waveshare_esp32_s3_touch_lcd_7:PSRAM=enabled,FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,UploadSpeed=115200'

arduino-cli core update-index
arduino-cli core install esp32:esp32@3.3.0
arduino-cli lib install ESP32_Display_Panel@1.0.0 ESP32_IO_Expander@1.0.1 esp-lib-utils@0.1.2 lvgl@8.4.0 EspUsbHost@2.4.0

sed -i.bak 's/^#define ESP_PANEL_BOARD_DEFAULT_USE_SUPPORTED       (0)/#define ESP_PANEL_BOARD_DEFAULT_USE_SUPPORTED       (1)/' "$PANEL_CONF"
sed -i.bak 's|^// #define BOARD_WAVESHARE_ESP32_S3_TOUCH_LCD_7|#define BOARD_WAVESHARE_ESP32_S3_TOUCH_LCD_7|' "$PANEL_CONF"

mkdir -p "$ROOT/build/esp32"
arduino-cli compile --clean --fqbn "$FQBN" --output-dir "$ROOT/build/esp32" "$SKETCH_DIR"
arduino-cli upload -p "$PORT" --fqbn "$FQBN" --input-dir "$ROOT/build/esp32"
