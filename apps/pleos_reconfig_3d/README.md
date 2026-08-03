# PLEOS Reconfig 3D (parked)

Native Android console: Kotlin, Jetpack Compose for the HMI, Google Filament for the
vehicle, and the platform Bluetooth API for the link to the 7-inch controller. No
Flutter, no WebView, no plugins.

**This app is parked.** The chosen direction for the demo is the light Flutter console
with the 3D model (`apps/pleos_reconfig_studio`). This is kept because it works and
because the notes below cost real time to find, not because it is on the roadmap.

```bash
cd apps/pleos_reconfig_3d
echo "sdk.dir=$HOME/Android/Sdk" > local.properties
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 ./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell pm grant com.keti.pleos.reconfig3d android.permission.BLUETOOTH_SCAN
adb shell pm grant com.keti.pleos.reconfig3d android.permission.BLUETOOTH_CONNECT
adb shell am start -n com.keti.pleos.reconfig3d/.MainActivity
```

Only one BLE client can own the controller at a time, so force-stop the other consoles
first (`com.keti.pleos.reconfig`, `com.keti.pleos.hmi`).

## What worked

- **BLE against the real rig.** Gateway link, snapshot sync, both path nodes ACK, live
  channel state and the event timeline all behaved the same as the Flutter apps.
- **Link state painted onto the model.** The asset has no useful node names, but its
  *materials* are named after the architecture, so the three commandable links resolve to
  material buckets: `tsn_front_a` → `Path1`, `connection-FrontZC-Path1-*`,
  `connection-Path1-RearZC-*`, `ESP_AR` (13 material instances); `tsn_front_b` the same
  through `Path2`/`ESP_BR` (13); `tsn_rear` → `ESP_AB`/`InlineESP` (1). Isolating a link
  turns its parts red on the vehicle itself.
- **38 MB debug APK** against the Flutter debug builds' ~146 MB.

## Four things that cost time, all of them silent

1. **`ModelViewer.loadModelGltf` throws the whole asset away if the resource callback
   returns null for any URI.** This asset is glTF JSON with its buffer and both images
   embedded as `data:...;base64` URIs, and returning null for them left an empty scene
   with no error logged anywhere — indistinguishable from a compositing bug. The callback
   has to decode them.
2. **A `SurfaceView` inside Compose is composited *below* the window,** so the panel's
   opaque background paints over it. What looks like a failed renderer is the Compose
   surface colour. `TextureView` is the one that composites inline.
3. **Material instances hang off `asset.instance`, not `asset`,** and Filament's Java
   `MaterialInstance` has setters but no getters — so a link's original colour has to be
   read out of the glTF JSON if a recovered link is to go back to what the model shipped
   with rather than a guess at neutral.
4. **Filament's default exposure is bright daylight** (f/16, 1/125, ISO 100). On a dark
   vehicle body on an indoor bench that renders as near-black.

## Known incomplete

- `setShellVisible(false)` is called at load to reveal the wiring, but the body shell was
  still visible in testing, so the entity lookup for `textured_meshobj` needs checking.
  The `BODY SHELL` toggle in the panel header is wired and unverified.
- Camera framing is a fixed 45 mm focal length. There is no reset-view control, so a
  dragged model stays dragged.
