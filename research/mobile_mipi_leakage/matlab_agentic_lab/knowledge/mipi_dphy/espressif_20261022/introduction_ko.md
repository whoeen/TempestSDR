# MIPI DSI LCD 상세 가이드 — 전체 한국어 번역과 검증 해설

**Espressif 문서 · 사용자 첨부 전체 페이지 캡처 대조 · 2026-10-22**

사용자가 제공한 1763×28291 픽셀의 전체 페이지 캡처를 번역했다. [Espressif의 같은 웹페이지](https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/mipi_dsi_lcd.html)와 문서 소스를 대조하여 작은 글씨와 가로 스크롤 밖 코드를 보완했다. 용어집부터 관련 문서·페이지 하단까지의 본문, 표, 코드, 그림 10개를 포함한다. 그림 내부의 영어 표기는 그림 아래의 번역 표와 설명으로 옮겼다.

**읽는 방법:** ‘원문 번역’은 원문의 주장과 예제 수치를 보존한다. 오기나 부정확한 설명에는 표시를 달고, ‘검증·해설’에서 근거와 함께 정정한다. 코드 식별자·수치·문자열은 유지하고 설명 주석을 번역했다. 이 문서는 Espressif의 검토·승인을 받은 공식 번역본은 아니다.

원문은 **ESP32-P4의 LCD 구동 안내**다. DSI 일반 개념과 ESP32-P4 구현 제한이 함께 쓰여 있으므로, 이 예제를 LG X2·iPhone의 실제 설정으로 해석하지 않는다.

## 먼저 확인할 원문 오류와 해석상의 주의점

| 항목 | 원문 | 검증 결과 |
|---|---|---|
| DSI 전송률 계산 | 8b/10b 때문에 ×1.25 | 이 문서의 clock-lane 기반 D-PHY HS 전송에는 일반적인 8b/10b 계수를 적용하지 않는다. |
| Pixel clock 예제 | 844×1324×60 = 62.4 MHz | **67.04736 MHz**가 맞다. 코드의 60 MHz는 같은 porch에서 **약 53.693389 Hz**다. |
| ULPS | Escape 0x84 | **0x84는 ACK trigger**에 해당한다. ULPS entry의 LSB-first byte 표기는 **0x78**이다. |
| 패킷 종류 표 | 0x16 = DCS read, 0x37 = DCS read response | **0x16 = Execute Queue**, **0x37 = Set Maximum Return Packet Size**다. |
| 파형의 전송 방식 | Short/Long packet 예시 | 그림의 ESC → 0x87은 **LPDT**다. HS DDR의 bit time을 읽는 파형이 아니다. |
| UI와 속도 | UI 2–12.5 ns → 20–500 Mbps | 역수를 취하면 **80–500 Mbps**다. |
| 코드 | 예제 그대로 사용 | dbi_config 누락, callback 인자 타입, SDK 버전에 따른 필드 변경을 확인해야 한다. |

위 정정의 출처와 적용 범위는 각 부의 해설에 기록했다. 문서 그림의 **4개 header ECC와 2개 payload CRC는 MATLAB 검산과 모두 일치**했다. 맞는 예제와 틀린 설명을 구분하여 읽으면 된다.

## 문서 구성

1. **제1부:** 용어, 화면 갱신 원리, D-PHY의 HS·LP·Escape·BTA·ULPS.
2. **제2부:** Short/Long packet, DI·DT·VC, DCS, RGB565·RGB666·RGB888.
3. **제3부:** ESP32-P4 드라이버 구성, 코드 전체, 문제 해결 8항목, 관련 문서.
4. **연구 연결:** lane 속도와 byte clock, 알려진 packet의 활용, stitching에 필요한 관측 조건.
5. **검산 및 출처:** MATLAB 결과, 대조 범위, 라이선스·변경 고지.

---
