# Drive Pilot for PLEOS

<img width="1680" height="979" alt="Drive Pilot running on PLEOS" src="https://github.com/user-attachments/assets/15bc23cf-d538-44f1-b7ab-a0e2c88446d5" />

PLEOS Connect / Android Automotive OS 데모 워크스페이스입니다. 기본 앱인 `Drive Pilot`에 더해, Autoware 멀티모드 3D 뷰어와 PLEOS 재구성 검증 콘솔을 함께 제공합니다.

이 저장소의 현재 작업 브랜치:

```bash
git clone -b pleos-multimode-viewer https://github.com/hwkim3330/ploes.git
cd ploes
```

## 구성

| App / Tool | Path | Android component | Purpose |
| --- | --- | --- | --- |
| Drive Pilot | repo root | `com.example.mrm_multimodal_demo/.MainActivity` | PLEOS IVI 데모, 지도/주행/차량 상태 표시 |
| PLEOS Multimode | `apps/pleos_multimode` | `com.example.pleosmrmviewer/.MainActivity` | 3D 차량 기반 Autoware 센서 조합 전환, MRM 시각화 |
| PLEOS Reconfig | `apps/pleos_reconfig_console` | `com.example.pleosreconfig/.MainActivity` | TSN/Zonal 재구성, 고장 시나리오, CBOR fault injection 검증 |
| PLEOS Test Bench | `tools/pleos_controller.py` | local web `127.0.0.1:8765` | Mac에서 ADB로 앱 실행, 속도/기어/GPS/CBOR/MRM 시나리오 조작 |

## 주요 기능

- PLEOS / AAOS 차량 속성 읽기와 앱 내부 주행 상태 override
- Mac 웹 컨트롤러로 에뮬레이터 GPS, 속도, 기어, 루트 제어
- `roii.glb` 3D 차량 모델 기반 TSN 스위치/센서 라벨 표시
- 전방 TSN 스위치 2개, 후방 TSN 스위치 1개 구성
- LiDAR, GNSS, Camera 조합별 Autoware stack 전환
- 센서 고장, TSN/FRER/Zonal 고장, 복합 환경 저하, MRM safe stop 시나리오
- ADB broadcast 기반 CBOR fault payload 주입과 Flutter EventChannel 처리

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

루트 앱은 Android `MethodChannel('mrm.pilot/pleos')`를 통해 다음 bridge를 제공합니다.

| Method | Purpose |
| --- | --- |
| `getCapabilitySnapshot` | PLEOS capability/permission 상태 |
| `getVehicleSnapshot` | AAOS car property read bridge |
| `getControlSnapshot` | ADB broadcast override 상태 |
| `requestRoute` | demo route request stub |
| `speakStatus` | demo TTS stub |
| `startVoiceCommand` | demo STT stub |

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
