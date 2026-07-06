# Drive Pilot for Pleos
<img width="1680" height="979" alt="image" src="https://github.com/user-attachments/assets/15bc23cf-d538-44f1-b7ab-a0e2c88446d5" />

Flutter 기반 Pleos Connect IVI 데모 앱입니다. 한 화면 안에서 OSM 네비게이션, 가상 센서 피드, Pleos/AAOS 차량 속성 읽기, 외부 ADB 컨트롤러 연동을 보여줍니다.

앱 표시 이름은 `Drive Pilot`이고 Android package/activity는 `com.example.mrm_multimodal_demo/.MainActivity`입니다.

## What This Demo Does

- OSM 기반 네비게이션 화면
- Pleos/AAOS 차량 속성 읽기
- 앱 내부 속도/GPS/주행 상태 override
- Mac 웹 컨트롤러로 에뮬레이터 GPS와 앱 시뮬레이션 제어
- ADB broadcast 기반 외부 앱/툴 연동
- Pleos SDK/API 권한 및 지원 상태 표시

## Requirements

- Flutter SDK
- Android SDK / ADB
- Pleos Connect Emulator 또는 Android Automotive Emulator
- Pleos Playground project, if testing SDK/API permissions or app review flow

Check connected devices:

```bash
adb devices
```

The examples below assume the emulator serial is `emulator-5554`.

## Quick Start

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start -n com.example.mrm_multimodal_demo/.MainActivity
```

Reinstall and launch in one shot:

```bash
flutter build apk --debug && \
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk && \
adb -s emulator-5554 shell am start -n com.example.mrm_multimodal_demo/.MainActivity
```

Stop the app:

```bash
adb -s emulator-5554 shell am force-stop com.example.mrm_multimodal_demo
```

Clear app data:

```bash
adb -s emulator-5554 shell pm clear com.example.mrm_multimodal_demo
```

Read logs:

```bash
adb -s emulator-5554 logcat | grep -E "mrm_multimodal_demo|DrivePilot|flutter"
```

## Mac Vehicle Controller

Run the local controller:

```bash
python3 tools/pleos_controller.py
open http://127.0.0.1:8765
```

Or double-click from Finder:

```bash
./tools/Pleos\ Vehicle\ Controller.command
```

The controller opens `http://127.0.0.1:8765` and exposes:

- `Set GPS`: sends emulator GPS and app location override
- `Set Speed`: sends app speed override
- `Drive/Park/Reverse`: sends AAOS driving state and app state override
- `Start Route`: starts a demo route with moving GPS and speed
- `Stop Route`: stops route, sends `speedKph=0`, and forces `park`

Controller HTTP endpoints:

```bash
curl "http://127.0.0.1:8765/api/status"
curl "http://127.0.0.1:8765/api/geo?lat=37.4018000&lon=127.1089500"
curl "http://127.0.0.1:8765/api/speed?kph=42"
curl "http://127.0.0.1:8765/api/drive?state=park"
curl "http://127.0.0.1:8765/api/drive?state=drive"
curl "http://127.0.0.1:8765/api/drive?state=reverse"
curl "http://127.0.0.1:8765/api/route/start?kph=45"
curl "http://127.0.0.1:8765/api/route/stop"
```

## Direct ADB Control: Drive Pilot App

The app listens to this broadcast receiver:

```text
com.example.mrm_multimodal_demo/.DrivePilotControlReceiver
```

Action:

```text
com.example.mrm_multimodal_demo.CONTROL
```

Required marker extra:

```text
--es drivepilot_source controller
```

Supported extras:

- `speedKph`: float, app simulation speed in km/h
- `lat`: double, app simulation latitude
- `lon`: double, app simulation longitude
- `driveState`: string, `park`, `drive`, `reverse`, or `neutral`

Set app speed only:

```bash
adb -s emulator-5554 shell am broadcast \
  -n com.example.mrm_multimodal_demo/.DrivePilotControlReceiver \
  -a com.example.mrm_multimodal_demo.CONTROL \
  --es drivepilot_source controller \
  --ef speedKph 42
```

Set app location only:

```bash
adb -s emulator-5554 shell am broadcast \
  -n com.example.mrm_multimodal_demo/.DrivePilotControlReceiver \
  -a com.example.mrm_multimodal_demo.CONTROL \
  --es drivepilot_source controller \
  --ed lat 37.4018000 \
  --ed lon 127.1089500
```

Set app speed, location, and state:

```bash
adb -s emulator-5554 shell am broadcast \
  -n com.example.mrm_multimodal_demo/.DrivePilotControlReceiver \
  -a com.example.mrm_multimodal_demo.CONTROL \
  --es drivepilot_source controller \
  --ef speedKph 42 \
  --ed lat 37.4018000 \
  --ed lon 127.1089500 \
  --es driveState drive
```

Force app stop state:

```bash
adb -s emulator-5554 shell am broadcast \
  -n com.example.mrm_multimodal_demo/.DrivePilotControlReceiver \
  -a com.example.mrm_multimodal_demo.CONTROL \
  --es drivepilot_source controller \
  --ef speedKph 0 \
  --es driveState park
```

Start activity with initial control extras:

```bash
adb -s emulator-5554 shell am start \
  -n com.example.mrm_multimodal_demo/.MainActivity \
  --es drivepilot_source controller \
  --ef speedKph 30 \
  --ed lat 37.4018000 \
  --ed lon 127.1089500 \
  --es driveState park
```

## Direct ADB Control: Emulator GPS

Move emulator GPS. Android emulator expects `lon lat altitude`.

```bash
adb -s emulator-5554 emu geo fix 127.1089500 37.4018000 5
adb -s emulator-5554 emu geo fix 127.1157800 37.4063600 5
```

Route points used by the controller:

```text
37.40180, 127.10895
37.40238, 127.10974
37.40294, 127.11104
37.40350, 127.11242
37.40432, 127.11328
37.40512, 127.11378
37.40592, 127.11464
37.40636, 127.11578
```

## Direct ADB Control: AAOS Car Service

Driving state:

```bash
adb -s emulator-5554 shell cmd car_service emulate-driving-state park
adb -s emulator-5554 shell cmd car_service emulate-driving-state drive
adb -s emulator-5554 shell cmd car_service emulate-driving-state reverse
adb -s emulator-5554 shell cmd car_service emulate-driving-state neutral
```

List car property configs:

```bash
adb -s emulator-5554 shell cmd car_service get-carpropertyconfig
```

Inspect one property config:

```bash
adb -s emulator-5554 shell cmd car_service get-carpropertyconfig 0x11600207
```

Read one property value:

```bash
adb -s emulator-5554 shell cmd car_service get-property-value 0x11600207 0
```

Try a VHAL event injection for test-only properties:

```bash
adb -s emulator-5554 shell cmd car_service inject-vhal-event 0x11600207 0 11.67
```

Try setting a property:

```bash
adb -s emulator-5554 shell cmd car_service set-property-value 0x11600207 0 11.67
```

Important: in Pleos/AAOS, third-party apps generally cannot write vehicle properties. If the command returns:

```text
Cannot set a property: android.os.ServiceSpecificException ... (code 4)
```

that property is read-only or not writable in the emulator image. This is expected for speed-like system cluster properties. Use the Drive Pilot broadcast override for demo speed instead.

Useful property IDs referenced by this app:

| Name | ID | Notes |
| --- | --- | --- |
| `PERF_VEHICLE_SPEED` | `0x11600207` | m/s, read from AAOS if available |
| `PERF_VEHICLE_SPEED_DISPLAY` | `0x11600208` | m/s, display speed |
| `PERF_ODOMETER` | `0x11600204` | km |
| `PERF_STEERING_ANGLE` | `0x11600209` | degrees |
| `GEAR_SELECTION` | `0x11400400` | selected gear |
| `CURRENT_GEAR` | `0x11400401` | current gear |
| `IGNITION_STATE` | `0x11400409` | ignition |
| `PARKING_BRAKE_ON` | `0x11200402` | boolean |
| `EV_BATTERY_LEVEL` | `0x11600309` | EV battery |
| `EV_CHARGE_PORT_CONNECTED` | `0x1120030b` | boolean |
| `EV_CHARGE_STATE` | `0x11400f41` | charge state |
| `RANGE_REMAINING` | `0x11600308` | range |
| `FUEL_LEVEL` | `0x11600307` | fuel |
| `TIRE_PRESSURE` | `0x17600309` | tire pressure |
| `ENV_OUTSIDE_TEMPERATURE` | `0x11600703` | outside temp |
| `TURN_SIGNAL_STATE` | `0x11400408` | turn signal |
| `HEADLIGHTS_STATE` | `0x11400e00` | headlights |
| `HAZARD_LIGHTS_STATE` | `0x11400e03` | hazards |
| `ABS_ACTIVE` | `0x1120040a` | ABS |
| `TRACTION_CONTROL_ACTIVE` | `0x1120040b` | traction control |
| `CRUISE_CONTROL_STATE` | `0x11401011` | cruise |
| `CRUISE_CONTROL_TARGET_SPEED` | `0x11601013` | cruise target |
| `ADAPTIVE_CRUISE_CONTROL_LEAD_VEHICLE_MEASURED_DISTANCE` | `0x11401015` | lead distance |
| `LANE_KEEP_ASSIST_STATE` | `0x11401009` | lane keep |
| `LANE_CENTERING_ASSIST_STATE` | `0x1140100c` | lane centering |
| `FORWARD_COLLISION_WARNING_STATE` | `0x11401003` | FCW |
| `AUTOMATIC_EMERGENCY_BRAKING_STATE` | `0x11401001` | AEB |
| `HANDS_ON_DETECTION_DRIVER_STATE` | `0x11401017` | hands-on detection |

## App Bridge

Flutter calls Android through:

```text
MethodChannel('mrm.pilot/pleos')
```

Implemented methods:

| Method | Purpose |
| --- | --- |
| `getCapabilitySnapshot` | Returns detected/declared Pleos capability status |
| `getVehicleSnapshot` | Reads AAOS car properties through `android.car.Car` reflection |
| `getControlSnapshot` | Returns latest ADB broadcast override |
| `requestRoute` | Demo stub for route request |
| `speakStatus` | Demo stub for TTS |
| `startVoiceCommand` | Demo stub for STT |

Broadcast receiver:

```xml
<receiver
    android:name=".DrivePilotControlReceiver"
    android:exported="true" />
```

## Pleos Permissions Declared

The Android manifest declares these Pleos permissions:

```xml
<uses-permission android:name="pleos.car.permission.CAR_ENERGY" />
<uses-permission android:name="pleos.car.permission.CAR_INFO" />
<uses-permission android:name="pleos.car.permission.NAVI_ROUTE" />
<uses-permission android:name="pleos.car.permission.NAVI_ROUTE_SEARCH" />
<uses-permission android:name="pleos.car.permission.NAVI_CUSTOM_MAP" />
<uses-permission android:name="pleos.car.permission.NAVI_CUSTOM_ROUTE" />
<uses-permission android:name="pleos.car.permission.NAVI_CUSTOM_ETC" />
<uses-permission android:name="pleos.car.permission.FUSED_LOCATION" />
<uses-permission android:name="pleos.car.permission.TTS_SERVICE" />
<uses-permission android:name="pleos.car.permission.STT_SERVICE" />
<uses-permission android:name="pleos.car.permission.LLM_SERVICE" />
```

The app currently checks declared permissions and displays capability state. Real SDK calls must still be wired with the official Pleos SDK artifacts and approved project permissions before app review.

## Pleos Connect SDK/API Map

Official Pleos Connect SDK modules:

| SDK/API | What it is for | Current demo status |
| --- | --- | --- |
| Vehicle SDK | vehicle status query and control | AAOS read bridge implemented; direct `set` avoided |
| NaviHelper SDK | control built-in Pleos navigation or request navigation information | permission declared; app currently uses OSM instead |
| Gleo AI SDK | STT, TTS, LLM features | permissions declared; demo stubs exist |
| ADAS SDK | driving-assist data such as objects, lanes, parking spaces | displayed as unavailable/demo |
| Fused Location SDK | vehicle location information | permission declared; emulator GPS/app override used |
| Fleet API | REST/Webhook fleet management API | documented as external cloud API |
| Vehicle Data API | connected car data API | documented as external cloud API |

Vehicle SDK domains named in the official docs:

```text
Brake
CarInfo
Display
Door
DrivingMode
EvBattery
HVAC
Light
Odometer
Safety
Seat
SideMirror
Steeringwheel
Tire
TurnSignal
Window
Wiper
```

Vehicle SDK usage pattern:

```kotlin
// Pseudocode. Wire the official SDK artifact before using this.
val vehicle = Vehicle(context)
vehicle.initialize()

val carInfo = vehicle.getCarInfo()
val capability = carInfo.checkCarInfoCapability()

vehicle.release()
```

NaviHelper APIs named in the official docs:

```text
initialize
release
addListener
removeListener
requestRoute
cancelRoute
requestReRoute
addWaypoint
removeWaypoint
changeRouteOption
getBookmarkInfo
getRecentDestinationInfo
getRouteStateInfo
getCurrentLocationInfo
getDestinationInfo
getWaypointInfo
getTBTInfo
getChargerOperatorInfo
```

NaviHelper target wiring for this app:

```kotlin
// Pseudocode. Replace the OSM-only route request with official NaviHelper when approved.
val naviHelper = NaviHelper(context)
naviHelper.initialize()
naviHelper.addListener(listener)
naviHelper.requestRoute(routeInfo)
naviHelper.getCurrentLocationInfo()
naviHelper.getTBTInfo()
naviHelper.release()
```

Gleo AI SDK groups and APIs named in the official docs:

```text
SpeechToText SDK
TextToSpeech SDK
LLM SDK
```

LLM APIs named in the official docs:

```text
initialize
release
generateContent
startChat
sendMessage
setModelParameter
registerApp
getOnDeviceModelPromptsContents
```

Fused Location APIs named in the official docs:

```text
initialize
release
registerFusedLocationCallback
unregisterFusedLocationCallback
```

Official compatibility notes from Pleos docs:

- SDK/API support can vary by vehicle model.
- Use each SDK interface's capability check API before relying on a feature.
- NaviHelper and Gleo AI are documented as fully compatible.
- Vehicle SDK may vary by model.
- ADAS and Fused Location were documented as not supported in the March 2026 compatibility guide.
- Third-party app developers can read supported AAOS vehicle properties but cannot write them with system authority.
- Pleos warns that direct `set*` SDK API calls can fail app review; use approved flows and app review guidance.

## Fleet API Skeleton

Do not commit real secrets. Use environment variables:

```bash
export FLEET_API_GATEWAY_HOST="https://<gateway-host>"
export FLEET_API_HOST="https://<fleet-api-host>"
export PLEOS_PROJECT_ID="<project-id>"
export PLEOS_CLIENT_ID="<client-id>"
export PLEOS_CLIENT_SECRET="<client-secret>"
```

Request a token:

```bash
curl -X POST "$FLEET_API_GATEWAY_HOST/auth/client/token" \
  -H "Content-Type: application/json" \
  -d "{
    \"client_id\": \"$PLEOS_CLIENT_ID\",
    \"secret\": \"$PLEOS_CLIENT_SECRET\",
    \"identifier\": \"$PLEOS_PROJECT_ID\",
    \"regenerate_token\": false
  }"
```

Call Fleet API with the issued token:

```bash
export PLEOS_ACCESS_TOKEN="<access-token>"

curl -X GET "$FLEET_API_HOST/developers/api/vehicles?page=1&size=20" \
  -H "x-42dot-client-id: Bearer $PLEOS_ACCESS_TOKEN"
```

## CRN / Devbox Setup

Do not commit the real CRN. Store it locally:

```bash
echo "<your-crn>" > ~/.pleos-connect-crn
```

Inject CRN into Devbox/emulator when required by Pleos setup:

```bash
CRN="$(cat ~/.pleos-connect-crn)"
adb -s emulator-5554 root
adb -s emulator-5554 shell su 0 "echo 'propId: 554696961 areaId: 0 values: $CRN' > /data/vendor/vsomeip/vhal_fifo"
adb -s emulator-5554 reboot
```

## Known Limits

- The Pleos system cluster/left vehicle UI is system-owned. This demo does not control that UI directly.
- Speed-like AAOS properties can be read-only. Use app broadcast override for demo speed.
- OSM public tiles are fine for development but not for production traffic. Use a proper tile provider before release.
- Pleos SDK permissions must be approved/synced in Pleos Playground and App Market Console before review.
- Real Client Secret, Project ID, CRN, and access tokens must not be committed to Git.

## Official References

- Pleos Connect SDK Overview: https://document.pleos.ai/en/api-reference/connect-sdk-pleos/
- Pleos API Compatibility & Availability: https://document.pleos.ai/en/docs/pleos-only/vehicle-app-planning-guide/api-compatibility-availability
- Pleos Develop page: https://pleos.ai/playground/develop?focus=fleet_api
- Fleet API Getting Started: https://document.pleos.ai/en/api-reference/fleet-api/getting-started
- Android VehiclePropertyIds: https://developer.android.com/reference/android/car/VehiclePropertyIds
