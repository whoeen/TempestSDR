# 과거 sweep에 대한 사용자 추가 진술
날짜: 2026-10-22. 출처: 현재 채팅의 사용자 답변. 실측 로그 대신 기억에 근거한 정보다.

| 항목 | 최신 기록 | 증거 상태 |
|---|---|---|
| iPhone 6 탐색 기준 | Screen Gleaning에서 언급한 주파수 주변을 관찰 | 사용자 기억 |
| iPhone 6 중심주파수 이동 폭 | 약 150 MHz | 근사·사용자 기억 |
| 절대 시작/끝 중심주파수 | 미상 | 추정해서 채우지 않음 |
| 당시 수신 BW | 120 MHz로 기억하나 불확실 | 미확인 설정 |
| 당시 저장 Fs | 기록을 찾아야 확인 가능 | 미상 |
| 당시 중심주파수 간격 | 미상 | 미상 |
| LG sweep 범위 | 기억나지 않음 | 미상 |

## 논문에서 확인한 별도 사실
Screen Gleaning, NDSS 2021, Table II(캐시된 author preprint p6):
- iPhone 6-A/B/C: strongest leakage center 105 MHz.
- iPhone 6s: 295 MHz.
- Section IV-A.3(p5): 수집 BW12.5 MHz, Fs25 MS/s.
- p5 SNR 표를 위한 50 MHz 분석폭과25 kHz resolution은 위 수집 BW와 구분한다.

[NDSS 원문](https://www.ndss-symposium.org/wp-content/uploads/2021-021-paper.pdf).
이번 확인은 로컬 캐시 knowledge/tempest/cache/pdf/gleaning2021.pdf의5–6쪽 텍스트와6쪽 원본 TableII 시각 대조를 사용했다. 이 논문 전체 재독을 의미하지 않는다. 기존 source_id=gleaning2021.

이 수치는 선행연구의 측정점이다. 사용자 sweep가105 MHz 중심 또는105 MHz에서 시작했다고 확정하지 않는다. 6s의295 MHz를6의 값으로 바꾸지 않는다. 기존 사용자238 MHz 파일의 중심도 그대로 유지한다.

## 측정안의 수정
1. 이전 “약100 MHz 범위 sweep”라는 표현보다 최신 iPhone6의 **약150 MHz center span** 기억을 우선한다.
2. 120 MHz 장비 옵션과 당시 실제 수집에 설정한120 MHz BW를 구분한다. 기존 파일명/외부기록의 BW60 MHz(238/308 MHz),49 MHz(312 MHz)는 이 회상만으로 덮어쓰지 않는다. 같은 실험인지도 미확인이다.
3. 각 band의 유효 폭이 B_use이고 중심들이 끊김 없이 이어지면 전체 RF union 폭은 center span+B_use다. 예를 들어150+120=270 MHz는 **가정하 기하학적 계산**이며 실제 유효 합성 폭·정보 대역을 확인한 값이 아니다.
4. 양 끝 중심150 MHz 간격의 두 band만 있다면 폭120 MHz에서는30 MHz gap이 생긴다. 중간 tuning 목록/간격 확인 없이 “270 MHz를 수집·stitch했다”고 기록하지 않는다.
5. 새 설계에서 B_use100 MHz/step50 MHz를 택한다면150 MHz center span은 f_start+[0,50,100,150] MHz의4개 중심, adjacent overlap50 MHz, 총 union250 MHz가 된다. **새 측정 설계 예시**이며 과거 step이나 주파수 범위의 복원이 아니다. f_start는 실제 재탐색 후 정한다.
6. 다음 재탐색은 논문105 MHz 부근과 기존238 MHz 측정점을 후보로 삼되 두 값 사이 전체가 성공 대역이라고 가정하지 않는다. LG는 기존344.8 MHz 지점을 먼저 재방문한다.
