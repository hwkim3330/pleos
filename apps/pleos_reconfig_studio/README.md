# PLEOS Reconfig Studio

ROII 3D vehicle architecture, Autoware sensor multimode and ESP32 inline fault-injection hardware are integrated in one PLEOS app.

`tools/build_reconfig_model.py` generates `roii_reconfig.glb` from the original ROII asset. The blue/teal switch links and ESP-AB/AR/BR enclosures are real model meshes, not screen overlays.

```bash
python3 tools/build_reconfig_model.py \
  apps/pleos_reconfig_console/lib/assets/roii.glb \
  apps/pleos_reconfig_studio/lib/assets/roii_reconfig.glb
```

## Run

Start the hardware bridge from the repository root:

```bash
./hardware/esp32_reconfig/bridge/run.sh --serial /dev/tty.usbmodem59580282341
```

Build, install and launch:

```bash
cd apps/pleos_reconfig_studio
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start \
  -n com.hwkim3330.pleosreconfigstudio/.MainActivity
```

The emulator reaches the Mac bridge at `ws://10.0.2.2:8766`. The model rotates only when dragged and supports pinch/wheel zoom; automatic rotation is disabled. `Safe bypass` means no USB inline injector is armed. Physical relay actuation is disabled by default and must remain disabled until the normally-closed relay PCB and watchdog behavior are verified.
