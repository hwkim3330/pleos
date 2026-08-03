# PLEOS Reconfig Studio

ROII 3D vehicle architecture, Autoware sensor multimode and ESP32 inline fault-injection hardware are integrated in one PLEOS app.

`tools/build_reconfig_model.py` generates `roii_reconfig.glb` from the original ROII asset. It preserves the native split FrontZC, Path1/Path2 and connection meshes, and adds only the ESP-AB/AR/BR enclosures.

```bash
python3 tools/build_reconfig_model.py \
  apps/pleos_reconfig_console/lib/assets/roii.glb \
  apps/pleos_reconfig_studio/lib/assets/roii_reconfig.glb
```


## The 3D is native, not a WebView

The vehicle is rendered by Google Filament in the Android host through a Flutter platform
view (`lib/screens/widgets/native_vehicle_view.dart` ->
`android/.../VehicleViewFactory.kt`). It used to be `model_viewer_plus`, which is
model-viewer JS running in an Android WebView.

Measured on the tablet, same app, same BLE link, 35 s after launch:

| | WebView (model-viewer) | Native (Filament) |
| --- | --- | --- |
| TOTAL PSS | 521 MB | 462 MB |
| Extra process | Chromium sandbox, +183 MB, 18-27% CPU | none |
| App CPU at rest | 35% | ~0-10% |
| Frame 90th / 95th | 150 ms / 200 ms | 32 ms / 34 ms |
| Janky frames (legacy) | 31% | 6% |

The in-process memory barely moved -- most of it is the Flutter debug engine and the
graphics buffers -- but the separate 183 MB Chromium process is gone and CPU at rest fell
from about 60% across two processes to under 10% in one. Dart was never the cost; the
renderer was.

Rendering is on demand: a frame is drawn when the link state, the shell slider or a drag
changes something. An unconditional per-frame Choreographer callback held a core at ~55%
on a scene that is static most of the time.

### Making it look like the WebView did

model-viewer ships a neutral environment map and lights the model with it. Filament with
only directional lights has no ambient term at all, and 82 of this asset's 110 materials
are metallic 0.5 -- a metal has no diffuse response, so half their albedo simply
disappears and everything reads dark and flat. That, not the renderer, was why the WebView
looked better. Three things closed the gap:

* an `IndirectLight` with band-0 (uniform) radiance, which puts the ambient term back
* 4x MSAA and screen-space ambient occlusion, for the edges and the contact shading that
  model-viewer got from its drop shadow
* the body shell dropped from metallic 1.0 to 0.15 in the asset, because a full metal with
  no reflections cubemap can only ever be flat grey -- and a translucent shell has no
  reason to read as polished metal

Only band 0 is used for the ambient: higher bands would add a sky-to-floor gradient, but
SH sign conventions differ between references and getting band 1 wrong lights the vehicle
from underneath. A real prefiltered IBL would be better still, and needs a `cmgen`-built
`.ktx` -- `IBLPrefilter` is not in this version of filament-utils, and hand-building a
cubemap through the 3D-region upload path was rejected by Filament's size validation even
with a correctly sized buffer.

`tools/build_native_vehicle_asset.py` prepares the asset. The Flutter copy is glTF JSON
with its buffer and images inlined as base64, so it is repacked as a real binary glb (3.67
-> 2.78 MB) into the Android assets, and the body material is switched to `alphaMode
BLEND`. That second change is what makes the shell slider work at all: gltfio bakes
blending into the material variant it picks and `MaterialInstance` cannot change it later,
so an OPAQUE body ignores whatever alpha is set on it.

### Not carried over

The 3D label hotspots were anchored by the model-viewer JS, and reprojecting entity
positions into Flutter overlays is separate work, so the `Show Labels` control is gone
rather than left on screen doing nothing. Sensor and switch alert targets *are* carried
over: the fault provider now pushes the whole `{target: severity}` map to the host, which
owns the target-to-material mapping.

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
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start \
  -n com.keti.pleos.reconfig/com.hwkim3330.pleosreconfigstudio.MainActivity
```

The applicationId (`com.keti.pleos.reconfig`) deliberately differs from the
Kotlin namespace so this build installs alongside a copy signed with a different
debug keystore instead of failing with INSTALL_FAILED_UPDATE_INCOMPATIBLE. That
is why the launch command needs the fully qualified activity class.

The emulator reaches the Mac bridge at `ws://10.0.2.2:8766`. The model rotates only when dragged and supports pinch/wheel zoom; automatic rotation is disabled. `Safe bypass` means no USB inline injector is armed. Physical relay actuation is disabled by default and must remain disabled until the normally-closed relay PCB and watchdog behavior are verified.
