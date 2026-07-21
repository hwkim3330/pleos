# Drive Pilot for PLEOS

<img width="1680" height="979" alt="Drive Pilot running on PLEOS" src="https://github.com/user-attachments/assets/15bc23cf-d538-44f1-b7ab-a0e2c88446d5" />

PLEOS Connect / Android Automotive OS 데모 워크스페이스입니다. 기본 앱인 `Drive Pilot`에 더해, Autoware 멀티모드 3D 뷰어와 PLEOS 재구성 검증 콘솔을 함께 제공합니다.

이 저장소의 현재 작업 브랜치:

```bash
git clone -b pleos-multimode-viewer https://github.com/hwkim3330/pleos.git
cd pleos
```

## 구성

| App / Tool | Path | Android component | Purpose |
| --- | --- | --- | --- |
| Drive Pilot | repo root | `com.example.mrm_multimodal_demo/.MainActivity` | PLEOS IVI 데모, 지도/주행/차량 상태 표시 |
| PLEOS Multimode | `apps/pleos_multimode` | `com.example.pleosmrmviewer/.MainActivity` | 3D 차량 기반 Autoware 센서 조합 전환, MRM 시각화 |
| PLEOS Reconfig | `apps/pleos_reconfig_console` | `com.example.pleosreconfig/.MainActivity` | TSN/Zonal 재구성, 고장 시나리오, CBOR fault injection 검증 |
| PLEOS Reconfig Studio | `apps/pleos_reconfig_studio` | `com.hwkim3330.pleosreconfigstudio/.MainActivity` | ROII 기반 Inline ESP/TSN 경로 재구성 및 Autoware 멀티모드 검증 |
| PLEOS Test Bench | `tools/pleos_controller.py` | local web `127.0.0.1:8765` | Mac에서 ADB로 앱 실행, 속도/기어/GPS/CBOR/MRM 시나리오 조작 |

## 버전 정보

이 표는 2026-07-06 현재 `PLEOS Multimode`와 `PLEOS Reconfig` 기준으로 확인한 개발/실행 버전입니다. 두 앱 모두 Dart SDK constraint는 `^3.9.2`이고, `pubspec.lock`이 포함되어 있으므로 재현이 필요하면 `flutter pub upgrade`보다 `flutter pub get`을 먼저 사용합니다.

### 개발 환경

| 항목 | 현재 확인값 / 권장값 | 확인 위치 / 명령 | 비고 |
| --- | --- | --- | --- |
| macOS | `macOS 26.5 25F71 darwin-arm64` | `flutter doctor -v` | 현재 작업 Mac 기준 |
| Flutter | `3.41.6 stable` | `flutter --version` | 설치 경로: `/opt/homebrew/share/flutter` |
| Dart | `3.11.4` | `dart --version` | Multimode/Reconfig constraint: `^3.9.2`, lock: `>=3.9.2 <4.0.0` |
| Flutter DevTools | `2.54.2` | `flutter --version` | Flutter SDK에 포함 |
| Java / JDK | OpenJDK `17` 권장 | `java -version` | 기본 `/usr/bin/java`는 버전 확인 실패 가능. 아래 `JAVA_HOME` export 사용 |
| Android SDK | SDK `35.0.0`, platform `android-36` 설치 | `flutter doctor -v` | SDK 경로: `/Users/parksik/Library/Android/sdk` |
| Android Emulator | `36.6.11.0` | `flutter doctor -v` | PLEOS AVD 실행에 사용 |
| PLEOS AVD | `Pleos_Connect_v2` | `~/Library/Android/sdk/emulator/emulator -list-avds` | 실행 예시는 아래 빠른 실행 참고 |
| 테스트 에뮬레이터 | Android 14 API 34, `emulator-5554` | `adb devices`, `flutter doctor -v` | `Car on arm64 emulator`로 인식 |
| Gradle wrapper | `8.12` | `apps/*/android/gradle/wrapper/gradle-wrapper.properties` | Multimode/Reconfig 동일 |
| Android Gradle Plugin | `8.9.1` | `apps/*/android/settings.gradle.kts` | Multimode/Reconfig 동일 |
| Kotlin Android plugin | `2.1.0` | `apps/*/android/settings.gradle.kts` | Android bridge/receiver에 사용 |
| Chrome | `149.0.7827.201` | `flutter doctor -v` | Flutter Web / local Test Bench 확인용 |
| npm / Node | 사용 안 함 | `package.json` 없음 | Test Bench는 Python 표준 라이브러리 기반 |

### Multimode / Reconfig SDK 설정

| App | Path | Dart SDK constraint | Flutter SDK constraint from lock | Android namespace | applicationId | App version |
| --- | --- | --- | --- | --- | --- | --- |
| PLEOS Multimode | `apps/pleos_multimode` | `^3.9.2` | `>=3.35.0` | `com.example.pleosmrmviewer` | `com.example.pleosmrmviewer` | `1.0.0+1` |
| PLEOS Reconfig | `apps/pleos_reconfig_console` | `^3.9.2` | `>=3.35.0` | `com.example.pleosreconfig` | `com.example.pleosreconfig` | `1.0.0+1` |

### Multimode / Reconfig 주요 라이브러리

| 라이브러리 | 선언 버전 | lock 버전 | 사용 앱 | 용도 |
| --- | --- | --- | --- | --- |
| `cupertino_icons` | `^1.0.8` | `1.0.8` | Multimode, Reconfig | 기본 아이콘 |
| `model_viewer_plus` | `^1.9.3` | `1.9.3` | Multimode, Reconfig | `roii.glb` 3D 차량 모델 표시 |
| `webview_flutter` | `^4.13.0` | `4.13.0` | Multimode, Reconfig | Android WebView 기반 3D/model-viewer 표시 |
| `webview_flutter_android` | transitive | `4.10.2` | Multimode, Reconfig | Android WebView 구현체 |
| `webview_flutter_platform_interface` | transitive | `2.14.0` | Multimode, Reconfig | WebView platform interface |
| `webview_flutter_wkwebview` | transitive | `3.23.1` | Multimode, Reconfig | iOS/macOS WebView 구현체 |
| `animations` | `^2.1.0` | `2.1.0` | Multimode, Reconfig | 패널/상태 전환 애니메이션 |
| `flutter_riverpod` | `^2.5.1` | `2.6.1` | Multimode, Reconfig | 상태 관리 |
| `freezed_annotation` | `^2.4.1` | `2.4.4` | Multimode, Reconfig | immutable state model annotation |
| `json_annotation` | `^4.8.1` | `4.9.0` | Multimode, Reconfig | JSON model annotation |
| `fl_chart` | `^1.2.0` | `1.2.0` | Multimode, Reconfig | 점수/상태 차트 |

### Multimode / Reconfig 개발 의존성

| 라이브러리 | 선언 버전 | lock 버전 | 사용 앱 | 용도 |
| --- | --- | --- | --- | --- |
| `flutter_lints` | `^5.0.0` | `5.0.0` | Multimode, Reconfig | 정적 분석 규칙 |
| `freezed` | `^2.4.7` | `2.5.8` | Multimode, Reconfig | state/model code generation |
| `build_runner` | `^2.4.8` | `2.5.4` | Multimode, Reconfig | code generation runner |
| `json_serializable` | `^6.7.1` | `6.9.5` | Multimode, Reconfig | JSON serializer generation |

### 네이티브 / 외부 연동

| 항목 | 버전 / 식별자 | 위치 | 용도 |
| --- | --- | --- | --- |
| `roii.glb` | repo asset | `apps/pleos_multimode/lib/assets/roii.glb`, `apps/pleos_reconfig_console/lib/assets/roii.glb` | 3D 차량 모델 |
| CBOR broadcast action | `com.pleos.SIMULATE_CBOR` | `CborFaultService.kt` | 센서/TSN/Zonal/MRM fault payload 주입 |
| Drive Pilot control action | `com.example.mrm_multimodal_demo.CONTROL` | `DrivePilotControlReceiver` | 속도/GPS/주행 상태 override |
| PLEOS Maven repository | `https://nexus-playground.pleos.ai/repository/maven-releases/` | Multimode/Reconfig `settings.gradle.kts` | PLEOS SDK 연동 대비 repository |
| Flutter storage Maven | `https://storage.googleapis.com/download.flutter.io` | Multimode/Reconfig `settings.gradle.kts` | Flutter Android artifacts |
| Test Bench server | Python 3 standard library | `tools/pleos_controller.py` | `127.0.0.1:8765` 로컬 제어 UI |

## 주요 기능

- PLEOS / AAOS 차량 속성 읽기와 앱 내부 주행 상태 override
- Mac 웹 컨트롤러로 에뮬레이터 GPS, 속도, 기어, 루트 제어
- `roii.glb` 3D 차량 모델 기반 TSN 스위치/센서 라벨 표시
- 전방 TSN 스위치 2개, 후방 TSN 스위치 1개 구성
- LiDAR, GNSS, Camera 조합별 Autoware stack 전환
- 센서 고장, TSN/FRER/Zonal 고장, 복합 환경 저하, MRM safe stop 시나리오
- ADB broadcast 기반 CBOR fault payload 주입과 Flutter EventChannel 처리
- 7인치 ESP 중앙 컨트롤러 및 USB 스위치 I/O 노드 실시간 연동
- `hardware/esp32_reconfig`의 Supervisor, Inline Injector, I/O Node 펌웨어와 fail-safe 배선 계약

## 빠른 실행

### 1. PLEOS 에뮬레이터 시작

```bash
adb kill-server
adb start-server
rm -f ~/.android/avd/Pleos_Connect_v2.avd/*.lock ~/.android/avd/Pleos_Connect_v2.avd/multiinstance.lock
~/Library/Android/sdk/emulator/emulator -avd Pleos_Connect_v2 -no-snapshot-load
```

다른 터미널에서 부팅 완료를 확인합니다.

```bash
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
adb devices
```

`emulator-5554    device`가 보이면 준비된 상태입니다.

### 2. Test Bench 실행

```bash
python3 tools/pleos_controller.py
open http://127.0.0.1:8765
```

Finder에서 바로 켜려면:

```bash
./tools/Pleos\ Vehicle\ Controller.command
```

Test Bench에서 할 수 있는 일:

- `Drive Pilot`, `PLEOS Multimode`, `PLEOS Reconfig` 앱 실행
- 속도, 기어, GPS, 데모 루트 제어
- Baseline, Drive Validation, Sensor Degradation, TSN/Zonal Reconfiguration, MRM Safe Stop, Recovery Reset 런북 실행
- CBOR fault preset 확인/전송
- raw CBOR hex 직접 전송

### 3. 앱 직접 실행

```bash
# Drive Pilot
adb -s emulator-5554 shell am start -n com.example.mrm_multimodal_demo/.MainActivity

# PLEOS Multimode
adb -s emulator-5554 shell am start -n com.example.pleosmrmviewer/.MainActivity

# PLEOS Reconfig
adb -s emulator-5554 shell am start -n com.example.pleosreconfig/.MainActivity

# PLEOS Reconfig Studio
adb -s emulator-5554 shell am start -n com.hwkim3330.pleosreconfigstudio/.MainActivity
```

## 빌드와 테스트

OpenJDK 17을 사용합니다.

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
```

루트 Drive Pilot:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

PLEOS Multimode:

```bash
cd apps/pleos_multimode
flutter pub get
flutter analyze
flutter test
flutter run -d emulator-5554 --debug --no-resident
```

PLEOS Reconfig:

```bash
cd apps/pleos_reconfig_console
flutter pub get
flutter analyze
flutter test
flutter run -d emulator-5554 --debug --no-resident
```

### 실물 ESP 연동 실행 순서

`PLEOS Reconfig`가 ROII 모델을 사용하는 재구성 과제 앱입니다. 7인치 ESP의 CBOR 브리지를 먼저 실행한 다음 앱을 시작합니다.

```bash
# ioniq 저장소에서 실행
./tools/esp_bridge/run.sh --serial /dev/tty.usbmodem59580282341

# 이 저장소에서 실행
cd apps/pleos_reconfig_console
flutter run -d emulator-5554 --debug --no-resident
```

앱은 에뮬레이터에서 `ws://10.0.2.2:8766`으로 Mac 브리지에 접속합니다. 상단 `Controller`는 7인치 중앙 ESP, `Switch I/O`는 중앙 보드의 USB에 연결된 보조 ESP 상태를 뜻합니다. 보조 노드가 없으면 `Simulation`으로 표시되며 터치/앱 시나리오는 계속 사용할 수 있습니다.

## CBOR Fault Injection

CBOR은 `Concise Binary Object Representation`입니다. 이 프로젝트에서는 네이티브 Android 쪽에서 hex payload를 받아 `{action, id, code, target, severity}` 형태로 변환한 뒤 Flutter fault provider로 전달합니다.

ADB broadcast action:

```text
com.pleos.SIMULATE_CBOR
```

예시:

```bash
adb -s emulator-5554 shell am broadcast \
  -a com.pleos.SIMULATE_CBOR \
  --es cbor_hex A566616374696F6E016269640364636F64651867667461726765747046726F6E7443656E7465724C6964617268736576657269747901
```

Test Bench HTTP endpoints:

```bash
curl "http://127.0.0.1:8765/api/status"
curl "http://127.0.0.1:8765/api/open?app=reconfig"
curl "http://127.0.0.1:8765/api/speed?kph=30"
curl "http://127.0.0.1:8765/api/drive?state=drive"
curl "http://127.0.0.1:8765/api/route/start?kph=30"
curl "http://127.0.0.1:8765/api/fault?name=front-lidar-degraded"
curl "http://127.0.0.1:8765/api/fault?name=rear-zc-warning"
curl "http://127.0.0.1:8765/api/fault?name=mrm-stop"
curl "http://127.0.0.1:8765/api/fault?name=clear-lidar"
curl "http://127.0.0.1:8765/api/fault?name=clear-mrm"
```

## Drive Pilot Override Broadcast

Drive Pilot은 아래 receiver로 외부 제어 값을 받습니다.

```text
com.example.mrm_multimodal_demo/.DrivePilotControlReceiver
```

Action:

```text
com.example.mrm_multimodal_demo.CONTROL
```

지원 extras:

| Extra | Type | Meaning |
| --- | --- | --- |
| `drivepilot_source` | string | `controller`일 때만 적용 |
| `speedKph` | float | 앱 시뮬레이션 속도 |
| `lat` | double | 앱 시뮬레이션 위도 |
| `lon` | double | 앱 시뮬레이션 경도 |
| `driveState` | string | `park`, `drive`, `reverse`, `neutral` |

예시:

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

## AAOS / PLEOS 참고

차량 속도 같은 시스템 property는 emulator image에서 read-only일 수 있습니다. 직접 `set-property-value`가 실패하면 정상입니다. 데모 속도는 Drive Pilot broadcast override를 사용합니다.

자주 확인하는 명령:

```bash
adb -s emulator-5554 shell cmd car_service emulate-driving-state drive
adb -s emulator-5554 shell cmd car_service emulate-driving-state park
adb -s emulator-5554 shell cmd car_service get-carpropertyconfig
adb -s emulator-5554 shell cmd car_service get-property-value 0x11600207 0
```

에뮬레이터 GPS를 직접 이동할 수도 있습니다. Android emulator는 `lon lat altitude` 순서를 사용합니다.

```bash
adb -s emulator-5554 emu geo fix 127.1089500 37.4018000 5
adb -s emulator-5554 emu geo fix 127.1157800 37.4063600 5
```

Test Bench 데모 루트:

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

읽기 확인용 car property:

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

루트 앱은 Android `MethodChannel('mrm.pilot/pleos')`를 통해 다음 bridge를 제공합니다.

| Method | Purpose |
| --- | --- |
| `getCapabilitySnapshot` | PLEOS capability/permission 상태 |
| `getVehicleSnapshot` | AAOS car property read bridge |
| `getControlSnapshot` | ADB broadcast override 상태 |
| `requestRoute` | demo route request stub |
| `speakStatus` | demo TTS stub |
| `startVoiceCommand` | demo STT stub |

Android receiver:

```xml
<receiver
    android:name=".DrivePilotControlReceiver"
    android:exported="true" />
```

## PLEOS 권한과 SDK/API Map

루트 앱 manifest는 PLEOS 권한을 선언하고, 앱 화면에서 capability 상태를 표시합니다. 실제 SDK 호출은 Playground/App Market Console 승인 상태와 공식 SDK artifact 연결이 필요합니다.

선언 권한:

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

SDK/API 대응:

| SDK/API | What it is for | Current demo status |
| --- | --- | --- |
| Vehicle SDK | vehicle status query and control | AAOS read bridge implemented; direct `set` avoided |
| NaviHelper SDK | built-in PLEOS navigation and route information | permission declared; demo uses OSM route surface |
| Gleo AI SDK | STT, TTS, LLM features | permissions declared; demo stubs exist |
| ADAS SDK | driving-assist data such as objects, lanes, parking spaces | displayed as unavailable/demo |
| Fused Location SDK | vehicle location information | permission declared; emulator GPS/app override used |
| Fleet API | REST/Webhook fleet management API | documented as external cloud API |
| Vehicle Data API | connected car data API | documented as external cloud API |

Vehicle SDK domains referenced by PLEOS docs:

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

Vehicle SDK wiring target:

```kotlin
// Pseudocode. Wire the official SDK artifact before using this.
val vehicle = Vehicle(context)
vehicle.initialize()

val carInfo = vehicle.getCarInfo()
val capability = carInfo.checkCarInfoCapability()

vehicle.release()
```

NaviHelper APIs referenced by PLEOS docs:

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

NaviHelper wiring target:

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

Gleo AI SDK groups:

```text
SpeechToText SDK
TextToSpeech SDK
LLM SDK
```

LLM APIs referenced by PLEOS docs:

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

Fused Location APIs:

```text
initialize
release
registerFusedLocationCallback
unregisterFusedLocationCallback
```

Compatibility notes:

- SDK/API support can vary by vehicle model.
- Use each SDK interface's capability check API before relying on a feature.
- NaviHelper and Gleo AI are documented as fully compatible.
- Vehicle SDK may vary by model.
- Third-party app developers can read supported AAOS vehicle properties but cannot write them with system authority.
- Direct `set*` SDK API calls can fail review if they bypass approved flows.

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

Inject CRN into Devbox/emulator when required by PLEOS setup:

```bash
CRN="$(cat ~/.pleos-connect-crn)"
adb -s emulator-5554 root
adb -s emulator-5554 shell su 0 "echo 'propId: 554696961 areaId: 0 values: $CRN' > /data/vendor/vsomeip/vhal_fifo"
adb -s emulator-5554 reboot
```

## 문서

- [PLEOS Multimode README](apps/pleos_multimode/README.md)
- [PLEOS Reconfig README](apps/pleos_reconfig_console/README.md)
- [Reconfig app plan](docs/pleos_reconfig_app_plan.md)
- [Multimode CBOR testing](apps/pleos_multimode/cbor_testing.md)
- [Reconfig CBOR testing](apps/pleos_reconfig_console/cbor_testing.md)

## 문제 해결

에뮬레이터가 `adb devices`에 안 보일 때:

```bash
adb kill-server
adb start-server
adb devices
```

Java Runtime 오류:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
java -version
```

PLEOS 매니저/영상 팝업이 앱을 덮을 때:

- 팝업 왼쪽 위 `X`를 눌러 닫습니다.
- 앱을 다시 앞으로 보내려면 `adb shell am start -n ...` 명령을 다시 실행합니다.

로그:

```bash
adb -s emulator-5554 logcat | grep -E "mrm_multimodal_demo|pleosmrmviewer|pleosreconfig|flutter|WebView"
```

## 주의

- 실제 Fleet API token, Project ID, Client Secret, CRN은 커밋하지 않습니다.
- PLEOS SDK 권한은 Playground/App Market Console 승인 상태에 따라 달라질 수 있습니다.
- OSM public tile은 개발용으로만 사용하고, 배포 전에는 별도 tile provider를 설정합니다.

## References

- [PLEOS Connect SDK Overview](https://document.pleos.ai/en/api-reference/connect-sdk-pleos/)
- [PLEOS API Compatibility & Availability](https://document.pleos.ai/en/docs/pleos-only/vehicle-app-planning-guide/api-compatibility-availability)
- [PLEOS Develop](https://pleos.ai/playground/develop?focus=fleet_api)
- [Android VehiclePropertyIds](https://developer.android.com/reference/android/car/VehiclePropertyIds)
