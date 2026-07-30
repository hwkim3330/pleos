# Prebuilt ESP32 firmware

Committed so the three boards can be flashed without installing the Arduino
toolchain. Built from the commit that added them; rebuild if the sketches change.

| Directory | Board | Sketch |
| --- | --- | --- |
| `esp32/` | Waveshare ESP32-S3-Touch-LCD-7 supervisor | `hardware/esp32_reconfig/controller` |
| `path1/` | LilyGO T-Display, `PLEOS_PATH_INDEX=0` (`PLEOS-PATH1`, `tsn_front_a`) | `hardware/esp32_reconfig/path_display_node` |
| `path2/` | LilyGO T-Display, `PLEOS_PATH_INDEX=1` (`PLEOS-PATH2`, `tsn_front_b`) | `hardware/esp32_reconfig/path_display_node` |

The path node builds keep only the flashable images; their `.elf`/`.map` were
dropped. The controller build keeps them because they are useful for decoding a
crash backtrace from the 7-inch.

## Flash

Path nodes — do not swap the two, the index is compiled in:

```bash
arduino-cli upload -p /dev/ttyACM2 \
  --fqbn 'esp32:esp32:esp32:FlashSize=4M,PartitionScheme=huge_app,UploadSpeed=460800' \
  --input-dir build/path1

arduino-cli upload -p /dev/ttyACM3 \
  --fqbn 'esp32:esp32:esp32:FlashSize=4M,PartitionScheme=huge_app,UploadSpeed=460800' \
  --input-dir build/path2
```

Controller:

```bash
arduino-cli upload -p /dev/ttyACM1 \
  --fqbn 'esp32:esp32:waveshare_esp32_s3_touch_lcd_7:PSRAM=enabled,FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,UploadSpeed=115200' \
  --input-dir build/esp32
```

Identify which port is which before flashing — the boards all enumerate as
`1A86:55xx` CH34x serial devices. The 7-inch controller emits framed CBOR
(`0xA5 0x5A` magic) on its UART; a path node prints
`!NODE:PLEOS_PATH_n:HEARTBEAT`. Note that opening any of these ports resets that
board.

Flutter build output is deliberately **not** committed: `apps/*/build` is about
2.4 GB and contains a 152 MB APK, past GitHub's 100 MB per-file hard limit.
