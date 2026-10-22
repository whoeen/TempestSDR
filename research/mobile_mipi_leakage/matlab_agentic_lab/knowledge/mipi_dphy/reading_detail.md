# 확보 문서 전체 텍스트 독해 기록

2026-10-22 KST · cycle_002 · 담당 `mipi_dphy_research`

## 현재 완료 범위

| 문서 | 텍스트 독해 | 시각 확인 | 남은 확인 |
|---|---:|---:|---|
| 사용자 보유 DSI v1.3 | 119 / 119 PDF 페이지 | 선택 18페이지 | 그 외 101페이지의 시각 전수검사, 공식 배포본·정오표 대조 |
| Arasan Total MIPI Camera IP Solution | 55 / 55 PDF 페이지 | 선택 18페이지 | 그 외 37페이지의 시각 전수검사, 저해상도 embedded pin 그림의 모든 미세 문자 확인 |

페이지별 기록은 `page_reading_coverage.jsonl`이다. `text_read`는 실제로 도구에 표시된 텍스트를 읽었음을 뜻한다. 추출문 길이와 해시는 감사용이며 자동으로 독해 완료를 결정하지 않았다. 첫 DSI 출력에서 잘린 PDF 13–14는 별도 호출로 다시 읽었다. 원문 PDF·페이지 렌더·전체 추출문은 Git에 추가하지 않았다.

이 기록은 확보된 두 PDF에 대한 것이며, 문서가 참조하는 D-PHY/DCS/DSC 규격이나 다른 업체·연도·논문까지 읽었다는 뜻이 아니다.

## DSI v1.3: 확인한 내용

본문의 인쇄 페이지는 PDF 페이지에서 12를 뺀 값이다. 첫 사이클 36쪽, 추가 사이클 83쪽으로 전체 텍스트를 확인했다.

| PDF 페이지 | 읽은 범위와 검토 내용 |
|---|---|
| 1–12 | 표지·권리 표시·목차·그림/표 색인·version history·의도적 blank page 확인. 후반 본문에는 DRAFT header가 있어 공식 배포본 인증 여부를 별도로 남김. |
| 13–21 | Scope가 전기적 상세 규격을 포함하지 않는다는 점, shall/should/may의 차이, frame/line/codestream/payload 용어, DCS·DBI·DPI·CSI·D-PHY·SDF·DSC 참조 관계 확인. |
| 22–30 | PHY / lane management / low-level protocol / application 계층, command/video 및 continuous/noncontinuous clock, 초기화 조건과 ULPS 관련 경계 확인. |
| 31–35 | byte round-robin lane 분배와 총 byte 수가 lane 수로 나누어떨어지지 않을 때의 lane 종료 시점 차이 확인. PDF 35 Figure 9에서 lane 0: byte 0,3,6… 배치를 이미지로 확인하여 추출 텍스트 순서의 혼동을 해소. |
| 36–44 | 선택적 split-link 구성, 공통 logical clock, 균등 payload 분배, sub-link 간 skew, 좌우 DDIC의 frame-buffer 좌표 분리 확인. PDF 43 Figure 17 시각 확인. 현재 A7의 single-DSI 설정을 split-link로 단정하지 않음. |
| 45–52 | SoT/SoT Sync/EoT Sync/Escape/LP Sync/False Control 오류, host/peripheral 별 처리 표, timeout 순서, ACK 보고 후 오류 clear 확인. 특히 §7.2.2.2 Common Mode fault와 방사 용어를 구분. PDF 48 표를 시각 확인. |
| 53–62 | short/long packet, WC, DI/virtual channel, endian, host data-type 표 및 frame synchronized transaction을 확인. PDF 60의 명령·pixel format 목록을 이미지로 대조. |
| 63–66 | VSS의 stereoscopic control bit 표, EoTp 고정 형식과 송수신 지원 조건, color mode·display on/off, generic/DCS read/write 및 maximum-return-size 명령을 확인. 즉시 복원에 쓰지 않는 제어 명령도 건너뛰지 않음. |
| 67–77 | Null·blanking·generic long write와 모든 제시된 YCbCr/RGB pixel packing을 읽음. 20-bit YCbCr의 padding, packed/loose RGB666, RGB565/888, 30/36-bit의 byte 경계와 채움 bits를 확인. PDF 68,71,72,75,76,77 그림을 대조. |
| 78–80 | 압축 stream의 slice-width 배치, compression mode와 PPS selector, Execute Queue, reserved DT, 역방향 lane 제한을 확인. |
| 81–86 | 역방향 LP packet, BTA, ECC와 optional checksum, ACK/오류 누적·clear, read-response type 표를 확인. PDF 84 error-bit 표를 이미지로 대조. 오류 수신과 실제 IQ에서 오류를 관측한 사실을 혼동하지 않음. |
| 87–94 | non-burst sync pulse/event, burst video timing, peripheral timing 요구, TE와 local timing controller, compressed video/command의 조건 확인. PDF 91 burst 그림은 첫 사이클에서 시각 확인. |
| 95–102 | modified Hamming ECC, syndrome/parity 표, D0–D23 적용 범위와 D24–D63 정보용 행, CRC polynomial·초기값·LSB 전송, reconstructed-image test checksum의 색 공간 위치를 확인. PDF 96,101 시각 확인. |
| 103–105 | resolution 목록, 필수/선택 pixel formats, lane 수, 최대 lane frequency의 제조사 명세 책임, bidirectional 조건, display architecture와 EoTp 구형 호환성 확인. 이 표를 현재 단말의 실제 설정으로 사용하지 않음. |
| 106–111 | LP contention 세 경우의 host/peripheral 처리, stop state, timer, 선택적 reset 표·flowchart의 추출문을 읽음. 이 flowchart 전부의 화살표를 시각 검사했다고 주장하지 않음. |
| 112–113 | CRC C/C++ 예제, bitwise 갱신, 4개 입력/결과 vector를 읽음. PDF 112 주석을 시각 확인하여 본문 polynomial과의 불일치를 기록. |
| 114–115 | optional interlaced first/second-field timing과 HSS 함의 차이를 읽음. 현 스마트폰에 interlace가 사용되었다는 추론은 하지 않음. |
| 116–119 | DSC 1.1 profile 8/12/generic, slice·buffer·delay·rate-control 관련 표, PPS update 적용 시점과 구현 지침을 읽음. PDF 117의 표와 119의 적용 시점 도식을 시각 확인. |

**시각 확인한 DSI PDF 페이지:** 31, 35, 43, 48, 60, 68, 71, 72, 75, 76, 77, 84, 91, 96, 101, 112, 117, 119.

### 원문 내부 불일치와 처리 방침

1. **CRC polynomial 주석:** PDF 112 / 인쇄 100, source line 2516은 x^15 항을 적었지만 본문 §9.6과 Figure 49(PDF 100–101)는 x^12 항을 사용하며 예제 상수도 reflected 0x8408이다. 두 페이지를 시각 확인했다. 공식 erratum을 확보한 것은 아니므로 `document_observation`으로 기록했다.
2. **1-pixel 30/36-bit packet 예시:** PDF 71–72 / 인쇄 59–60에 표시된 WC=1과 뒤에 보이는 payload 4/5 byte가 WC 정의와 맞지 않는다. 그림과 본문 hex를 확인했으며 새 정답 hex를 임의로 확정하지 않았다. 구현 전 normative 규칙 및 독립 vector 대조가 필요하다.
3. **표와 도식의 추출 순서:** Figure 9처럼 표/그림 속 byte label이 텍스트 추출 순서만으로는 오해될 수 있다. lane mapping과 중요 bit packing은 이미지로 확인했다.
4. 문서의 DRAFT header와 cover/version 표시는 그대로 provenance에 남겼다. 문서가 사용자 보유본이라는 사실과 공식 배포본 인증은 다른 검증이다.

## Arasan: 확인한 내용

본문의 인쇄 페이지는 PDF 페이지에서 6을 뺀 값이다. 첫 사이클 10쪽, 추가 사이클 45쪽으로 전체 추출 텍스트를 읽었다.

| PDF 페이지 | 검토 기록 |
|---|---|
| 1–8 | 범위·저작권·목차·업체 소개 확인 |
| 9–15 | CSI-2 송신 블록, buffering/clock domain, interface, 검증 환경 확인 |
| 16–24 | CSI-2 수신 블록·format·lane merger·FIFO·ISP, pinout/검증 환경 확인 |
| 25–40 | C-PHY와 D-PHY 구조 비교, pad/전원/trim, HS handshake, escape/ULPS/BTA, 오류·deskew·timing-count 표 확인 |
| 41–44 | D-PHY 동작 범위·HS/LP 구조·clock 분리 확인 |
| 45–54 | lane/power/trim/reset, PPI, sideband·DFT·timing·BIST 표 및 deliverables 확인 |
| 55 | 지원·라이선스 설명 확인; 현재 상업 조건으로 재검증한 것은 아님 |

이 자료는 IP 구현 소개이므로 pin과 timing-count 입력을 삼성 단말의 register 주소로 사용하지 않는다. HS 전압 swing은 수신 AM/PM 변조도가 아니다. Deskew burst 제어가 있다고 해서 A7에서 해당 burst가 측정됐다고 주장하지 않는다.

**시각 확인한 Arasan PDF 페이지:** 8, 11, 12, 14, 15, 18, 19, 21, 23, 24, 26, 27, 30, 38, 42, 43, 44, 53.

PDF 21은 실제 blank page였다. PDF 42의 도식은 MuPDF 렌더에서 어둡게 나타나 Poppler로 다시 렌더한 후 확인했다. PDF 14의 작은 embedded pin 문자는 해상도 한계가 있어 topology 검토와 모든 세부 label 판독을 구분한다. C-PHY revision 표기와 일부 수치/설명에 편집상 불일치가 있으므로 현재 기기의 규범적 사양으로 사용하지 않는다.

## 다음 연구에 넘기는 구체적 항목

- HS burst segmentation에 active payload, blanking/null, LP control, calibration 후보를 분리해 검토한다.
- capture metadata의 Fs/BW와 실제 packing·update cadence를 연결한 뒤 samples/pixel을 계산한다.
- phase hue의 경사는 CFO/시간축 오차로도 생길 수 있다. 물리적 source 판정과 시각화 해석을 나눈다.
- 앞으로 byte decode를 구현하면 ECC 범위, WC, CRC 규칙을 검증된 vector로 시험한다. 이번 독해가 serial payload decode 성공을 뜻하지 않는다.
- 모든 문서·모든 실험의 학습 완료를 선언하지 않고, 새 측정과 문헌의 근거를 같은 DB에 계속 추가한다.
