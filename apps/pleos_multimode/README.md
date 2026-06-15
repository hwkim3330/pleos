# PLEOS Multimode 3D Viewer

Pleos Connect / Android Automotive OS에서 Autoware 멀티모드 전환을 시각화하는 Flutter 앱입니다.

- 앱 이름: `PLEOS Multimode`
- Android package/activity: `com.example.pleosmrmviewer/.MainActivity`
- 3D 모델: `lib/assets/roii.glb`
- 주요 기능: 3D 차량 뷰어, TSN 스위치/센서 라벨, LiDAR/GNSS/Camera 조합별 Autoware 모드, MRM safe stop, Recover stack

## 1. Pleos 에뮬레이터 켜기

프로젝트 루트와 상관없이 macOS 터미널에서 실행합니다.

```bash
adb kill-server
adb start-server
rm -f ~/.android/avd/Pleos_Connect_v2.avd/*.lock ~/.android/avd/Pleos_Connect_v2.avd/multiinstance.lock
~/Library/Android/sdk/emulator/emulator -avd Pleos_Connect_v2 -no-snapshot-load
```

이 터미널은 닫지 않습니다. 에뮬레이터 창이 뜨면 다른 터미널을 열어 다음 단계로 갑니다.

## 2. 부팅 완료 확인

```bash
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
adb devices
```

정상 예:

```text
List of devices attached
emulator-5554    device
```

## 3. 이미 설치된 앱 실행

```bash
adb -s emulator-5554 shell am start -n com.example.pleosmrmviewer/.MainActivity
```

앱이 가운데 Pleos 앱 창에 뜨면 바로 조작할 수 있습니다.

## 4. 앱이 없거나 최신 소스로 다시 설치할 때

프로젝트 루트에서 실행합니다.

```bash
cd apps/pleos_multimode
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"

flutter pub get
flutter analyze
flutter test
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell am start -n com.example.pleosmrmviewer/.MainActivity
```

개발 중에는 프로젝트 루트에서 빌드/설치 대신 `flutter run`을 써도 됩니다.

```bash
cd apps/pleos_multimode
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"

flutter run -d emulator-5554 --debug --no-resident
```

## 5. 조작 순서

1. 오른쪽 `Autoware Multimode Control`에서 시나리오를 누릅니다.
2. 3D 모델에 경고 핫스팟이 표시되고, 왼쪽 상태 카드가 현재 Autoware stack으로 바뀝니다.
3. 아래 `Show Labels`를 누르면 `TSN-FL`, `TSN-FR`, `TSN-R`, `LiDAR-FL/FC/FR/RC`, `Camera-FC`, `GNSS/TCU`, `VCU` 라벨이 표시됩니다.
4. 아래 `Vehicle shell`을 누르면 차량 외피/부품 표시를 전환합니다.
5. 아래 `Recover stack`을 누르면 fault 상태와 경고 표시가 지워지고 Triple sensor 상태로 돌아갑니다.

시나리오:

- `Triple sensor mode`: LiDAR + GNSS + Camera 정상 운용
- `LiDAR + GNSS mode`: Camera 상실
- `LiDAR + Camera mode`: GNSS 음영
- `GNSS + Camera mode`: LiDAR 성능 저하
- `LiDAR-FL degraded`: 좌전방 LiDAR 저하
- `LiDAR-FC unavailable`: 중앙 LiDAR 상실
- `LiDAR-FR degraded`: 우전방 LiDAR 저하
- `LiDAR-RC degraded`: 후방 LiDAR 저하
- `LiDAR only mode`: Camera/GNSS 제한
- `Camera only mode`: LiDAR/GNSS 제한
- `MRM safe stop`: 자율주행 stack 유지 불가, 안전 정지

## 6. 문제 해결

에뮬레이터가 `adb devices`에 안 보일 때:

```bash
adb kill-server
adb start-server
adb devices
```

AVD가 바로 꺼지거나 안 뜰 때:

```bash
rm -f ~/.android/avd/Pleos_Connect_v2.avd/*.lock ~/.android/avd/Pleos_Connect_v2.avd/multiinstance.lock
~/Library/Android/sdk/emulator/emulator -avd Pleos_Connect_v2 -no-snapshot-load -verbose
```

`Unable to locate a Java Runtime` 오류가 날 때:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"
java -version
```

Pleos 매니저/영상 팝업이 앱을 덮을 때:

- 팝업 왼쪽 위 `X`를 눌러 닫습니다.
- 앱을 다시 앞으로 보내려면 실행 명령을 다시 보냅니다.

```bash
adb -s emulator-5554 shell am start -n com.example.pleosmrmviewer/.MainActivity
```

앱을 완전히 재시작할 때:

```bash
adb -s emulator-5554 shell am force-stop com.example.pleosmrmviewer
adb -s emulator-5554 shell am start -n com.example.pleosmrmviewer/.MainActivity
```

로그 확인:

```bash
adb -s emulator-5554 logcat | grep -E "pleosmrmviewer|flutter|chromium|WebView"
```
