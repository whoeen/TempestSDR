# 프로토콜 계층·DCS·색 형식 — 한국어 전체 번역과 기술 해설

대상: Espressif, *MIPI DSI LCD Detailed Guide*의 **Protocol Layer**부터 **Color Format** 끝까지. 열람일: 2026-10-22. 사용자 제공 전체 페이지 캡처의 해당 부분과 현재 웹 페이지를 대조했다. 본문은 원문의 문장과 표를 빠짐없이 번역하고, 원문에 있는 오류·생략은 별도의 **검증 해설**에서 바로잡는다. 본 범위에는 소스 코드 블록이 없다.

원문: <https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/mipi_dsi_lcd.html#protocol-layer>

## 1. 원문 전체 번역

### 프로토콜 계층 (Protocol Layer)

- **기능:** 데이터를 패킷으로 구성하고 해석한다. DCS 패킷이나 영상 데이터 패킷과 같은 전송 형식을 정의하고, 데이터의 정확성과 신뢰성을 보장하기 위한 오류 검출 기능을 제공한다.
- **데이터 프레임 구조**

#### 짧은 패킷 (Short Packet)

- **길이:** 4바이트로 고정된다.
- **구성:** 데이터 식별자 DI 1바이트, 프레임 데이터 2바이트, 오류 검출 ECC 1바이트.

**원문 그림: MIPI-DSI 짧은 패킷의 구성**

[원문 그림 보기](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_short_packet.png)

그림에 표시된 문구와 값은 다음과 같다.

| 원문 그림 표기 | 한국어 번역 또는 값 |
|---|---|
| Packet Header (PH) | 패킷 헤더 |
| Packet Data (PD) | 패킷 데이터 |
| DI (Data Identification) | 데이터 식별자 |
| Data 0 (Packet Data) | 데이터 0, 패킷 데이터 |
| Data 1 (Always 8'b 00h) | 데이터 1, 항상 0x00으로 표시됨 |
| ECC (Error Correction Code) | 오류 정정 코드 |
| DI / Data 0 / Data 1 / ECC | `21 45 00 01` |
| B0 … B7 / LSB / MSB | 비트 0 … 비트 7 / 최하위 비트 / 최상위 비트 |
| Time | 시간, 오른쪽으로 증가 |

그림은 각 바이트의 최하위 비트부터 전송되는 순서를 표시한다. `Data 1 = 00` 표기는 이 그림의 예시를 그대로 옮긴 것으로, 모든 짧은 패킷에 적용되는 규칙은 아니다. 자세한 설명은 아래 검증 해설에 있다.

**예시: MIPI-DSI 짧은 패킷의 타이밍**

[원문 파형 그림 보기](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_short_packet_example.png)

주요 필드는 전송 순서대로 다음과 같다.

- **ESC:** Escape 모드로 진입한다.
- **0x87:** LPDT, 저전력 데이터 전송 모드.
- **0x37:** 데이터 식별자. 원문에서는 DCS 명령인 “최대 반환 패킷 크기 설정(Set Maximum Return Packet Size)”에 해당한다고 설명한다. 호스트가 주변 장치로부터 수신하는 반환 데이터 패킷의 최대 크기를 설정한다.
- **0x03, 0x00:** 프레임 데이터. 최대 반환 패킷 크기를 3바이트로 설정한다는 뜻이다.
- **0x01:** ECC, 오류 정정 코드.

#### 긴 패킷 (Long Packet)

- **길이:** 6바이트에서 65,541바이트까지 가변적이다.
- **구성:** 프레임 헤더는 데이터 식별자 DI 1바이트, 데이터 수 WC 2바이트, 오류 검출 ECC 1바이트로 구성된다. 이어서 0~65,535바이트의 데이터 페이로드와 2바이트 체크섬으로 된 프레임 꼬리가 온다.

**원문 그림: MIPI-DSI 긴 패킷의 구성**

[원문 그림 보기](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_long_paket.png)

| 원문 그림 표기 | 한국어 번역 또는 값 |
|---|---|
| Packet Header (PH) | 패킷 헤더 |
| DI (Data Identification) | 데이터 식별자 |
| WC-LSB / WC-MSB (Word Count) | 페이로드 바이트 수의 하위 바이트 / 상위 바이트 |
| ECC (Error Correction Code) | 오류 정정 코드 |
| 헤더에 표시된 DI / WC-LSB / WC-MSB / ECC | `1C 05 00 29` |
| Packet Data (PD) | 패킷 데이터 |
| Data 0 / Data 1 / Data 2 / Data 3 / Data 4 | `89 23 12 A2 E2` |
| Packet Footer (PF) | 패킷 꼬리 |
| CRC-LSB / CRC-MSB | CRC의 하위 바이트 / 상위 바이트 |
| 그림의 CRC-LSB / CRC-MSB | `59 29` |
| B0 … B7 / LSB / MSB / Time | 비트 0 … 비트 7 / 최하위 비트 / 최상위 비트 / 시간 |

긴 그림은 시간축을 여러 줄로 접어 그렸다. 헤더 뒤에 5바이트의 페이로드가 이어지고, 그 뒤에 2바이트의 CRC가 전송된다. 이 그림의 헤더 ECC와 페이로드 CRC는 MATLAB 재계산 결과 모두 일치했다.

**예시: MIPI-DSI 긴 패킷의 타이밍**

[원문 파형 그림 보기](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_long_packet_example.png)

주요 필드는 전송 순서대로 다음과 같다.

- **ESC:** Escape 모드로 진입한다.
- **0x87:** LPDT, 저전력 데이터 전송 모드.
- **0x39:** 데이터 식별자. 원문에서는 DCS 명령 “DCS Write Long”에 해당한다고 설명한다.
- **0x03, 0x00:** 데이터 수. 명령 데이터 3바이트를 전송한다는 뜻이다.
- **0x09:** ECC, 오류 정정 코드.
- **0xB6, 0xB2, 0xB2:** 실제로 전송하는 명령 데이터.
- **0xEF, 0xFA:** 체크섬 필드.

#### 자주 쓰는 데이터 식별자 (DI)

아래 표는 원문 표를 그대로 번역한 것이다. **0x16과 0x37 행에는 원문 오류가 있으므로 분석 코드나 실제 장치 설정에 그대로 사용하지 않는다.** 정확한 값은 뒤의 교정 표를 참고한다.

| Data ID | 명칭 — 원문 의미 그대로 | 설명 — 원문 의미 그대로 |
|---|---|---|
| 0x05 | DCS 짧은 쓰기, 매개변수 0개 | 매개변수가 없는 DCS 명령을 보낸다. 예: Sleep Out 0x11. |
| 0x15 | DCS 짧은 쓰기, 매개변수 1개 | 매개변수 1개를 가진 DCS 명령을 보낸다. |
| 0x39 | DCS 긴 쓰기 | 여러 바이트의 데이터를 가진 DCS 명령을 보낸다. 메모리 쓰기에 흔히 사용된다. |
| 0x06 | DCS 짧은 읽기, 매개변수 0개 | 매개변수 없이 DCS 상태나 레지스터를 읽는다. |
| 0x16 | DCS 짧은 읽기, 매개변수 1개 **[원문 오류]** | 매개변수 1개로 DCS 상태나 레지스터를 읽는다. **[원문 오류]** |
| 0x37 | DCS 읽기 응답 **[원문 오류]** | 디스플레이가 반환하는 DCS 읽기 데이터. **[원문 오류]** |
| 0x03 | 범용 짧은 쓰기, 매개변수 0개 | 매개변수가 없는 범용 명령을 보낸다. |
| 0x13 | 범용 짧은 쓰기, 매개변수 1개 | 매개변수 1개를 가진 범용 명령을 보낸다. |
| 0x23 | 범용 짧은 쓰기, 매개변수 2개 | 매개변수 2개를 가진 범용 명령을 보낸다. |
| 0x29 | 범용 긴 쓰기 | 여러 바이트의 데이터를 가진 범용 명령을 보낸다. |
| 0x04 | 범용 읽기, 매개변수 0개 | 매개변수가 없는 범용 읽기 명령. |
| 0x14 | 범용 읽기, 매개변수 1개 | 매개변수 1개를 가진 범용 읽기 명령. |
| 0x24 | 범용 읽기, 매개변수 2개 | 매개변수 2개를 가진 범용 읽기 명령. |

### 디스플레이 명령 계층 (DCS Layer)

- **기능:** DCS(Display Command Set)는 디스플레이를 제어하기 위한 표준 명령 집합이다. 원문에서는 MIPI-DSI가 정의한 명령 집합이라고 설명한다. 호스트는 이 명령들을 통해 디스플레이와 상호작용한다. 이를 이용해 전원 켜기·끄기, 절전, 백라이트, 화면 켜기·끄기와 같은 디스플레이 모듈의 기본 제어를 수행한다. 또한 픽셀 형식, 표시 모드, 주소 설정과 같은 표시 매개변수를 구성하고, 이미지 데이터 쓰기나 상태 정보 읽기 같은 프레임 버퍼 접근을 수행한다.

DCS 명령은 DSI 버스에서 짧은 쓰기, 긴 쓰기, 읽기 명령의 형태로 전송되며, 애플리케이션 계층과 디스플레이 하드웨어 사이의 주요 제어 인터페이스가 된다.

**자주 쓰는 명령**

| 명령 코드 | 명칭 | 기능 설명 |
|---|---|---|
| 0x01 | Software Reset | 소프트웨어 리셋 |
| 0x11 | Sleep Out | 절전 모드에서 나옴 |
| 0x28 | Display Off | 화면 표시를 끔 |
| 0x29 | Display On | 화면 표시를 켬 |
| 0x2A | Column Address Set | 열 주소 범위를 설정 |
| 0x2B | Page Address Set | 페이지 주소 범위를 설정 |
| 0x2C | Memory Write | 프레임 버퍼 데이터를 씀 |
| 0x2E | Memory Read | 프레임 버퍼 데이터를 읽음 |
| 0x36 | Address Mode | 메모리 스캔 방향과 뒤집기 모드를 설정 |
| 0x3A | Pixel Format Set | RGB565 또는 RGB888 같은 픽셀 형식을 설정 |

### 색 형식 (Color Format)

**원문 그림: MIPI-DSI 색 형식**

[원문 그림 보기](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_color_format.png)

그림 제목인 **Display image data (24 bits)**는 **표시 이미지 데이터, 24비트**를 뜻한다. 상단의 `R7…R0`, `G7…G0`, `B7…B0`는 24비트 표시 데이터에서 각 색 성분의 비트 위치를 나타낸다. 그림은 16/18비트 입력 성분을 24비트 표현으로 확장하는 예를 나열한다.

| 그림의 행 | R 성분의 8비트 표현 | G 성분의 8비트 표현 | B 성분의 8비트 표현 |
|---|---|---|---|
| 24-bit | `R[7:0]` | `G[7:0]` | `B[7:0]` |
| 18-bit, EPF[1:0]=00, Note 1 | `R[5:0] 00` | `G[5:0] 00` | `B[5:0] 00` |
| 18-bit, EPF[1:0]=01, Note 2 | `R[5:0] 11` | `G[5:0] 11` | `B[5:0] 11` |
| 18-bit, EPF[1:0]=10 | `R[5:0] R[5:4]` | `G[5:0] G[5:4]` | `B[5:0] B[5:4]` |
| 16-bit, EPF[1:0]=00, Note 3 | `R[4:0] 000` | `G[5:0] 00` | `B[4:0] 000` |
| 16-bit, EPF[1:0]=01, Note 4 | `R[4:0] 111` | `G[5:0] 11` | `B[4:0] 111` |
| 16-bit, EPF[1:0]=10 | `R[4:0] R[4:2]` | `G[5:0] G[5:4]` | `B[4:0] B[4:2]` |

여기서 공백은 비트열을 이어 붙이는 위치를 나타내며, `Note 1…4`는 그림에 표시된 주석 번호다. 본 페이지에는 그 주석의 상세 설명이 함께 실려 있지 않으므로 추가 내용을 추정해서 번역하지 않았다. EPF 설정도 이 페이지에서 모든 DSI 패널에 공통인 설정으로 정의하지 않는다.

대부분의 MIPI-DSI LCD는 RGB565, RGB666, RGB888 등 여러 입력 색 형식을 지원한다. 호스트는 DCS 명령 0x3A, 즉 Pixel Format Set을 통해 디스플레이의 색 깊이를 설정할 수 있다. 예를 들면 다음과 같다.

- **RGB565, 16비트로 설정할 때:** `Command: 0x3A`, `Parameter: 0x55`를 전송한다. 구체적인 매개변수 값은 LCD 컨트롤러 데이터시트를 확인해야 한다.

픽셀 데이터는 일반적으로 긴 패킷으로 전송된다. 이 패킷에는 픽셀 데이터와 해당 데이터 유형 DT가 포함된다. 예를 들어 RGB565 형식의 픽셀 스트림은 일반적으로 `DT = 0x0E`, 즉 16비트 Packed Pixel Stream을 사용한다.

#### 설명 (Description)

- 16비트와 18비트 형식은 대역폭과 저장 공간을 줄이기 위해 흔히 사용된다.
- 24비트 형식은 높은 표시 품질이 필요한 경우에 적합하다.

#### 일반적인 색 형식과 데이터 유형

| 색 형식 | 색 깊이 | DCS 매개변수 예 | 데이터 유형 DT |
|---|---|---|---|
| RGB565 | 16비트 | 0x55 | 0x0E |
| RGB666 | 18비트 | 0x66 | 0x1E / 0x2E |
| RGB888 | 24비트 | 0x77 | 0x3E |

## 2. 검증 해설: 연구에서 반드시 구분할 내용

### 2.1 DI, DT, VC, DCS command는 서로 다른 필드다

고전적인 DSI 패킷에서 DI는 1바이트이며 `DI = (VC << 6) | DT`다. VC는 상위 2비트, DT는 하위 6비트다. 따라서 원문 표에서 0x05나 0x39를 그대로 DI로 부르려면 VC=0이라는 조건이 필요하다. 다른 VC를 쓰면 동일한 DT여도 DI의 1바이트 값은 달라진다.

DSI의 DT는 “어떤 종류의 패킷인가”를 표시하고, DCS command는 “디스플레이가 어떤 동작을 수행해야 하는가”를 표시한다. DCS는 DSI와 별도인 MIPI 명령 규격이며, DSI 패킷을 통해 전달될 수 있다.

예를 들어 Sleep Out을 VC=0의 DCS 짧은 쓰기로 보내는 패킷은 다음과 같이 해석한다.

```text
DI=05 | DCS command=11 | unused parameter=00 | ECC
```

원문의 긴 쓰기 예는 다음과 같다.

```text
ESC | 87 | DI=39 | WC=03 00 | ECC=09 | command=B6 | parameters=B2 B2 | CRC=EF FA
```

여기서 `B6 B2 B2`를 서로 독립인 명령 3개로 해석하면 안 된다. DCS Long Write 형식에서는 첫 바이트가 명령이고 나머지가 그 명령에 대한 데이터다. `B6`의 실제 의미는 대상 패널 컨트롤러의 명령 집합과 현재 명령 페이지 설정을 확인해야 한다. `WC=3`에는 명령 바이트도 포함되며, 헤더와 CRC는 포함되지 않는다.

같은 숫자라도 필드가 다르면 의미가 달라진다. 예를 들어 **DT 0x39는 DCS Long Write**, **DCS command 0x39는 Enter Idle Mode**다. **DT 0x3E는 RGB888 Video Mode pixel stream**, **DCS command 0x3E는 Read Memory Continue**다. 숫자만 검색해서 packet을 분류하면 잘못된 결과가 나온다.

근거: 사용자 보유 DSI v1.3 DRAFT §8.4–8.7, PDF 55–60쪽; §8.8.9, PDF 65–66쪽. 구현 교차 확인: [Linux mipi_display.h](https://raw.githubusercontent.com/torvalds/linux/master/include/video/mipi_display.h).

### 2.2 원문 DI 표의 두 행은 틀렸다

| 원문 내용 | 확인된 의미 | 전송 방향 |
|---|---|---|
| 0x16 = DCS Short Read, 1 Param | **Execute Queue** | 호스트 → 주변 장치 |
| 0x37 = DCS Read Response | **Set Maximum Return Packet Size** | 호스트 → 주변 장치 |
| 원문 표에 없는 DCS 1바이트 읽기 응답 | **DT 0x21** | 주변 장치 → 호스트 |
| 원문 표에 없는 DCS 2바이트 읽기 응답 | **DT 0x22** | 주변 장치 → 호스트 |
| 원문 표에 없는 DCS 긴 읽기 응답 | **DT 0x1C** | 주변 장치 → 호스트 |

0x37은 원문 짧은 패킷 파형 설명에서는 최대 반환 크기 설정이라고 올바르게 설명했지만, 바로 아래 표에서는 읽기 응답이라고 잘못 적었다. 또한 이를 DCS 명령이라고 부른 문장도 층을 혼동한 것이다. 0x37은 이 문맥에서 DSI packet data type이다.

근거: DSI v1.3 DRAFT Table 16, PDF 60쪽; §8.8.10, PDF 66–67쪽; [Linux의 host→peripheral 및 peripheral→host enum](https://raw.githubusercontent.com/torvalds/linux/master/include/video/mipi_display.h).

### 2.3 그림의 구성 예와 뒤에 붙인 LPDT 파형 예는 다른 패킷이다

짧은 패킷 **구성 그림**의 `DI=0x21`은 주변 장치→호스트 방향에서 해석하면 DCS 1바이트 읽기 응답이다. 그래서 Data0에 반환값 0x45, Data1에 미사용값 0x00이 들어간다. 반면 **타이밍 그림**의 `DI=0x37`은 호스트→주변 장치의 최대 반환 크기 설정이다. 모든 short packet의 Data1을 0으로 고정하는 규칙은 없다.

긴 패킷 **구성 그림**의 `DI=0x1C`는 주변 장치→호스트 방향에서 DCS Long Read Response로 해석된다. 뒤의 **타이밍 그림**은 `DI=0x39`인 호스트의 DCS Long Write다. 전송 방향을 모르면 0x21과 0x1C는 호스트가 보내는 별도의 DT와도 겹칠 수 있으므로, 그림의 바이트값만 보고 모든 DSI 전송에 공통인 예시로 취급하지 않는다.

두 **타이밍 그림**은 모두 `ESC → 0x87 → DSI packet` 순서를 보인다. 이들은 **LPDT 예시**다. D-PHY HS에서 SoT를 지난 후 DDR clock에 맞춰 전송하는 파형 예시가 아니다. LPDT는 저전력 신호 상태와 자체 클록 방식으로 데이터를 전달하므로, 이 파형에서 측정한 펄스 폭을 HS의 bit time이나 byte clock으로 환산하면 안 된다.

### 2.4 ECC는 헤더를, CRC는 긴 패킷의 페이로드를 보호한다

짧은 패킷은 `DI + Data0 + Data1 + ECC`로 된 4바이트다. 긴 패킷은 다음 구조다.

```text
DI[1] | WC[2] | ECC[1] | payload[WC] | CRC[2]
```

기본 4바이트 헤더의 ECC는 앞의 3바이트, 즉 24비트로부터 계산된다. 긴 패킷에서는 DI와 WC, 짧은 패킷에서는 DI와 두 데이터 바이트가 대상이다. ECC를 단순한 “오류 검출”로만 번역하면 정정 능력을 놓친다. 기본 DSI 헤더 코드는 1비트 오류 정정과 2비트 오류 검출을 지원한다. ECC가 픽셀 페이로드 전체를 정정해 주는 것은 아니다.

긴 패킷의 16비트 CRC는 페이로드에 대해 계산된다. DCS Long Write의 명령 바이트 역시 페이로드에 들어 있으므로 CRC 계산에 포함된다. WC와 CRC는 하위 바이트부터, 각 바이트 내부는 최하위 비트부터 전송된다. 예를 들어 `WC=03 00`은 0x0003, `CRC=EF FA`는 0xFAEF다.

따라서 stitching의 알려진 패턴 후보로 쓸 때는 **고정된 DI·WC로부터 ECC까지 계산할 수 있는 header**와 **화면 내용에 따라 달라지는 CRC**를 나눠야 한다.

이번 원문 예제는 MATLAB R2026b에서 별도로 재계산했다. 네 개 헤더와 두 페이로드의 보호 코드가 모두 일치했다. **DT 설명 표의 오류와 그림 예제의 보호 코드 정확성은 구분해야 한다.**

| 재계산 대상 | 계산 결과 | 원문과 일치 |
|---|---|---|
| Header `37 03 00` | ECC `01` | 일치 |
| Header `39 03 00` | ECC `09` | 일치 |
| Header `21 45 00` | ECC `01` | 일치 |
| Header `1C 05 00` | ECC `29` | 일치 |
| Payload `B6 B2 B2` | CRC 전송 바이트 `EF FA` | 일치 |
| Payload `89 23 12 A2 E2` | CRC 전송 바이트 `59 29` | 일치 |

재현 코드: `verification/verifyEspressifGuide.m`. 수치 기록: `verification/espressif_20261022/guide_verification.json`. 이는 문서 예제의 계산 검증이며 수집 IQ에서 packet을 검출했다는 뜻은 아니다.

근거: DSI v1.3 DRAFT §8.3–8.4.2, PDF 55–57쪽; checksum 관련 §9. 본 검토에서는 보호 범위와 endian 정책을 해당 페이지 전체로 대조했다.

### 2.5 RGB666은 “18비트 색”이어도 전송에 24비트를 쓸 수 있다

원문의 `RGB666: DT=0x1E / 0x2E`는 서로 같은 배치라는 뜻이 아니다.

| 형식 | DT | 유효 색 정보 | 전송되는 payload 크기 |
|---|---:|---:|---|
| RGB565 packed | 0x0E | 16bit/pixel | 2bytes/pixel |
| RGB666 packed | 0x1E | 18bit/pixel | **4pixels = 9bytes** |
| RGB666 loosely packed | 0x2E | 18bit/pixel | **3bytes/pixel = 24 transmitted bits/pixel** |
| RGB888 packed | 0x3E | 24bit/pixel | **3bytes/pixel** |

RGB666 packed는 6비트 R·G·B 성분을 빈틈없이 이어 붙인다. 따라서 pixel 경계가 byte 경계와 다시 일치하는 단위는 4pixels, 즉 9bytes다. RGB666 loosely packed는 각 색 성분을 하나의 바이트에 넣고 유효 6비트를 `[7:2]`에 둔다. 해당 바이트의 `[1:0]`은 수신 측에서 무시한다. “무시한다”는 것은 송신되는 두 비트가 반드시 0이라는 뜻은 아니다.

따라서 **RGB666 loosely packed는 RGB888과 동일한 payload byte 수를 사용**한다. 원문의 “18비트 형식은 대역폭을 줄인다”는 설명은 packed 형식에는 적용되지만 loosely packed 형식에 자동 적용되지 않는다. 또 링크 포맷과 MCU/SoC의 RAM 저장 형식은 별개이므로, RAM 용량 감소 역시 드라이버의 저장 방식까지 확인해야 한다.

원문 색상 그림의 EPF 행은 작은 색 깊이를 24비트 표시 값으로 확장하는 방법을 나타낸다. 이것을 DSI lane 위의 직렬 bit 배치도나 RGB666 packed/loosely packed 차이로 읽으면 안 된다.

근거: DSI v1.3 DRAFT §8.8.20–8.8.23, PDF 73–77쪽, 특히 Figure 36–38. 이 검토에서 PDF 74–77쪽을 직접 읽었다. [Linux DT 정의](https://raw.githubusercontent.com/torvalds/linux/master/include/video/mipi_display.h)와도 일치한다.

### 2.6 RGB888 가정과 사용자의 누설 신호 연구에 연결하기

RGB888의 Video Mode pixel stream은 DT=0x3E이고, 각 픽셀은 `R, G, B` 순서의 세 바이트로 전송된다. 각 바이트 내부는 LSB-first다. 반면 RGB888 데이터를 Command Mode의 메모리 쓰기로 보내면 DT=0x39인 DCS Long Write와 내부의 `0x2C` 또는 `0x3C` 명령을 고려해야 한다. RGB888이라는 색 형식만으로 패킷 DT를 하나로 단정할 수 없다.

알려진 header를 stitching이나 검출에 쓰려면 최소한 전송 방향, VC, video/command mode, WC, lane 수와 HS transmission 경계를 구분해야 한다. 이 페이지의 LPDT 파형은 packet 필드의 의미를 배우는 데 도움이 되지만, 현재 연구 대상인 고속 차동 방사의 반복 bit pattern을 그대로 제공하지는 않는다.

이번 문서 대조는 프로토콜과 원문 오류를 확인한 결과다. LG X2 또는 iPhone 6의 실제 packet, lane 설정이나 누설 경로를 검출했다는 의미는 아니다.

## 3. 대조 출처와 독해 기록

- 사용자 제공 전체 페이지 캡처: `codex-clipboard-6d1deffe-1b8b-463e-8943-d2bbb51a4add.png`, 1763×28291 pixels. Root가 만든 `cache/espressif_capture/capture_03.png` 및 `capture_04.png`에서 이 범위의 그림·표를 시각 대조했다. `capture_05`에 이어지는 Color Format 끝의 본문은 현재 웹 원문으로 확인했다.
- Espressif 현재 원문, 2026-10-22 열람: 웹 본문 Protocol Layer부터 Color Format 마지막 표까지, 원문 anchor `#protocol-layer` ~ `#common-color-formats-and-data-types`. 이 구간의 문장·목록·표 3개 및 그림 5개의 표제와 주요 표기를 번역했다.
- 사용자 보유 *MIPI Alliance Specification for DSI*, v1.3, 23-Mar-2015, **DRAFT**: `C:/Users/leechanghoon/Desktop/MIPI_Alliance_Specification_DSI/MIPI_Alliance_DSI_ver1.3.pdf`. 관련 PDF 54–57, 59–60, 66, 74–77쪽을 읽었으며 본문 인쇄 페이지 번호는 PDF 번호보다 12 작다. PDF 92–93쪽은 DCS/DSI 계층 분리의 부가 확인으로 읽었다. 원문 PDF나 전체 추출문은 이 번역 파일에 재배포하지 않는다.
- Linux upstream `include/video/mipi_display.h`, 2026-10-22 열람: host→peripheral DT, peripheral→host DT, DCS command, pixel format enum. `master` URL이므로 규범 문서의 버전을 대신하지 않는 구현 교차 확인이다. <https://raw.githubusercontent.com/torvalds/linux/master/include/video/mipi_display.h>
