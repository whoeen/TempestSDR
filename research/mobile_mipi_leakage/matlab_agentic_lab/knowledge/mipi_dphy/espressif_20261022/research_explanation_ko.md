## 연구 연결 — 스마트폰 누설 신호에 적용할 부분

### 1. 세 가지 속도의 정의

별도 clock lane을 사용하는 일반적인 D-PHY HS DDR에서 한 data lane의 직렬 bit rate를 **R_lane**으로 정의하면:

```text
R_lane = 2 × f_DDR = 8 × f_byte
T_bit  = 1 / R_lane
T_byte = 8 / R_lane
```

| 원문 예제의 설정 | 환산한 값 | 의미 |
|---|---:|---|
| lane_bit_rate_mbps = 1300 | R_lane = 1.3 Gbit/s | 한 lane의 직렬 bit rate |
| Forwarded DDR clock | f_DDR = 650 MHz | 한 주기에 두 bit 전송 |
| Byte clock | f_byte = 162.5 MHz | lane 하나의 초당 byte 수에 대응 |
| One bit | 약 0.76923 ns | HS 한 bit의 시간 |
| One byte on one lane | 약 6.15385 ns | HS 한 byte의 직렬화 시간 |

이는 **원문 예제 설정의 환산값**이다. 스마트폰 실측값이나 RF 중심주파수 fc로부터 바로 정해지는 값이 아니다. 스펙트럼의 한 피크만으로 그것을 f_byte, f_DDR 또는 R_lane에 대응시키면 안 된다.

RGB888 payload는 3bytes/pixel이다. Active payload를 끊김 없이 보내고 overhead를 제외한 순간 전송 능력은 **L×R_lane/24 pixels/s**다. 이것이 실제 pixel clock과 같으려면 blanking, burst duty, packet 배치 등의 조건이 추가로 필요하다.

### 2. Lane 분배는 byte 순서를 기준으로 본다

RGB888 네 픽셀의 byte stream은 다음과 같다.

```text
R0 G0 B0 R1 G1 B1 R2 G2 B2 R3 G3 B3
```

4-lane에서 첫 payload byte가 lane 0에 놓인다고 가정하면:

| Byte clock tick | Lane 0 | Lane 1 | Lane 2 | Lane 3 |
|---:|---|---|---|---|
| 0 | R0 | G0 | B0 | R1 |
| 1 | G1 | B1 | R2 | G2 |
| 2 | B2 | R3 | G3 | B3 |

Lane마다 특정 색 하나만 전달하는 구조가 아니다. **4pixels의 12bytes가 3개 byte clock tick에 분배**된다. 앞의 header, 같은 HS transmission에 앞서 있던 packet 길이, lane distributor의 시작 상태가 다르면 표의 lane 시작 위치가 달라질 수 있다. 새로운 packet마다 무조건 lane 0부터 다시 시작한다고 가정하면 반복 template의 위상을 잘못 만들 수 있다.

기존 근거와 MATLAB 예제는 [RGB888 속도·lane 정리](../rgb888_rates_lanes_20261022.md)에 기록했다.

### 3. Known packet 후보와 확인 조건

| 후보 | 알 수 있는 부분 | 확인할 조건 |
|---|---|---|
| HS 진입 및 SoT | 정의된 물리 계층 동기 패턴 | lane별 진입 시점, HS burst 주기, 수신 대역에서의 파형 |
| Video pixel packet header | VC·DT·WC를 알면 ECC까지 계산 가능 | Video Mode 여부, packet당 pixel 수, 행별 packet 구성 |
| DCS memory write header | DT·WC·command 0x2C/0x3C 후보 | Command Mode·메모리 쓰기 방식, 갱신 영역·빈도 |
| Sync/blanking/null packet | 일부 필드·길이의 반복 가능성 | 모드와 구현에 따른 삽입 위치·내용 |
| ACK·TE·LPDT | 정의된 제어 bit pattern | 발생 여부·빈도, LP 이벤트와 HS 영상 전송의 구분 |
| Payload CRC | payload가 알려져 있으면 계산 가능 | 화면 내용이 바뀌면 일반적으로 함께 바뀜 |

초기화 명령은 전원을 켤 때 한 번 전송될 수 있다. **고정된 값과 주기적으로 반복되는 값은 다른 조건**이다. 반면 일정한 row payload 길이를 가진 video packet header는 화면 내용이 변해도 일부가 반복될 수 있으므로 준주기성 후보가 될 수 있다.

원문의 **ESC → 0x87 → packet은 LPDT**다. 이를 HS 영상 누설의 bit template로 그대로 복사하지 않는다. 같은 packet 내용도 LPDT와 HS에서 전기적인 파형과 시간 척도가 달라진다.

### 4. Stitching에서 packet 지식의 역할

Packet 지식은 수집 구간들에서 **같은 프로토콜 이벤트를 대응시키고 시간·주파수·위상 정렬 후보를 줄이는 데** 사용할 수 있다. 그러나 알려진 bit pattern만으로 안테나의 복소 RF 파형이 정해지지는 않는다. Lane별 결합 세기·위상, 공통 모드 변환, 전파 경로, 수신 필터와 LO 위상이 함께 작용한다.

1. 단색·RGB stripe 등 알려진 화면으로 실제 반복 주기와 재현성을 측정한다.
2. HS/LP, video/command, lane 수·rate 후보를 구분하고, template를 수신 대역과 샘플링률에 맞게 모델링한다.
3. 인접 RF 수집 대역의 겹치는 부분에서 gain·상대 phase·delay·frequency drift를 추정한다. Packet anchor는 같은 이벤트를 대응시키는 보조 근거로 쓴다.
4. 정렬에 사용하지 않은 frame이나 화면 패턴으로 복원 개선을 확인한다.

넓은 중심주파수 범위에서 각각 복원된다는 관측은 **다대역 stitching을 시도할 근거**다. 복소 스펙트럼의 위상 정합과 coherent stitching의 성립 여부는 정렬 후 추가로 검증할 대상이다.

### 5. 세로줄의 발생원은 이 문서만으로 확정되지 않는다

같은 x 위치에서 반복되는 packet/blanking 구조가 raster화 과정에서 세로줄로 보일 수 있다. Panel source/column driver의 주기적 구동도 후보다. 줄 모양이나 행렬 rank만으로 발생 회로를 구분할 수 없다.

구분에 도움이 되는 것은 **표시 패턴에 따른 줄의 위치·위상 변화**, **packet·행·프레임 주기와의 관계**, **수신 대역·안테나 위치에 따른 변화**다. 이 문서는 DSI 전송 구조를 제공하며 특정 스마트폰 panel driver의 방사 발생원을 확인한 결과는 아니다.

## MATLAB 검산 기록

MATLAB R2026b에서 원문 산술과 보호 코드 예제를 실행했다. 문서의 계산 검증이며 스마트폰 IQ의 packet 검출이나 ESP32 C 코드 빌드 결과는 아니다.

| 검산 항목 | 결과 |
|---|---|
| H_total, V_total | 844, 1324 |
| 60 Hz일 때 pixel clock | 67.04736 MHz |
| RGB888 raster 환산 rate, 전체 | 1609.13664 Mbit/s |
| 같은 환산 rate, 2-lane으로 분배 | 804.56832 Mbit/s/lane |
| Active pixel payload만의 frame 평균 | 737.28 Mbit/s/lane |
| 행마다 long packet 1개, header+CRC만 추가한 frame 평균 | 739.1232 Mbit/s/lane |
| Pixel clock 60 MHz일 때 frame rate | 약 53.693389 Hz |
| 원문의 1497.6×1.25×1.15 산술 | 2152.8 |
| 원문 4개 header ECC / 2개 payload CRC | 모두 일치 |
| 별도 2개 header 참조 벡터 | 모두 일치 |
| MATLAB Code Analyzer | 문제 0개 |

**Frame 평균 rate와 raster 환산 rate는 실제 필요한 DSI lane rate의 확정값이 아니다.** 사용 가능한 HS 전송 시간, LP 구간, packet 종류, lane tail, panel 제약을 별도로 계산해야 한다.

- 실행 코드: [verifyEspressifGuide.m](../../../verification/verifyEspressifGuide.m)
- 수치 결과: [guide_verification.json](../../../verification/espressif_20261022/guide_verification.json)
- 원본·대조 범위 기록: [provenance.json](provenance.json)

## 출처·저작권·변경 고지

**번역 대상:** Espressif Systems, *MIPI DSI LCD Detailed Guide*, 사용자 첨부 전체 페이지 캡처 및 2026-10-22의 [공식 웹페이지](https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/mipi_dsi_lcd.html). [RST 소스](https://github.com/espressif/esp-iot-solution/blob/master/docs/en/display/lcd/mipi_dsi_lcd.rst)와도 대조했다. latest/master는 변경될 수 있으므로 당시 파일 hash를 기록했다.

원문 저작권: **© 2016–2026 Espressif Systems (Shanghai) CO., LTD.** 저장소의 [Apache License 2.0](https://github.com/espressif/esp-iot-solution/blob/master/LICENSE)을 [동봉](LICENSE-ESPRESSIF-APACHE-2.0.txt)했다. 그림은 사용자가 제공한 캡처에서 추출했으며 원문의 링크와 귀속을 보존했다. 그림에 포함된 제3자 자료의 권리가 새로 작성한 번역자에게 이전되는 것은 아니다.

**변경 내용:** 한국어 번역, 캡처에서 그림 분리, 그림 표기의 한국어 설명, 오류 정정, 수치 검산, 스마트폰 연구 해설을 추가했다. 번역 구간에서는 코드 식별자·수치·문자열을 유지했다. Espressif의 공식 번역이나 공식 errata는 아니다.

**교차 검증 자료:**

- [TI DS90UR910-Q1 데이터시트](https://www.ti.com/lit/ds/symlink/ds90ur910-q1.pdf), Rev. E, PDF p.19 Figure 13: D-PHY ULPS entry·유지·종료. CSI packet 규칙을 DSI에 적용하지 않았다.
- 사용자 보유 *MIPI Alliance Specification for DSI*, v1.3, 23-Mar-2015, DRAFT: packet·ECC·CRC·ACK·TE·RGB 형식의 해당 절. 공식 배포본 여부와 최종 규격 지위는 별도 확인 대상이며 원문 전체를 재배포하지 않았다.
- [Linux mipi_display.h](https://raw.githubusercontent.com/torvalds/linux/master/include/video/mipi_display.h): 방향별 DT와 DCS command의 구현 교차 확인.
- [ESP-IDF DSI LCD API](https://docs.espressif.com/projects/esp-idf/en/stable/esp32p4/api-reference/peripherals/lcd/dsi_lcd.html) 및 [release/v6.0 헤더](https://github.com/espressif/esp-idf/blob/release/v6.0/components/esp_lcd/dsi/include/esp_lcd_mipi_dsi.h): callback·config 필드의 버전 확인.
- [EK79007 컴포넌트 2.0.2~1 예제](https://components.espressif.com/components/espressif/esp_lcd_ek79007/versions/2.0.2~1/readme): DBI config 초기화.

용어집, 프로토콜·색 형식, 드라이버, Common Issues 8항목, 관련 링크·footer를 대조했다. 연결된 외부 문서 전체를 모두 읽었다는 의미는 아니다. 세부 열람 범위와 접근 실패는 각 부와 지식 DB에 기록했다.
