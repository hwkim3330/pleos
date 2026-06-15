# PLEOS 재구성 아키텍처 앱 개선 방향

작성일: 2026-06-15  
참조 문서: `/Users/parksik/Downloads/산업기술혁신사업_연차보고서_1세부_v4_최종.pdf`

## 1. 결론

현재 `apps/pleos_multimode` 앱은 3D 차량과 Autoware 멀티모드 전환을 보여주는 시연용 뷰어로는 충분하다. 다음 단계는 이 앱을 직접 고치는 것보다 복사본을 만들어 별도 앱으로 발전시키는 편이 좋다.

권장 신규 앱 이름:

```text
apps/pleos_reconfig_console
```

권장 앱 컨셉:

```text
PLEOS Reconfig Console
```

목표는 단순히 센서 고장 표시를 하는 앱이 아니라, 보고서의 핵심인 `전장부품 결함/오류 대응`, `기능 가변형 E/E 아키텍처`, `Zonal Gateway`, `센서 조합 기반 Autoware 멀티모드`, `평가/검증`을 한 화면에서 조작하고 설명할 수 있는 콘솔로 만드는 것이다.

## 2. 보고서에서 앱에 반영해야 할 핵심

보고서의 최종 목표는 자율주행차 전장부품 위험 시나리오별 안전성 향상을 위해 기능 재구성이 가능한 미래차 E/E 아키텍처를 개발하고, 시뮬레이션/실차 기반으로 검증하는 것이다. 따라서 앱의 중심도 `고장 발생` 자체가 아니라 `고장 후 어떤 구조로 재구성되고, 자율주행 stack이 어떤 상태로 바뀌며, 그 전환이 검증 가능한가`가 되어야 한다.

보고서 기준으로 반영할 축은 다음과 같다.

- 기능 재구성: 결함 감지 후 대체 경로, 대체 센서, 대체 Autoware stack으로 전환
- Zonal 아키텍처: 센서가 가까운 Zonal Gateway 또는 TSN 스위치에 연결되고, 장애 시 경로를 재구성
- 멀티모드 자율주행: LiDAR, GNSS, Camera 조합에 따른 측위 기반 주행 모드 전환
- 검증 관점: 전환 시간, 지연시간 최대치, 지연시간 편차, 측위 불연속성, 안전 목표 달성 여부 표시
- 안전 분석: FMEA/HARA 기반으로 고장 모드, 원인, 영향, 대응 전략을 구조화

## 3. 현재 앱의 한계

현재 앱에서 이미 잘 된 부분:

- 3D 차량 모델 기반 표시
- TSN-FL, TSN-FR, TSN-R 및 LiDAR/GNSS/Camera/VCU 라벨
- LiDAR/GNSS/Camera 조합별 Autoware 모드
- LiDAR 4개 개별 고장 시나리오
- MRM safe stop 및 Recover stack 조작

부족한 부분:

- 고장 시나리오가 보고서의 FMEA/HARA 구조와 직접 연결되어 있지 않음
- Zonal Gateway, Ethernet/CAN/LVDS/USB 인터페이스 구조가 UI에 드러나지 않음
- TSN/FRER/DetNet 같은 네트워크 재구성 의미가 약함
- Autoware 모드 전환이 pipeline/fusion weight/전환 시간으로 설명되지 않음
- 복구가 단순 clear처럼 보이며, `검증 후 복귀`와 `MRM 진입`의 차이가 약함
- 보고서/과제 제출용 근거 화면으로 쓰기에는 평가 지표 패널이 부족함

## 4. 새 앱의 화면 구성

### 4.1 전체 레이아웃

새 앱은 풀사이즈 가로형 콘솔로 구성한다.

```text
┌──────────────────────────────────────────────────────────────┐
│ Top: Scenario / Current Mode / Safety Goal / Validation State │
├───────────────┬──────────────────────────────┬───────────────┤
│ Scenario Rail │ 3D Vehicle + E/E Topology Map │ Evidence Panel │
│               │                              │               │
├───────────────┴──────────────────────────────┴───────────────┤
│ Bottom: Mode Timeline / Fusion Weight / Network Latency       │
└──────────────────────────────────────────────────────────────┘
```

핵심은 3D 모델만 크게 보여주는 것이 아니라, 3D 차량 위에 전장 아키텍처와 자율주행 stack 상태를 함께 올리는 것이다.

### 4.2 좌측 Scenario Rail

시나리오는 보고서식으로 분류한다.

- Sensor Fault
- Network Fault
- Zonal Gateway Fault
- Compute/Autoware Fault
- Compound Fault
- MRM Required
- Recovery Validation

각 시나리오는 다음 필드를 가진다.

```text
id
title
faultTarget
faultType
faultCause
faultEffect
severity
detectRule
reconfigAction
autowareModeAfter
mrmPolicy
validationMetric
evidenceRef
```

### 4.3 중앙 3D + E/E Topology View

중앙은 현재 3D 차량 모델을 유지하되, 표시 대상을 늘린다.

표시 요소:

- LiDAR 4개
- Camera 그룹
- GNSS/TCU
- Radar 그룹, 가능하면 5개 단위로 단순화
- TSN/Zonal Gateway 3개 이상
- ADS Compute
- VCU
- CAN backbone
- Ethernet/TSN links
- 장애 경로와 대체 경로

현재 `노란색 보드`처럼 보이는 영역은 이름을 `TSN Switch` 또는 `Zonal Gateway`로 정리한다. 보고서 관점에서는 `Zonal Gateway`가 더 설득력 있고, TSN은 네트워크 기능 계층으로 표현하는 편이 좋다.

권장 표기:

```text
ZG-FL
ZG-FR
ZG-R
TSN/FRER active
CAN fallback
```

### 4.4 우측 Evidence Panel

우측 패널은 단순 설명이 아니라 평가/검증 근거로 구성한다.

표시 항목:

- Fault chain: 원인 → 고장 모드 → 영향 → 대응
- FMEA/HARA severity
- Active safety goal
- Autoware stack state
- Reconfiguration result
- Validation checklist
- Report mapping

예시:

```text
Fault: GNSS drift
Detection: odometer distance mismatch
Reconfig: GNSS weight 5 -> 0
Mode: LiDAR + Camera
Validation: localization discontinuity not detected
MRM: standby
```

### 4.5 하단 Timeline / Metrics

하단은 발표 때 가장 중요한 부분이다. 장애 발생 후 시스템이 어떻게 움직였는지 시간 순서로 보여준다.

```text
t0 Normal
t1 Fault injected
t2 Fault detected
t3 Reconfiguration started
t4 Autoware mode switched
t5 Validation passed
t6 Recovered or MRM
```

같이 표시할 지표:

- Mode switch time
- Network latency max
- Network jitter
- Fusion weight
- Localization confidence
- Planning restriction
- Control speed cap

## 5. 멀티모드 Autoware 정의

보고서의 측위 센서 기준 7가지 모드를 앱에 그대로 넣는 것이 좋다.

| 모드 | 센서 조합 | 앱 표시 |
| --- | --- | --- |
| Triple | LiDAR + GNSS + Camera | 정상 주행 |
| Dual 1 | LiDAR + GNSS | Camera 상실 대응 |
| Dual 2 | LiDAR + Camera | GNSS 음영 대응 |
| Dual 3 | GNSS + Camera | LiDAR 저하 대응 |
| Single 1 | LiDAR only | 저속 crawl, HD map/NDT 중심 |
| Single 2 | GNSS only | 제한적 위치 유지, MRM 후보 |
| Single 3 | Camera only | 차선 기반 저속 유지, MRM 후보 |

현재 앱에는 GNSS only가 빠져 있다. 새 앱에서는 `GNSS only`를 넣되, 자율주행 지속 모드라기보다 `제한 운행 또는 MRM 전 단계`로 표현하는 것이 자연스럽다.

LiDAR 4개 개별 고장은 7개 모드 위에 얹는 세부 시나리오로 둔다.

```text
LiDAR-FL degraded -> Triple partial fusion, left lane change 제한
LiDAR-FC unavailable -> LiDAR partial fusion, speed cap
LiDAR-FR degraded -> Triple partial fusion, right lane change 제한
LiDAR-RC degraded -> rear confidence down, reverse assist 제한
```

## 6. 복구를 넣는 방식

복구는 반드시 넣는 것이 맞다. 다만 `Recover stack`이 단순히 경고를 지우는 버튼처럼 보이면 안 된다.

새 앱에서는 복구를 3단계로 나눈다.

1. Fault clear: 오류 입력 제거
2. Validation: 센서 품질, 네트워크 지연, stack 상태 확인
3. Restore: 원래 모드로 복귀

복구 실패 시에는 바로 정상으로 돌아가지 않고 MRM으로 간다.

```text
Fault clear 성공 + validation 성공 -> Triple sensor 복귀
Fault clear 성공 + validation 실패 -> degraded mode 유지
Fault clear 실패 또는 복합 장애 -> MRM safe stop
```

이렇게 해야 보고서의 `검증`, `안전성`, `기능 재구성` 언어와 맞는다.

## 7. 시나리오 세트

1차 구현에 넣을 시나리오는 다음 정도가 적당하다.

### A. Sensor Fault

- LiDAR-FL degraded
- LiDAR-FC unavailable
- LiDAR-FR degraded
- LiDAR-RC degraded
- GNSS drift
- GNSS denied
- Camera blinded
- Camera low light
- Radar unavailable

### B. Network Fault

- Front Ethernet link unstable
- Rear Ethernet link down
- TSN time sync lost
- FRER path A lost, path B active
- DetNet jitter exceeded

### C. Zonal Gateway Fault

- ZG-FL degraded
- ZG-FR reboot
- ZG-R isolated
- Gateway time sync mismatch

### D. Autoware Stack Fault

- Localization node delayed
- Perception confidence low
- Planning route confidence low
- Control command timeout

### E. Compound Fault

- GNSS denied + Camera blinded
- LiDAR-FC unavailable + TSN jitter exceeded
- ZG-FL isolated + LiDAR-FL degraded
- Multiple sensor confidence drop in rain/fog/night

### F. MRM

- Controlled stop
- Minimal lane keep
- Hazard light / external warning
- Stop completed, recovery pending

## 8. 데이터 모델

새 앱에서는 시나리오를 Dart 코드에 박아두기보다 JSON/YAML로 분리하는 것이 좋다.

예시:

```json
{
  "id": "gnss_drift",
  "category": "Sensor Fault",
  "target": "GNSS/TCU",
  "faultType": "GNSS drift",
  "cause": "urban canyon or tunnel",
  "detectRule": "odometer distance mismatch",
  "severity": 1,
  "beforeMode": "LiDAR + GNSS + Camera",
  "afterMode": "LiDAR + Camera",
  "fusionWeights": {
    "lidar": 0.6,
    "gnss": 0.0,
    "camera": 0.4
  },
  "networkAction": "no topology change",
  "controlPolicy": "lateral smoothing, speed cap",
  "validation": [
    "mode switch time < threshold",
    "localization discontinuity not detected",
    "MRM standby"
  ]
}
```

## 9. 구현 순서

### Phase 1. 앱 복사와 구조 정리

- `apps/pleos_multimode`를 `apps/pleos_reconfig_console`로 복사
- package name 변경: `com.example.pleosreconfig`
- 앱 이름 변경: `PLEOS Reconfig`
- 기존 3D 모델, WebView hotspot, fault provider 재사용
- 시나리오 데이터 모델 분리
- README와 실행 스크립트 추가

### Phase 2. 보고서형 UI로 재구성

- 좌측 시나리오 카테고리 rail 추가
- 중앙 3D + E/E topology overlay 추가
- 우측 evidence/validation panel 추가
- 하단 timeline/metrics panel 추가
- Show Labels를 `Labels`, `Topology`, `Fault Path`, `Metrics` 토글로 확장

### Phase 3. 시나리오와 검증 로직 확장

- 보고서 기반 7개 Autoware 측위 모드 반영
- LiDAR 4개 개별 장애 반영
- TSN/FRER/DetNet 네트워크 장애 반영
- Zonal Gateway 장애 반영
- 복합 장애와 MRM 진입 조건 반영
- Recover를 validation 기반 상태 전이로 변경

### Phase 4. 외부 연동

- ADB broadcast로 fault scenario 주입
- CBOR fault stream 유지
- 향후 Autoware/ROS 2 bridge를 위한 adapter 인터페이스 추가
- 로그 export: scenario, mode transition, metrics

## 10. 발표/검증용 데모 흐름

가장 설득력 있는 데모 순서는 다음이다.

1. Triple sensor mode 정상 상태
2. Show Labels로 센서/Zonal Gateway 표시
3. GNSS drift 주입
4. LiDAR + Camera 모드로 전환
5. Fusion weight에서 GNSS가 0으로 내려가는 것 표시
6. Validation panel에서 측위 불연속성 없음 표시
7. Recover validation 후 Triple 복귀
8. 복합 장애 주입
9. MRM safe stop 진입
10. 로그/근거 패널로 보고서 요구사항 대응 설명

## 11. 성공 기준

새 앱은 다음 질문에 답할 수 있어야 한다.

- 어떤 전장부품 또는 센서가 고장났는가?
- 고장이 어떤 방식으로 감지됐는가?
- 어떤 Zonal/Ethernet/TSN 경로가 영향을 받았는가?
- 어떤 Autoware 측위 모드로 전환됐는가?
- 전환 중 성능 영향은 무엇인가?
- 검증 결과 정상 복귀 가능한가, MRM으로 가야 하는가?
- 이 시나리오가 보고서의 어떤 요구사항/성과와 연결되는가?

## 12. 최종 권장 방향

현재 앱을 계속 덧붙이면 화면이 복잡해지고 기존 데모 안정성도 흔들릴 수 있다. 따라서 현재 앱은 `PLEOS Multimode 3D Viewer`로 유지하고, 새 앱을 `PLEOS Reconfig Console`로 복사해서 만든다.

새 앱은 보고서형 산출물에 가깝게 만든다. 핵심은 3D 모델의 멋이 아니라 `시나리오`, `재구성`, `검증`, `근거`가 한 번에 보이는 것이다. 그렇게 가야 과제 보고서, 전시 데모, Autoware 연동 설명이 모두 같은 화면에서 맞물린다.
