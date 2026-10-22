# LG X2 / iPhone 6 stitching 측정안 v1.1
2026-10-22 — **측정 준비안. 새 RF 수집과 실측 stitching은 아직 실행하지 않음.**
[원문 검토](README.md), [장비 근거](hardware_notes.md), [기존 파일 근거](mobile_capture_inventory.md).

## 연구 질문
고정된 스마트폰 화면에서 서로 다른 RF 구간의 **복소 파형**을 같은 source-time 격자로 정렬하여, 단일 수신 대역보다 더 많은 화면 관련 주파수 정보를 복원할 수 있는가?

최신 사용자 기억에 따르면 iPhone6은 Screen Gleaning의 주파수를 참고하여 중심주파수를 약150 MHz 범위에서 이동하며 복원을 관찰했다. 시작/끝·step·Fs는 미상이고, 당시 수신 BW120 MHz도 확인이 필요하다. LG 범위는 미상이다. [사용자 진술과 논문 대조 기록](HISTORICAL_SWEEP_NOTE_KO.md)을 기준으로 삼는다. 성공 여부는 겹치는 구간의 신호 동일성, 추가 구간이 제공하는 화면 정보, 별도 검증 구간의 재현성으로 판정한다.

## A. 수집 전에 고정할 항목
- 대상: LG X2와 **iPhone 6**. iPhone 6s의 311 MHz 자료는 별도 장치다.
- 사용자 장비: USRP-2940R 120 MHz 옵션. 라벨/board ID, 실제 사용 VI/driver/FPGA/host 경로를 metadata에 남긴다. 기존 동작 경로를 우선 사용한다.
- 후보 raw Fs=200 MS/s, I/Q 각 int16이면 800 MB/s. 실제 API 반환 Fs와 overflow/sequence continuity를 확인한다. 120 MHz RF 폭이 120 MS/s 설정을 의미하지 않는다.
- 120 MHz 중 실제 비교에 쓰는 B_use는 RF/DDC 응답과 신호를 보고 선택한다. 아래 100 MHz는 **검증 전 후보**다.
- gain/antenna/probe/위치/편파/충전상태/밝기/온도상태 고정. AGC 및 tune별 auto-normalization이 있다면 설정과 실제 변화 기록. ADC clipping과 DC correction 상태 기록.
- 화면은 저장된 pattern/hash로 재현하고 애니메이션·시계·밝기 자동변화를 통제한다. 정적인 사진이라고 DSI 전송도 동일 주기로 반복된다고 가정하지 않는다.
- 원본 IQ를 읽기 전용 보존. 하드웨어 반환 format, endian, scaling, channel order를 확인한다. 기존 RIS의 big-endian int16 규칙을 새 API 출력에 자동 적용하지 않는다.

## B. 수집 세 단계
### B1. 한 번의 wideband 수집에서 가상 subband 검증
기존 성공 중심 f0에서 usable 100 MHz를 확보할 수 있다면:
- 직접 받은 전체 100 MHz 복소 IQ를 기준 파형으로 보관한다.
- 이 한 파형에서 **50 MHz × 3**, center offsets −25/0/+25 MHz, overlap 25 MHz의 가상 subband를 만든다.
- 별도의 합성 phase, finite delay, rate error, CFO를 주입해 정렬하고 원래 wideband와 비교한다. 합성 변형 수치와 원본 sample range를 기록한다.
- 이 단계는 알고리즘·filter edge·resampling·gain 보존을 검증하며, 실제 retune 재현성을 증명하지 않는다.
- 출력: 직접 wideband vs stitched complex NRMSE, amplitude/phase residual vs RF frequency, 스펙트럼 경계 ripple, edge/문자 복원. 맞추는 데 쓰지 않은 시간·주파수 구간에서 평가한다.

### B2. 두 band를 실제 retune하여 정합 가능성 확인
- A→B→A 순서로 동일 화면을 수집한다. 먼저 같은 중심의 A 반복으로 시간적 재현성을 구한다.
- A/B 사이에 충분한 **화면 관련** overlap이 있는 주파수를 고른다. 강한 단일 clock tone만 공유하면 delay와 scalar phase가 서로 구별되지 않을 수 있다.
- 모든 band에서 source timing을 추정한다. frame/row folding이 유효한지, packet burst가 panel raster와 같은 주기를 따르는지 검사한다.
- 상수 phase/delay뿐 아니라 residual CFO(시간에 따른 phase slope), sample-rate drift(시간에 따른 delay slope)를 추정한다.
- overlap band 내부 여러 주파수에서 잔여 group delay를 본다. 단일 phase+delay로 설명되지 않으면 receiver response, coupling 변화, 서로 다른 source 혼합을 점검한다.
- 0.5 s/band는 시작 후보이며 60 Hz가 실제 맞으면 약 30 frame이다. coherent segment length는 실측 phase stability로 결정한다. retune settling은 측정해서 discard한다.
- A 반복이 이미 변하면 긴 sweep을 진행하기 전에 시간을 줄이거나 burst/state별 구간을 나누어 비교한다.

### B3. 세 band 이상으로 합성 대역 확장
**150 MHz center span을 새로 시험하는 설계 예시:** B_use100 MHz/step50 MHz일 때 f_start+[0,50,100,150] MHz의4개 중심으로250 MHz union을 얻는다. f_start는 아직 정하지 않았다. 이는 과거 측정 설정의 추정이 아니다. 논문 iPhone6의105 MHz와 기존238 MHz를 독립적인 재탐색 후보로 두고 실제 성공 대역을 확인한다.

다음 수치는 시작 주파수 범위가 확인되기 전의 **예시**다. 사용자 보고의 실제 성공 sweep 범위를 우선한다.

| 장치 | 기존 f0 | 후보 중심 MHz | B_use/step/overlap | 합성 구간 MHz |
|---|---:|---|---|---|
| LG X2 | 344.8 | 294.8, 344.8, 394.8 | 100/50/50 MHz | 244.8–444.8 (200 MHz) |
| iPhone 6 | 238.0 | 188.0, 238.0, 288.0 | 100/50/50 MHz | 138.0–338.0 (200 MHz) |

- 중심이 움직인 폭은 100 MHz, union 폭은 200 MHz다.
- 순서: center→lower→center→upper→center. 다음 반복은 center→upper→center→lower→center로 순서를 바꾼다.
- 예시 5 captures × 0.5 s × 800 MB/s = **2.0 GB/장치/반복**(헤더·settle 제외). 두 순서, 두 장치는 8 GB 후보. 실제 data rate가 다르면 다시 산정한다.
- edge 밖의 신호 감쇠와 calibration 상태를 보고 overlap/filter order를 정한다. 원문의 W=8/50%를 무조건 최적값으로 고정하지 않는다.
- pairwise sequential 결과와 모든 overlap/anchor 제약을 함께 이용한 정렬 결과를 비교한다. 기준 band의 phase/time gauge는 고정한다. 합성 대역이 커졌다는 사실만으로 공간 해상도가 증가했다고 판정하지 않는다.

## C. MIPI와 column/row driver 혼합을 다루는 방법
각 IQ의 알려진 nominal 중심주파수 차이를 공통 RF/기저대역 좌표로 이동시킨 뒤 사용하는 관측 모델의 한 예:
\[
v_b(t)=e^{j(\phi_b+2\pi\Delta f_b t)}[h_b*s](a_b t-\tau_b)+n_b(t).
\]
여기서 Δf_b는 알려진 tuning 차이를 제거한 뒤의 residual CFO만 뜻한다. 의도한 50 MHz 중심 간격을 CFO fitting으로 흡수하지 않는다. 이는 설계를 위한 모델이며 현재 소스 정체가 확인됐다는 뜻이 아니다. 실제로는 여러 s가 동시에 존재한다.

1. **stitching 자체는 소스 분리기가 아니다.** 강한 세로선 간섭이 overlap 상관을 지배하면 그 성분을 기준으로 band를 맞출 수 있다. 결과 화면이 안정적이어도 원하는 DSI 누설이 맞았다고 할 수 없다.
2. 전화 다이얼 화면과 함께 단색·수직/수평 edge·비대칭 위치 표식·세로/가로 grating을 수집한다. 각 pattern 안에서 sweep을 완결한다. 서로 다른 pattern의 band들을 섞어 한 영상으로 만들지 않는다.
3. pattern을 이동하거나 바꿨을 때 같이 이동/변조되는 성분과 좌표에 고정된 선을 비교한다. 패널 inversion이나 driver도 내용에 반응할 수 있으므로 이 결과만으로 source를 확정하지 않는다.
4. 가능하면 별도 반복에서 probe 위치/방향을 바꾸고 같은 pattern을 재측정한다. 하나의 sweep 중간에 위치를 바꾸면 frequency stitching과 coupling 변화를 구별하기 어렵다.
5. raw fixed-gain, complex averaging, interference suppression 결과를 모두 보존한다. whitening/RPCA/subspace는 복소정렬의 학습·검증 구간 분리를 유지한 후 비교한다.
6. D-PHY differential clock/bit rate, DSI packet/burst rate, panel row/frame rate를 개별 항목으로 기록한다. RF fc를 bit/pixel rate로 치환하지 않는다. TMDS blanking template나 fb=10fp를 가져오지 않는다.
7. 단일 안테나로 받은 혼합장만으로 common-mode emission만을 식별했다고 말하지 않는다. source attribution에는 근접장 위치·방향·프로토콜 주기·pattern 반응의 결합 근거가 필요하다.

## D. 매 단계 저장할 수치와 화면
| 단계 | 필수 수치 | 화면/그림 |
|---|---|---|
| 원본 band | fc/Fs/BW actual, samples, duration, clipping, drops, gain | 공통 scale PSD, I/Q time trace, 원래 amplitude/phase raster |
| 시간축 | fh/fv 또는 burst period, fractional samples/period, timing drift | row·frame STFT, packet/burst envelope, 시간별 delay |
| 정렬 | complex coherence, delay ns, phase rad, CFO Hz, rate ppm, usable overlap | phase residual vs f/time, correlation peak 및 경쟁 peak |
| crossover | response ripple, finite-edge discard, gain ratio | 각 band와 합성 PSD, overlap 전후 amplitude/phase |
| 복원 | 같은 독립 frame 수, edge-width/contrast, reference pattern 비교 | P=1/4/8/16 등 frame progression, 단일band/비동기sum/정렬sum |
| 검증 | held-out error, anchor repeat, sweep-order difference | pattern 변경 대조, source별 의심 ROI 진단 |

- phase는 공통 기준을 표시하고 낮은 진폭 영역을 mask한다. HSV hue는 상대 IQ 위상이며 원래 화면 RGB가 아니다.
- 복소 coherence는 동일 waveform/overlap 구간으로 맞춘 뒤 계산한다. 추정에 쓴 peak 값 자체를 독립 성능으로 제시하지 않는다.
- 상관이 높은 fixed column clutter와 실제 글자/edge의 개선을 별도로 평가한다.
- 임의의 보편 임계값 대신 A↔A repeat와 mismatched frame/pattern 또는 적절한 surrogate 대조의 분포를 보고 판단한다.
- 원하는 성분과 noise가 분리되지 않았다면 “SNR 개선” 대신 측정한 coherence, residual, repeatability를 그대로 보고한다.

## E. 이번 준비에서 완료/미완료
완료: 155쪽 전체 독해, 원문 식 대조, MATLAB 상관 부호·crossover 항등식 검증, NI/UHD/MathWorks 공식 지원 확인, 기존 capture inventory, metadata template.

미완료: 새 수집, 실제 passband 측정, LG/iPhone6 실측 band stitching, 전체 MATLAB stitching pipeline 구현·성능 검증. 이 문서는 이를 수행할 때의 기준 기록이다.
