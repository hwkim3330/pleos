# Drive Pilot for Pleos

Flutter 기반 Pleos Connect IVI 데모 앱입니다. 한 화면 안에서 OSM 네비게이션, 가상 센서 피드, Pleos/AAOS 차량 속성 읽기, 외부 ADB 컨트롤러 연동을 보여줍니다.

앱 표시 이름은 `Drive Pilot`이고 Android 패키지는 현재 `com.example.mrm_multimodal_demo`입니다.

## Features

- OSM 기반 네비게이션 화면
- 주행 모드/이벤트 시뮬레이션
- Android Automotive/Pleos 차량 속성 읽기 브리지
- Mac 컨트롤러 웹 UI로 앱의 속도, GPS, 주행 상태 override
- ADB broadcast 기반 외부 제어

## Requirements

- Flutter SDK
- Android SDK / ADB
- Pleos Connect emulator 또는 Android Automotive emulator

## Install and Run

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start -n com.example.mrm_multimodal_demo/.MainActivity
```

If the emulator serial is different, check it first:

```bash
adb devices
```

## Mac Vehicle Controller

Run the local controller:

```bash
python3 tools/pleos_controller.py
open http://127.0.0.1:8765
```

Or double-click this script from Finder:

```bash
./tools/Pleos\ Vehicle\ Controller.command
```

The controller sends GPS to the emulator and sends speed/location/state overrides to the Drive Pilot app.

## Direct ADB Controls

Send a speed/location override into the app:

```bash
adb -s emulator-5554 shell am broadcast \
  -n com.example.mrm_multimodal_demo/.DrivePilotControlReceiver \
  -a com.example.mrm_multimodal_demo.CONTROL \
  --es drivepilot_source controller \
  --ef speedKph 42 \
  --ed lat 37.4018000 \
  --ed lon 127.1089500 \
  --es driveState park
```

Move emulator GPS:

```bash
adb -s emulator-5554 emu geo fix 127.1157800 37.4063600 5
```

Set AAOS driving state:

```bash
adb -s emulator-5554 shell cmd car_service emulate-driving-state park
adb -s emulator-5554 shell cmd car_service emulate-driving-state drive
adb -s emulator-5554 shell cmd car_service emulate-driving-state reverse
```

## Pleos Notes

The Pleos system cluster/left vehicle UI exposes some values as read-only car properties. If `cmd car_service set-property-value` returns a `ServiceSpecificException` with `code 4`, that property is not writable in this emulator image.

For this reason, this demo controls the Drive Pilot app's own simulation layer with broadcasts and only reads available Pleos/AAOS vehicle data from the system.
