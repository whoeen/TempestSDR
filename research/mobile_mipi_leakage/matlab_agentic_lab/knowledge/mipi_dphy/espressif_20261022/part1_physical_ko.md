# 제1부 — 용어, 인터페이스 개요와 D-PHY 물리층

- 번역 대상: 사용자가 첨부한 전체 페이지 화면의 **Glossary부터 Physical Layer 끝까지**.
- 원문: [Espressif, MIPI DSI LCD Detailed Guide](https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/mipi_dsi_lcd.html), 확인일 2026-10-22 KST.
- 원문 확인: 첨부 PNG 원본의 해당 영역을 확대해 본문·그림과 웹 문서를 대조했다.
- 아래 **A는 원문의 번역**, **B는 별도의 검증·설명**이다. A의 잘못된 표기까지 임의로 바꾸지 않고, 연구에 영향을 주는 오류는 [검증]으로 표시했다. 이 문서는 ESP32-P4 구현 안내를 포함한다. 그 구현 제한을 모든 스마트폰 DSI의 성질로 확대하면 안 된다.

## A. 원문 전체 번역

### 1. 용어집 — Glossary

[LCD 용어표](https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/lcd_terms_table.html)를 참조한다.

#### MIPI-DSI 관련 용어

| 약어 | 전체 이름 | 설명 |
|---|---|---|
| MIPI-DSI | MIPI Display Serial Interface | MIPI Alliance가 개발한 고속 직렬 인터페이스 표준. 프로세서와 디스플레이 장치를 연결하기 위해 설계되었다. |
| DCS | Display Command Set | 디스플레이 모듈을 제어하기 위해 MIPI-DSI에서 정의한 표준 디스플레이 명령 집합. |
| DBI | Display Bus Interface | DSI의 Command Mode를 esp-lcd의 제어 IO 계층으로 캡슐화한다. |
| DPI | Display Pixel Interface | DSI의 Video Mode를 esp-lcd의 데이터 패널 계층으로 캡슐화한다. |
| HS | High-Speed Mode | 고속 모드. 주로 디스플레이 프레임 데이터를 전송하는 데 사용하며, 일반적으로 lane당 80Mbps~1.5Gbps이다. |
| LP | Low-Power Mode | 저전력 모드. 일반적으로 DCS 명령 전송이나 링크 상태 제어에 사용하며, 최대 속도는 약 10MHz이다. [검증 P3] |
| HS-TX/HS-RX | High-Speed Transmitter/Receiver | 고속 송신기/수신기. |
| LP-TX/LP-RX | Low-Power Transmitter/Receiver | 저전력 송신기/수신기. |
| LP-CD | Low-Power Contention Detector | 저전력 모드에서의 충돌 검출기. |
| BTA | Bus Turnaround | 양방향 통신을 위한 버스 방향 전환. |
| ULPS | Ultra Low Power State | 전력 소모를 최대한 줄이기 위한 초저전력 상태. |
| LPDT | Low Power Data Transmission | 저전력 데이터 전송 모드. |
| ESC | Escape Mode | Escape 모드. MIPI-DSI의 저전력 동작 모드. |
| SoT | Start of Transmission | 전송 시작 신호. |
| EoT | End of Transmission | 전송 종료 신호. |
| DI | Data Identifier | 패킷 종류를 식별하는 데이터 식별자. |
| ECC | Error Correction Code | 데이터 무결성을 검증하기 위한 오류 검출 코드. [검증 P8: 이름은 오류 정정 코드이며 설명을 보완해야 한다.] |
| DT | Data Type | 픽셀 데이터 형식을 식별하는 데이터 유형. [검증 P8: 픽셀 형식 이외의 패킷 종류도 포함한다.] |
| HSYNC | Horizontal Synchronization | 수평 동기 신호. |
| VSYNC | Vertical Synchronization | 수직 동기 신호. |
| DMA | Direct Memory Access | 효율적인 데이터 전송을 위한 직접 메모리 접근. |
| PSRAM | Pseudo Static RAM | 의사 정적 RAM. |
| RGB565 | Red Green Blue 565 | 16비트 색상 형식. 빨강 5비트, 초록 6비트, 파랑 5비트. |
| RGB666 | Red Green Blue 666 | 18비트 색상 형식. 빨강·초록·파랑 각각 6비트. |
| RGB888 | Red Green Blue 888 | 24비트 색상 형식. 빨강·초록·파랑 각각 8비트. |

### 2. MIPI-DSI 인터페이스 및 프로토콜 소개

#### 2.1 MIPI-DSI 인터페이스 개요

MIPI-DSI(MIPI Display Serial Interface)는 프로세서와 디스플레이 장치를 연결하기 위해 MIPI Alliance가 개발한 고속 직렬 인터페이스 표준이다. 다음과 같은 특징이 있다.

- **고속 전송:** 각 데이터 채널은 최대 수 Gbps의 전송 속도를 지원할 수 있다.
- **낮은 전력 소모:** 저전압 차동 신호를 사용하며, 유휴 상태이거나 저속으로 전송할 때 저전력 모드에 들어간다.
- **핀 수 감소:** 병렬 RGB 인터페이스와 비교하여 신호선 수가 크게 줄어든다.
- **확장성:** 1~4개의 데이터 채널을 지원한다.
- **높은 호환성:** 다양한 해상도와 디스플레이 장치를 지원한다.

현재 ESP32-P4에는 MIPI-DSI 인터페이스가 있으며, **2lane × 1.5Gbps**를 지원한다. 영상 스트림을 출력할 때는 Video Mode를 사용한다.

#### 2.2 MIPI-DSI 화면 갱신 원리

MIPI-DSI는 프로세서와 디스플레이를 연결할 때 널리 쓰이는 디스플레이 인터페이스 표준이다. 다음 두 가지 주요 데이터 전송 모드를 지원한다.

1. Command Mode
2. Video Mode

현재 ESP32-P4는 영상 스트림 출력에 Video Mode만 지원한다.

Video Mode에서 호스트는 디스플레이의 갱신 주기, 예를 들어 VSync에 엄격하게 동기화하여 연속적인 영상 프레임 형태로 데이터를 전송한다. 디스플레이에는 프레임 버퍼 메모리가 필요하지 않으므로 하드웨어 설계를 단순화할 수 있다. 이 모드는 고해상도·고주사율 디스플레이에 널리 사용된다.

**그림: MIPI-DSI 화면 갱신 과정**

원본 그림: [mipi_dsi_video.png](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_video.png)

그림 속 표기 번역:

| 원문 표기 | 번역 |
|---|---|
| ESP SoC | ESP 시스템 온 칩 |
| GRAM | 그래픽 RAM |
| MIPI-DSI | MIPI 디스플레이 직렬 인터페이스 |
| I2C / SPI | I²C / SPI 통신 인터페이스 |
| Command | 명령 |
| Frame Color | 프레임의 색상 데이터 |
| Touch Point | 터치 위치 |
| Screen | 디스플레이 모듈 |
| LCD IC / Driver | LCD 집적회로 / 구동기 |
| Panel | 표시 패널 |
| Touch IC | 터치 제어 집적회로 |

위 그림은 MIPI-DSI의 화면 갱신 과정을 나타낸다.

- **명령 데이터:** MIPI-DCS 명령은 DBI를 통해 LCD 컨트롤러로 전달된다. 레지스터 초기화와 디스플레이 기능 제어에 사용된다.
- **프레임 색상 데이터:** MIPI-DSI Video Mode에서는 호스트 측 프레임 버퍼, 즉 내부 또는 외부 RAM의 픽셀 데이터를 DMA를 통해 LCD 패널로 연속 출력하여 표시한다. LCD 드라이버 IC에는 GRAM이 필요하지 않다.
- **터치 데이터:** 터치스크린이 터치 신호를 감지하고, I²C 또는 SPI 인터페이스를 통해 호스트 시스템에 전달하여 처리한다.

#### 2.3 MIPI-DSI 프로토콜

MIPI-DSI는 크게 물리 계층(Physical Layer), 프로토콜 계층(Protocol Layer), 디스플레이 명령 계층(DCS Layer)으로 나눌 수 있다. 각 계층은 고유한 기능을 담당하며, 함께 동작하여 호스트에서 디스플레이로 명령과 픽셀 데이터를 전달한다.

각 계층이 협력하는 과정은 다음 그림으로 요약할 수 있다.

**그림: MIPI-DSI 프로토콜 계층**

원본 그림: [mipi_dsi_layer.png](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_layer.png)

그림 안의 모든 계층과 설명을 위에서 아래 순서로 번역하면 다음과 같다.

| 계층 | 그림 속 설명 번역 |
|---|---|
| Application Layer — 응용 계층 | 디스플레이 명령 또는 영상 프레임 데이터를 생성한다. |
| DCS Layer — 디스플레이 명령 계층 | 밝기, 해상도, 픽셀 쓰기 등의 디스플레이 명령을 정의한다. |
| Protocol Layer — 프로토콜 계층 | 데이터를 MIPI-DSI 패킷으로 구성하고 필요한 제어 정보를 추가한다. |
| Physical Layer — 물리 계층 | D-PHY 고속 링크를 통해 데이터 패킷을 전송한다. |
| Display Screen — 디스플레이 화면 | 데이터를 해석하고 표시 내용을 갱신한다. |

### 3. 물리 계층 — Physical Layer

#### 3.1 기능

실제 데이터 전송을 담당하며 프로토콜 스택의 가장 아래에 위치한다. MIPI D-PHY를 이용해 고속 차동 신호를 전송하고, 여러 채널을 통한 데이터 전송을 지원한다.

#### 3.2 전송 모드

- **고속 모드(High-Speed Mode):** 주로 디스플레이 프레임 데이터를 전송하는 데 사용한다. 명령도 전송할 수 있으며, 일반적인 속도는 lane당 80Mbps~1.5Gbps이다.
- **저전력 모드(Low-Power Mode):** 일반적으로 Command Mode에서 DCS 명령을 보내거나 링크 상태를 제어할 때 사용한다. 최대 속도는 약 10MHz이며, 구체적인 값은 칩의 지원 범위에 따라 달라진다. [검증 P2·P3]

#### 3.3 구성

- **Clock Lane:** 동기화 신호를 제공한다.
- **Data Lane:** 실제 디스플레이 데이터를 전송한다.

#### 3.4 Lane 모듈, 즉 D-PHY의 상세 설명

##### 종류

| Lane 종류 / 전송 역할 | Master | Slave |
|---|---|---|
| 단방향 Clock Lane | HS-TX, LP-TX | HS-RX, LP-RX |
| 단방향 Data Lane | HS-TX, LP-TX | HS-RX, LP-RX |
| 양방향 Data Lane | HS-TX, LP-TX, HS-RX, LP-RX, LP-CD | HS-TX, LP-TX, HS-RX, LP-RX, LP-CD |

**참고 — 모듈 기능 설명**

- **LP-TX/LP-RX:** 저전력 송신기/수신기.
- **HS-TX/HS-RX:** 고속 송신기/수신기.
- **LP-CD:** 저전력 모드에서의 충돌 검출기.

Clock Lane은 일반적으로 단방향이며, Master가 제공한 신호를 Slave가 수신한다. 양방향 lane과 LP-CD는 주로 Command Mode의 저전력 통신에서 사용된다. [검증 P2·P7]

##### 상태

- **LP 상태(LP-00, LP-01, LP-10, LP-11):** 단일 종단 신호를 사용한다. 주로 저속 명령 전송, 제어 신호, 초기화 또는 대기 상태에 사용한다. 서로 다른 LP 상태를 부호화와 링크 제어에 사용한다.
- **HS 상태(HS-0, HS-1):** 차동 신호를 사용한다. 주로 영상 데이터나 프레임 내용을 고속으로 전송할 때 사용한다. HS-0과 HS-1은 차동 신호 쌍의 논리 상태를 나타내며, HS-TX/HS-RX에서만 유효하다.

##### 대표 전압

- **LP:** 일반적인 전압은 약 0~1.2V이다.
- **HP:** 일반적인 차동 전압은 약 100~300mV이다. [원문 표기 유지. 문맥상 HS의 오타로 판단됨 — 검증 P1]

##### 동작 모드

**1. Escape Mode**

Low-Power Mode에서만 사용할 수 있다. 특별한 데이터를 전송하거나 특정 기능을 실행하기 위한 MIPI-DSI의 저전력 동작 모드이다. 다음 기능을 지원한다.

| 기능 이름 | 설명 | 명령 |
|---|---|---|
| LPDT — Low Power Data Transmission | 저전력 모드로 데이터를 전송한다. | 0x87 |
| ULPS — Ultra Low Power State | 초저전력 상태에 들어가 전력 소모를 최대한 줄인다. | 0x84 [원문값; 검증 P4에서 정정] |
| Trigger Command | 상태 전환이나 모드 조정 등의 특정 이벤트를 발생시킨다. | 0x85 [원문값; 검증 P4] |

- **진입 과정 — 신호 상태 머신의 전이:**

  `LP-11 → LP-10 → LP-00 → LP-01 → LP-00`

- **종료 과정:**

  `LP-10 → LP-11`

**2. High-Speed (Burst) Mode**

항상 High-Speed Mode에서 동작한다. 고속 직렬 데이터 전송에 사용하며, 높은 대역폭이 필요한 경우에 적합하다. [원문 번역. “항상”이라는 표현은 검증 P5에서 보완한다.]

- **진입 과정:**

  `LP-11 → LP-01 → LP-00 → SoT(전송 시작) → HSD(80Mbps~1.5Gbps)`

- **종료 과정:**

  `EoT(전송 종료) → LP-11`

**3. Control Mode**

기본적으로 Low-Power Mode에서 동작한다. Stop 상태에서 명령을 전송하거나 양방향 통신, 즉 BTA(Bus Turnaround)를 수행할 때 사용한다. [검증 P5]

- **BTA 송신 과정:**

  `LP-11 → LP-10 → LP-00 → LP-10 → LP-00`

  위 과정은 버스 방향 전환을 위한 상태 전이다.

- **BTA 수신 과정:**

  `LP-00 → LP-10 → LP-11`

#### 3.5 중요한 신호 설명

MIPI-DSI 통신에서는 두 가지 중요한 Stop 신호를 통해 버스 상태를 적절하게 관리한다.

**그림: MIPI-DSI Stop 신호 타이밍**

원본 그림: [mipi_dsi_stop.png](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_stop.png)

첨부 그림의 디코더 표시 순서는 `BTA → Stop → ESC → 0x84 → Stop`이다. 아래 두 파형은 D0N, D0P이다. BTA는 버스 방향 전환, Stop은 정지 상태, ESC는 Escape 진입을 의미한다. 0x84의 의미는 아래 원문의 설명과 별도로 검증 P4·P6을 확인해야 한다.

**1. BTA-Stop 신호**

Slave가 Bus Turnaround 응답을 마친 뒤 전송한다. 다음을 나타낸다.

- 버스 방향 전환 동작이 성공적으로 완료되었다.
- Slave가 버스 제어권을 해제했다.
- Host가 버스 제어권을 다시 얻을 수 있다.

**2. ESC-0X84-Stop 신호**

Lane의 Stop 신호 전송을 나타내는 데 사용한다. 구체적인 기능은 다음과 같다.

- 시스템을 초저전력 상태(ULPS)로 전환한다.
- Escape Mode의 0x84 명령에 해당한다.
- 전력 관리를 극대화한다.

**팁**

이러한 Stop 신호는 MIPI-DSI 프로토콜에서 통신 신뢰성과 전력 관리를 보장하는 핵심 수단이다.

**[원문 번역 종료: 다음 절은 Protocol Layer이다.]**

## B. 검증과 연구 해설 — 번역문과 구분

### P1. HP는 문맥상 HS 오타이며, 전압은 측정량을 먼저 정의해야 한다

원문의 LP/HP는 LP/HS로 읽어야 한다. D-PHY는 같은 Dp/Dn 두 선에서 LP의 단일 종단 신호와 HS의 차동 신호를 사용한다. 그러나 “100~300mV”를 안테나 수신 신호의 전압으로 해석하면 안 된다. 이는 PHY 핀의 전기적 신호에 관한 기술이며, 차동 전압과 공통 모드 전압은 서로 다르다.


- 차동 전압: `v_d(t) = v_p(t) - v_n(t)`
- 공통 모드 전압: `v_cm(t) = [v_p(t) + v_n(t)] / 2`

차동 쌍의 불균형, 배선, 리턴 경로와 공간 전파를 거친 안테나의 복소 IQ는 위 핀 전압 중 하나를 그대로 복제한 값이 아니다. 따라서 HS의 차동 전압 범위만으로 방사 AM/PM 변조도나 수신 SNR을 계산할 수 없다. 상태 명칭과 Dp/Dn 매핑은 [Analog Devices AN-2621, Table 8](https://www.analog.com/en/resources/app-notes/an-2621.html)과 대조했다.

### P2. HS/LP와 Video/Command는 서로 다른 분류다

| 구분 | 답하는 질문 |
|---|---|
| HS / LP | 배선에서 어떤 전기적 신호 방식으로 전송하는가? |
| Video / Command | 표시 데이터를 어떤 프로토콜·갱신 방식으로 전달하는가? |
| DCS | 디스플레이에 어떤 명령을 내리는가? |
| DBI / DPI | 이 문서의 esp-lcd 구현에서 제어 경로와 영상 경로를 어떻게 추상화하는가? |

“명령은 LP, 영상은 HS”는 흔한 사용 경향을 간단히 표현한 것이며, 엄밀한 일대일 대응이 아니다. HS로 명령을 보낼 수도 있고 Video Mode의 빈 구간에 명령을 삽입할 수도 있다. ESP32-P4가 영상 출력에 Video Mode를 사용한다는 문장도 스마트폰이 동일하게 동작한다는 증거가 아니다. [Microchip DS60001813E, Transmission of Commands의 Video/LP/HS 하위 절](https://onlinedocs.microchip.com/oxy/GUID-51CE727C-126C-4670-A2BA-189781F25924-en-US-3/GUID-7761A315-1C72-4B64-AFBF-C367690C6A11.html)

원문의 계층 그림은 설명용 개념도다. Video Mode의 모든 픽셀 데이터가 DCS 명령으로 변환된 뒤 전송된다고 해석해서는 안 된다. 화면 갱신 그림도 Video Mode의 한 구성 예시이며, “GRAM이 필요 없다”는 “어떤 수신 디스플레이에도 버퍼가 존재하지 않는다”는 뜻은 아니다.

### P3. 80Mbps~1.5Gbps와 10MHz를 D-PHY 전체의 보편 상한으로 쓰지 않는다

원문의 HS 속도 범위는 예전 D-PHY 및 이 가이드의 ESP32-P4 범위와 연관 지어 읽어야 한다. [Arasan D-PHY v1.1 구현](https://www.arasan.com/products/mipi/mipi-phys/d-phy-v1-1/)은 HS 80~1500Mb/s, LP 비동기 전송 10Mb/s를 명시한다. LP 데이터 전송률을 MHz로 적으면 escape clock 주파수와 bit rate가 혼동되므로 **Mb/s**와 구분해야 한다. 칩 내부 escape clock과 실제 LP 유효 데이터 속도는 같은 값이라고 가정할 수 없다.

또한 [MIPI 공식 D-PHY 페이지](https://www.mipi.org/specifications/d-phy)는 후속 버전의 더 높은 속도와 선택적 embedded-clock mode를 설명한다. 따라서 이 문서의 고정 clock lane 구조와 속도 범위를 모든 버전의 D-PHY 규정으로 확대하지 않는다. 반대로 최신 버전 기능을 LG X2나 iPhone 6에 적용했다고 추정하지도 않는다.

### P4. 원문의 “ULPS = 0x84”는 잘못되었다

시간순 비트열을 먼저 적고, 일반적인 16진 byte 표기로 바꾸어 보면 혼동을 줄일 수 있다.

| 기능 | 시간순 비트열: 먼저 전송되는 bit가 왼쪽 | LSB-first로 해석한 byte | 확인 근거 |
|---|---|---|---|
| ULPS entry | `00011110` | **0x78** | TI DS90UR910-Q1 Rev. E, p.19, Fig.13 |
| Acknowledge Trigger | `00100001` | **0x84** | 로컬 DSI v1.3 draft, PDF p.83 / 인쇄 p.71, §8.9.4, lines1880–1881 |
| TE Trigger | `01011101` | **0xBA** | 같은 DSI 문서 PDF p.92 / 인쇄 p.80, §8.12, lines2141–2143 |

따라서 0x84를 ULPS 동기 template로 사용하면 ACK를 ULPS로 오인하게 된다. 첨부 Stop 그림의 `ESC → 0x84 → Stop`은 **ACK Trigger와 일치하는 해석 후보**이다. 그림에 송수신 주체와 전체 앞뒤 트랜잭션이 없으므로 “어느 쪽이 어떤 명령에 응답한 ACK인가”까지는 확정할 수 없다.

근거: [TI 공식 DS90UR910-Q1 데이터시트, p.19](https://www.ti.com/lit/gpn/DS90UR910-Q1). ACK와 TE 값은 기존에 확보한 로컬 MIPI DSI v1.3 draft를 직접 확인했다. 해당 원문은 로컬 연구 참조이며 재배포하지 않는다.

원문의 “Trigger Command = 0x85”도 모든 trigger의 공통 명령처럼 사용하면 안 된다. 확인된 ACK와 TE는 각각 위의 값이며, 0x85에 대해 가이드가 의도한 특정 의미는 이 문서만으로 확인되지 않는다.

ST AN4860 공식 PDF도 교차 확인을 시도했으나 웹 도구의 크기 제한(약13.1MB) 및 로컬 네트워크 DNS 실패로 해당 파일의 본문 열람에 실패했다. 따라서 ST 본문을 읽었다고 기록하지 않았다.

### P5. Stop 상태에서는 DCS 패킷을 전송하지 않는다

Stop은 Dp=1, Dn=1인 **LP-11 유휴 상태**다. 그 상태에서 전송 요청을 시작하여 Escape/LPDT 또는 HS 상태로 옮겨가 데이터를 전송하고, 이후 Stop으로 돌아온다. 따라서 원문의 “stop state에서 명령 전송”은 “Stop에서 출발하는 제어 절차”로 이해해야 한다. [Microchip, Control Mode](https://onlinedocs.microchip.com/oxy/GUID-51CE727C-126C-4670-A2BA-189781F25924-en-US-3/GUID-047D4BCE-20CD-4B02-B13C-C41914B010AE.html)

“High-Speed (Burst) Mode는 항상 HS”도 HS payload 구간에 한정한 설명이다. 실제 burst의 앞뒤에는 LP 진입·종료 과정이 포함된다. Clock lane과 data lane의 HS 진입·종료는 구별해야 하며, data lane 전체의 HS 전송을 포괄하는 동안 forwarded clock이 유효해야 한다. [Microchip, High-Speed Data Transfer Mode](https://onlinedocs.microchip.com/oxy/GUID-51CE727C-126C-4670-A2BA-189781F25924-en-US-3/GUID-1337F0F0-0EE8-402C-BF80-8AA8E69BA182.html)

### P6. Stop과 ULPS, 버스 소유권을 구분한다

- **Stop:** LP-11.
- **ULPS 유지:** LP-00.
- **ULPS 종료:** 규정된 wakeup 시간의 Mark-1(LP-10)을 거친 뒤 Stop(LP-11).
- **BTA:** 누가 lane을 구동하는지 바꾸는 방향 전환 절차. LP-11 파형만으로 소유권을 단정할 수 없다.

[TI Fig.13](https://www.ti.com/lit/gpn/DS90UR910-Q1)은 ULPS(LP00), Mark-1(LP10), Stop(LP11)을 별도 구간으로 표시한다. 따라서 원문의 “ESC-0x84-Stop이 ULPS 진입”이라는 해석은 전기적 상태 및 명령 값 양쪽에서 맞지 않는다.

또한 BTA 직후의 Stop이 항상 “slave가 응답을 끝내고 host에 돌려주었다”는 뜻도 아니다. Host→peripheral로 넘기는 BTA인지 반대 방향인지, 앞뒤의 제어 흐름을 확인해야 한다. 로컬 DSI v1.3 §8.12에는 host가 bus ownership을 peripheral에 넘긴 뒤 TE trigger를 기다리는 사례가 있다.

### P7. Lane 모듈 표는 가능한 PHY 구성과 DSI 실제 연결을 구분해서 읽는다

원문의 양방향 lane 표는 HS/LP TX·RX를 모두 나열한 일반적인 모듈 구성 설명이다. 그것만으로 실제 스마트폰 디스플레이가 모든 lane에서 양방향 HS 데이터를 주고받는다고 결론낼 수 없다. 사용 장치와 DSI 규격에 맞게 forward HS 경로, reverse LP 경로, BTA가 사용되는 lane을 따로 확인해야 한다.

### P8. ECC, DT 용어의 범위를 보완한다

- **ECC**는 단순 CRC 같은 payload 검출 코드와 구별된다. DSI header의 수정된 Hamming code는 규정된 범위의 bit 오류를 정정·검출한다. 원문 용어표가 “Error Correction Code”를 적어 놓고 설명에서 “error detection code”로 줄인 점을 보완해야 한다.
- **DT**는 RGB888 같은 pixel stream뿐 아니라 DCS short/long write, read response, sync event 등 여러 패킷 종류를 나타낸다. DI는 VC와 DT를 함께 포함한다.

### P9. 스마트폰 방사 연구에 적용할 때의 의미

이 부분에서 얻을 수 있는 유용한 후보는 세 종류다.

1. **HS 진입과 종료가 만드는 상태 전환:** 화면 전체를 직렬화하는 데이터 구간과 구별되는 반복 이벤트 후보.
2. **LPDT, ACK, TE 같은 알려진 제어 패턴:** 실제 사용 여부가 확인된다면 timing anchor 후보.
3. **Pixel payload의 반복성과 packet 경계:** 동일한 RGB888 데이터라도 lane 수·packetization·video/command mode에 따라 서로 다른 시간 구조를 만든다.

다만 이 문서의 LP/HS logic analyzer 그림은 접촉 측정한 논리 복호 결과에 해당한다. 안테나 IQ에서 같은 패턴이 곧바로 읽힌다는 뜻은 아니다. 안테나 관측에는 lane별 결합, RF 대역 제한, 필터 지연과 미지 위상이 포함되므로, 실제 프로토콜 이벤트를 찾을 때는 대역 제한된 template 및 독립적인 timing evidence를 함께 사용해야 한다.
