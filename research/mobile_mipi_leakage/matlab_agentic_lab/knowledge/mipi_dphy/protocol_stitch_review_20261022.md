# MIPI packet 기반 stitching: 독립 식별 가능성 검토

검토일: 2026-10-22 · 분류: 문헌 검토 및 유도 모델 · 실측/새 알고리즘 실행 없음.

## 결론

Known SoT와 DSI header/EoTp는 전송 이벤트 검출, 상대 시간 정렬, 반복 구간 선택의 유망한 기준이다. 실제 RF에서 보이는 것은 비트열 그 자체가 아니라 lane별 방사 경로와 수신 필터를 거친 복소 혼합이다. 따라서 알려진 packet을 이용하는 것은 타당한 연구 방향이지만, 검출 성공만으로 절대 RF 위상, lane 분리 또는 임의 RGB888 전체 복원이 성립하지는 않는다.

## 1. 논리 bit template와 RF template를 구분한다

검토용 모델:

\[
r_b(t)=e^{j(2\pi\delta f_b t+\phi_b)}
\sum_{\ell=0}^{L-1}(g_{b\ell}*x_\ell)((1+\epsilon_b)t-\tau_b)+c_b(t)+n_b(t).
\]

- x_l: lane l의 알려진/미지 직렬 전송에 대응하는 파형. 비트 값을 전압이나 방사 파형과 동일시하지 않는다.
- g_bl: 불균형으로 인한 mode conversion, 방사/전파 경로, 안테나, RF/IF 필터를 포함하는 유효 응답. RF 대역과 lane마다 다를 수 있다.
- delta f_b, phi_b: 수신 기준에 대한 잔여 주파수와 상수 위상, epsilon_b: 시간축 비율 오차, tau_b: 기록 정렬 오프셋.
- c_b: clock/다른 회로/간섭 성분. 단일 안테나 IQ의 상관만으로 CM 방사만 분리됐다고 주장하지 않는다.

이는 검증할 선형 근사 모델이며 모든 HS/LP 전환 및 비선형 방사에 정확하다는 주장이 아니다. 차동 불균형·skew의 EMI 영향은 TI SLLA104A pp.3,5–6; 장치마다 경로와 극성이 다른 여러 선로가 합쳐지는 실제 누설 관측은 O’Connell pp.119–120에 근거한다. 이 모델을 모바일 DSI에 적용하는 부분은 본 검토의 유도이다.

## 2. 무엇이 식별되고 무엇이 남는가

| 관측/가정 | 얻을 수 있는 것 | 남는 ambiguity 또는 실패 조건 |
|---|---|---|
| 같은 전송 이벤트의 알려진 pattern을 같은 대역에서 반복 관측 | 상대 event timing, 반복성, 안정한 유효 복소 template | absolute RF phase, 물리적 lane별 위상은 바로 식별되지 않음 |
| 단일 좁은 tone | 상대 복소 phasor | 지연 tau가 phase 2 pi f tau로 흡수됨; 지연과 phase를 분리하기 어려움 |
| 여러 주파수를 포함한 알려진 waveform, 안정한 channel | delay의 phase slope와 상수 phase 분리 개선 | channel의 미지 group delay와 기록 delay 사이 gauge가 남음 |
| 동일 SoT를 동시 송신하는 여러 lane | 합성 SoT response | 정렬되고 flat-channel인 경우 y=(sum h_l)s; h_l 각각은 분리 불가 |
| 4lane EoTp의 byte 집합 08/0F/0F/01(실제 lane 순서는 누적 byte offset에 따른 순환 이동) | SoT와 다른 lane excitation 후보 | 동일 0F 두 lane은 이 구간만으로 분리 불가(정렬·flat-channel 근사); 다른 pattern도 필요 |
| 중첩 RF 주파수에서 같은 반복 파형, 안정한 위치/장면/chain | 서로 다른 기록의 상대 phase/delay 정렬 | 순차 수집의 clock drift, packet schedule 변화, gain/phase 응답 변화 |
| 서로 겹치지 않는 RF 대역의 동일 header | 각 대역의 timing/event 후보 | 미지 g_bl의 상대 위상을 그대로 두면 coherent stitching 기준이 부족 |

SoT와 EoTp는 같은 층의 동일한 동작이 아니다. SoT는 PHY가 활성 lane마다 만드는 동기 sequence이고, EoTp는 DSI packet byte들이 lane distributor를 통해 배분되는 경우이다. EoTp가 모든 lane에 동일하게 복제된다고 모델링하지 않는다. DSI v1.3 §6 PDF32/인쇄20 lines772–777(병렬 SoT), §8.8.2 PDF63–64/인쇄51–52 lines1381–1388(EoTp와 lane 분배)의 packet 담당 원문 대조를 반영했다. §8.5.1.2 PDF58/인쇄46 lines1257–1264는 packet마다 독립적인 start/end sync code가 없으며 byte count로 경계를 찾는다고 설명한다.

## 3. 짧은 known header는 수신 필터 안에서 고립되지 않는다

조건부 수치 예시: R_lane=1 Gb/s, L=4이면 UI=1 ns이다. 4-byte header는 네 lane에 나뉘어 lane당 1byte, 약 8 ns 동안 전송된다. SoT 1byte도 8 ns이다. B_use=120 MHz라면 1/B_use=8.33 ns는 수신 필터 응답 시간 폭의 척도이다. 이것을 엄밀한 검출 한계나 추정 정밀도 하한으로 해석하지 않는다.

이 조건에서는 앞뒤 HS-zero, 다른 packet, 미지 payload의 응답이 header 관측과 겹칠 수 있다. 이상적인 0/1 header를 수신 sample rate로 줄인 template만으로는 채널·필터·인접 데이터 영향을 설명하기 어렵다. 더 긴 known sequence, 앞뒤 구간의 모델링, 실제 알려진 화면을 이용한 RF template 보정, 독립 반복의 복소 누적을 함께 검토한다. 작은 fraction의 sample delay를 추정할 수 있어도 대역 밖 임의 payload 정보가 생기는 것은 아니다.

## 4. quasi-periodicity의 층을 나누어 탐색한다

1. HS entry/SoT의 반복: host가 lane을 HS로 재진입시키는 일정에 따른다.
2. HS 내부 packet 반복: 여러 packet이 하나의 HS 전송에 묶일 수 있으므로 packet마다 새로운 SoT가 있다고 가정하지 않는다.
3. video mode의 행/프레임 timing packet: sync-pulse, sync-event, burst 선택에 따라 구조가 달라진다.
4. command mode의 DCS write/update/TE 일정: panel scan refresh와 host write 반복이 같다는 보장이 없다.
5. payload의 RGB byte 배치와 반복 화면: 같은 구조 반복과 같은 bit 값 반복은 다르다.
6. clock lane 및 calibration/다른 구동 회로: 강한 주기 peak가 DSI pixel payload를 뜻하지 않을 수 있다.

근거: DSI v1.3 §8.1–8.5, §8.8.11–12, §8.11–8.12; MIPI Alliance의 2021 DSI-2 발표 PDF pp.4,7–10. Null/blanking packet은 HS를 유지할 수 있어 HS envelope 길이를 곧바로 active pixel 수로 바꾸지 않는다.

## 5. 반복 event를 위상 anchor로 쓸 때의 alias

동일 event의 간격이 T이고 event마다 복소 계수 하나를 추정하면:

\[
\Delta\phi=2\pi\Delta f T\pmod{2\pi}.
\]

따라서 Δf 후보는 1/T 간격으로 구별되지 않는다. 예를 들어 T=1/60 s이면 60 Hz 간격 ambiguity이다. burst 내부 위상 진행, 서로 다른 시간 간격, coarse CFO 제한 또는 다른 독립 anchor가 있어야 이를 좁힐 수 있다. 반복 header의 높은 coherence만으로 CFO와 frame 정렬을 유일하게 정했다고 평가하지 않는다.

동일한 packet이 행마다 반복되면 상관 peak도 행 간격으로 반복된다. 프레임별 고유 위치 정보나 내용 비대칭이 없다면 행 정렬과 frame origin이 남는다. O’Connell Fig.5.3/pp.113–114도 frame peak와 작은 line peak를 구별한다. 그 문헌의 HDMI blanking template Eq.5.21은 MIPI packet/command mode에 그대로 옮기지 않는다.

## 6. 목표별 평가와 실패를 분리한다

- Event detection: 독립 데이터에서 알려진/바뀐 header 후보, false alarm, timing 불확실성을 기록한다.
- Relative alignment: 학습에 쓰지 않은 overlap 구간에서 complex coherence와 phase slope 잔차를 확인한다. 반복 clutter와 packet 쪽 성능을 따로 본다.
- Lane inference: SoT 하나로 lane 수나 lane별 h_l을 확정하지 않는다. 후보 lane 수·byte 배치·packet mode별 예측이 독립 payload 구간에서도 맞아야 한다.
- Image reconstruction: header 정렬 개선과 실제 문자/edge/색 정보 개선을 별도 지표로 기록한다. HSV hue는 선택한 기준에 대한 IQ phase이며 RGB 색 복원을 의미하지 않는다.
- Full decode: 대역, 채널, lane mixture, mode, packetization을 포함한 관측 모델과 독립 known-screen 검증이 추가로 필요하다. Header ECC와 payload CRC는 무제한 아날로그 정보 복원 수단이 아니다.

추천 순서는 프로토콜 후보 표 → 실제 동일 화면의 HS/event 분류 → band별 복소 template의 안정성 → 동일 capture의 가상 subband 대조 → 순차 수집의 overlap 정렬이다. 이번 메모에서는 이 실험을 실행하거나 성능 수치를 생성하지 않았다.

## 7. 원문 읽기 범위와 출처

- O’Connell, 2018, *Exploiting quasiperiodic electromagnetic radiation using software-defined radio*. 이번 검토에서 pp.113–114,119–120,134 추출 텍스트를 직접 재독했다. p.134는 잔여 stitching phase 오차 누적과 서로 다른 시점에 수집한 harmonic의 frequency 차이로 coherent demodulation을 얻지 못한 한계를 명시한다. [Cambridge 원문 페이지](https://www.repository.cam.ac.uk/handle/1810/290902), DOI 10.17863/CAM.38085.
- TI, SLLA104A, *Suggestions for High-Speed Differential Connections*, September 2004, pp.3,5–6. 이번 검토에서는 기존 로컬 검토·claim을 참조했다. [제조사 PDF](https://www.ti.com/lit/an/slla104a/slla104a.pdf).
- MIPI Alliance, 2021 DSI-2 cockpit 발표, PDF pp.4,7–10. 이번 검토에서는 기존 로컬 검토·claim을 참조했다. [MIPI PDF](https://www.mipi.org/hubfs/Automotive-Workshop/How-Use-of-DSI-2-and-Video-Compression-Is-Essential-for-Next-Gen-Digital-Cockpits.pdf).
- 사용자 로컬 DSI v1.3, 23 March 2015: §6(PDF31–33/인쇄19–21), §8.1–8.5(PDF53–58/인쇄41–46), §8.8.2(PDF64/인쇄52), §8.8.11–12(PDF67/인쇄55), §8.11–8.12(PDF87–93/인쇄75–81). 이번 검토는 기존 전체 독해 기록과 packet 담당의 재대조를 참조했다. Confidential/DRAFT 표시 및 공식 배포본 진위 미검증은 기존 sources.jsonl의 제한을 유지한다.

주의: O’Connell의 올바른 추출 경로는 knowledge/stitching/extracted/oconnell/page_NNN.txt이다. 같은 extracted 폴더 루트의 page_NNN.txt는 이전 DisplayPort 자료이므로 O’Connell 인용에 사용하지 않았다. 둘 다 ignored local cache이며 본 메모는 저작한 요약·유도만 포함한다.
