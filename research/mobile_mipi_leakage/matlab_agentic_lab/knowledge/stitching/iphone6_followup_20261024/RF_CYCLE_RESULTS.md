# iPhone 6 RF 주기 후보: 실행 결과와 독립 감사

2026-10-24. MATLAB RF audit 실행은 완료됐으며 시간은 **98.566 s**, 실패 band는 0개다. 이 문서는 저장된 피크·모델 JSON/CSV와 기존 화면 복원 결과를 다시 분석한 기록이다. 작성 에이전트는 새 MATLAB 실행이나 원시 IQ 변형을 하지 않았다.

## 1. 관측으로 말할 수 있는 것

1. **112.8025 kHz 간격의 RF 피크 계열이 11개 수신 대역 모두에서 관측된다.** 이후 raw 구간에서도 유지되며, 기존 AM 영상의 1100-sample row 반복과 맞는다. 화면/패킷 관련 준주기성을 추적할 가장 직접적인 현재 후보다. 이 일치만으로 MIPI packet, panel row driver 또는 다른 동기성 방사원 중 하나를 특정하지는 못한다.
2. **음의 RF 좌표 f_RF=fc−f_bb에서 공통 피크가 훨씬 많이 맞는다.** 인접 중심 간 201쌍, 양의 좌표에서는 8쌍이다. −IQ convention을 후속 검증의 우선 후보로 삼을 근거지만 하드웨어 spectrum polarity의 교정 측정을 대신하지 않는다.
3. **14.812010 MHz comb는 검출됐지만 f_byte로 식별되지 않았다.** 대부분 같은 피크를 2.115990 MHz 등의 부고조파 comb로 설명할 수 있다. 60.03 MHz byte-rate 가설 역시 식별되지 않았다.
4. 화면 내용이 보이는 기준 band는 기존 100 MHz AM 결과다. 160 MHz는 공통 RF 피크·화면 구조의 대조군, 580/640 MHz는 다른 RF 위치의 문장 구조 및 잔여 coherence 확인 대상으로 유용하다. 높은 tone power나 comb score만으로 band를 선택하지 않는다.

## 2. 데이터와 측정 해상도

- Fs=124.0828 MS/s, nominal RF bandwidth=120 MHz: 사용자 제공 값. 절대 LO/sample-clock 교정 정확도는 미제공.
- 각 파일 training은 처음 2^22 samples, 약 **33.802461 ms**. Heldout도 2^22 samples이며 파일의 약 65% 위치, 시작 시각 약 0.933–1.711 s다. 두 구간은 겹치지 않는다.
- Hann Welch window=2^17, 50% overlap. 선택된 피크는 전체 block Hann periodogram으로 위치를 보간했다. Long FFT bin=29.583645 Hz, Hann null-to-null mainlobe≈118.334579 Hz. 약 59.969 Hz frame sideband를 이 block으로 분리했다고 볼 수 없다.
- 11개 band 모두 **64-peak 상한에 도달**했다. 이후 결과는 선택된 강한 피크의 분석이며 스펙트럼의 모든 성분 또는 약한 정보성 성분을 포함하지 않는다.
- Training input의 I/Q rail-hit는 전 band에서 0이다. DC는 PSD에 남겼고 comb fit에서는 ±20 kHz를 제외했다. fc700의 mean-complex-power fraction은 약 52.94%로, DC 포함 총전력을 복원 품질로 비교하면 특히 부적절하다.
- 주파수 소수점은 계산 재현용이다. peak 보간·반복쌍 median의 소수점 자릿수가 절대 주파수 정확도를 의미하지 않는다.

원본 수치: [RF overview](../../../results/iphone6_followup_20261024/rf_cycle_candidates/overview.json). 후처리 근거: [RF_CYCLE_RESULTS.json](RF_CYCLE_RESULTS.json). 원본 overview SHA-256: 10fb5e607ff334888b1acda3bf5ae2659b2b47217cbae3e5638b0c8dc210fc4f.

## 3. 인접 대역의 공통 RF 피크

Training eligible peak를 RF 축으로 옮겨 |RF_B−RF_A|≤8 kHz인 대응을 집계했다. Training peak 최소 간격20 kHz라 이 범위의 대응은 중복되지 않는다. 아래 signed offset은 **더 높은 중심주파수 파일 B의 RF 추정 − A의 RF 추정**이다.

| 중심 쌍 MHz | −IQ 공통쌍 | +IQ 공통쌍 | −IQ training offset median Hz | 이후에도 양쪽 피크 존재 | 이후 offset median Hz |
|---|---:|---:|---:|---:|---:|
| 100–160 | 30 | 0 | 714.039 | 29 | 702.440 |
| 160–220 | 10 | 1 | 712.858 | 10 | 710.909 |
| 220–280 | 16 | 1 | 715.281 | 15 | 707.080 |
| 280–340 | 26 | 1 | 709.248 | 25 | 709.556 |
| 340–400 | 21 | 1 | 742.802 | 20 | 744.249 |
| 400–460 | 5 | 0 | 710.056 | 5 | 704.186 |
| 460–520 | 20 | 1 | 704.095 | 20 | 711.116 |
| 520–580 | 22 | 1 | 724.794 | 19 | 692.925 |
| 580–640 | 23 | 2 | 719.952 | 22 | 716.985 |
| 640–700 | 28 | 0 | 704.421 | 28 | 722.888 |

전체 −IQ 201쌍의 training median은 **+713.412 Hz**, MAD=8.070 Hz다. 이후 양쪽에 대응되는 193쌍의 median은 +710.079 Hz다. 60 MHz 이동에 대한 비율은 training 약 **11.890 ppm**이다. 피크들이 같은 row-sideband family를 공유하므로 201쌍은 독립적인 calibration 실험201회가 아니다. 양의 좌표에서도 우연히 맞는 일부 round-MHz 성분이 있어 극성 판정을 단일 tone으로 하면 위험하다.

이 결과는 기존 integer branch 약−12×59.969 Hz와 규모가 맞는다. 그러나 LO step 오차, sample-rate scale, tuning 상태, 해당 방사원의 drift 등을 분리하지 못한다. **이 수치만으로 Fs=124.0828 MS/s를 수정하지 않는다.**

### 100→160 MHz의 훈련 전용 이동량 후보

30쌍의 training RF_B−RF_A median=**+714.0389660000801 Hz**, MAD=2.546454019844532 Hz, 전체 범위650.965225–729.737596 Hz다. 각 template의 이미 고정된 주기가 다르므로 단순히 714 Hz×한 주기만 빼는 것보다 다음 식을 직접 사용했다.

- T_A=0.01667515455004975 s, T_B=0.016675154851964396 s.
- q_nominal=fc_B T_B−fc_A T_A=1000509.3213093283 cycles.
- q_empirical=median[−f_bb,A T_A+f_bb,B T_B]=**1000497.3813758891 cycles**.
- Δq=−11.939933439251035 cycles, Δq/T_A=−716.0313509187483 Hz. B의 placement를 낮추는 부호다.
- RF-difference의 Theil–Sen slope는 −0.0583 Hz/MHz이나 pairwise-slope MAD=0.3253 Hz/MHz로 추세 증거가 약하다. 단일 scalar median을 고정한 검증을 우선한다.

[훈련 scalar·공식·전30쌍 JSON](TRAINING_TRANSLATION_100_160.json) · [동일 CSV](TRAINING_TRANSLATION_100_160.csv). 이후 구간의 주파수나 coherence는 이 scalar 계산에 사용하지 않았다. Tone placement를 개선해도 payload 위상·지연·화면 복원이 검증되는 것은 아니다.

## 4. 데이터에서 먼저 드러난 112.8025 kHz 간격

Training에서 comb-eligible인 모든 peak 쌍의 간격20 kHz–1 MHz를 계산하고 **250 Hz histogram bins**로 집계했다. 특정 row 주파수를 먼저 강제하지 않았다. 총1671쌍 중 가장 높은 bin은112.75 kHz였고, 그 안의368쌍 median은 **112802.507477 Hz**다. 이 368쌍 중 양쪽 peak가 이후에도 잡힌337쌍의 간격 median은 **112802.609089 Hz**다.

그 역수는 약 **8.865051 µs**, 기존1100/Fs=8.865048 µs와 맞는다. 주파수의 sub-Hz 차이는 absolute calibration 또는 독립 통계 오차 추정이 아니다.

| fc MHz | 해당 training 간격쌍 | 간격 median Hz | 이후 대응쌍 | 이후 median Hz |
|---:|---:|---:|---:|---:|
| 100 | 33 | 112802.037 | 26 | 112803.051 |
| 160 | 34 | 112802.543 | 34 | 112802.925 |
| 220 | 30 | 112802.468 | 22 | 112803.003 |
| 280 | 30 | 112802.647 | 27 | 112802.508 |
| 340 | 33 | 112802.666 | 32 | 112802.556 |
| 400 | 35 | 112802.935 | 32 | 112803.041 |
| 460 | 23 | 112802.344 | 23 | 112802.482 |
| 520 | 33 | 112802.423 | 31 | 112802.521 |
| 580 | 41 | 112802.495 | 38 | 112802.535 |
| 640 | 37 | 112802.549 | 36 | 112802.339 |
| 700 | 39 | 112802.369 | 36 | 112802.542 |

같은 탐색에서 약225605.024,338407.509,451210.043,564012.667,676815.325 Hz의 간격도 반복돼 2–6배 계열을 이룬다. 두 피크의 차이는 amplitude/phase modulation에 의한 sideband, 반복 burst의 Fourier comb, 혹은 별도 tone의 조합일 수 있다. 현재 PSD만으로 AM과 PM을 구분하지 않는다.

### 약56.4 kHz 후보는 더 약하다

56.5 kHz bin에15쌍이 있고 실제 training median=56410.044 Hz, 이후 median=56408.111 Hz다. 이는100/160/220/280 MHz에서만 관측됐고 상당수가 같은 약155.8 MHz 또는259.8 MHz RF family를 서로 다른 중심에서 다시 본 것이다. 11개 band에 걸친112.8025 kHz와 같은 수준의 증거가 아니다. 2-row 주기 등의 후보로 남기되 lane, DDR 또는 특정 inversion 회로의 증거로 지정하지 않는다.

### 직접 확인할 수 있는 RF 계열 예시

아래는 **−IQ training coordinate**이며 receiver offset이 교정되지 않은 숫자다.

| 파일 fc MHz | 피크 계열 RF 구간 MHz | 연속 피크 수 | 이후 존재 | 용도 |
|---:|---|---:|---:|---|
|100|103.458516–104.248133|8|8|100/160 overlap 내부 row-period family|
|160|103.572032–104.248847|7|7|위 계열을 별도 tuning에서 재관측; 약+714 Hz offset|
|100|118.383168–119.059986|7|7|두 번째 overlap 계열|
|100|148.006886–148.909306|9|7|넓은 RF 간격에서 같은 row modulation 확인|
|160|148.007595–148.797212|8|8|위 계열 별도 tuning 대조|
|580|593.383150–594.059965|7|7|580/640 overlap의 row-period family|
|640|593.383871–594.173488|8|8|위 계열 별도 tuning 대조|
|640|637.932233–638.609047|7|7|고주파 band의 추가 계열|

계열 안의 이웃 간격은 약112.8025 kHz다. 이것은 복원용 동기 후보를 정하는 근거이며 해당 대역에 유용한 글자 정보가 있다는 직접 검증과는 구별한다. 전체 피크·IDs는 후처리 JSON에 있다.

## 5. 수 MHz comb 순위와 alias 감사

−IQ에서 cross-center 재현 group은201개다. 모델 탐색에는 source-center 수와 local excess 순위로160개가 사용됐다. Train-only로 fit하고 같은 tooth index·spacing·offset을 이후 구간에 고정 적용했다. 보존된12개는 다음과 같다.

| 순위 | 모델 | 간격 MHz | offset MHz | tooth 수 | training RMS Hz | 이후 RMS Hz |
|---:|---|---:|---:|---:|---:|---:|
| 1 | 자유 offset | 14.812010276 | 1.354088 | 13 | 172.5 | 171.7 |
| 2 | 자유 offset | 2.115990083 | 1.357364 | 14 | 419.3 | 419.7 |
| 3 | 자유 offset | 7.422415225 | 7.373368 | 12 | 5848.6 | 5853.4 |
| 4 | 자유 offset | 22.274378255 | 7.237461 | 10 | 1211.5 | 1216.7 |
| 5 | 0 offset | 7.421933351 | 0.000000 | 10 | 6574.3 | 6583.3 |
| 6 | 자유 offset | 44.548861293 | 29.624087 | 9 | 176.6 | 174.0 |
| 7 | 자유 offset | 29.736850413 | 29.060024 | 9 | 181.6 | 178.5 |
| 8 | 자유 offset | 11.137215323 | 7.349656 | 9 | 176.6 | 174.0 |
| 9 | 자유 offset | 8.909772259 | 2.894770 | 9 | 176.6 | 174.0 |
| 10 | 자유 offset | 25.976626147 | 0.002153 | 9 | 6851.2 | 6860.6 |
| 11 | 0 offset | 17.317833324 | 0.000000 | 9 | 6908.2 | 6917.1 |
| 12 | 자유 offset | 17.317522613 | 0.004228 | 9 | 7148.7 | 7161.4 |

**1위의 정확한 의미:** RF≈1.354088359 MHz+n×14.812010276 MHz이며 n=33–47 중13개 tooth가 해당한다. 피크는 약490.150410,504.962238,534.586659,549.398488,564.210343,593.834720,608.646572,623.458432,638.270282,653.082847,667.894699,682.706506,697.518356 MHz다. Offset이 있는 comb이고 이13개가 전부 그 간격의 인접 고조파라는 뜻은 아니다. Training RMS172.471 Hz, 이후171.748 Hz. 조건부 spacing SE22.368 Hz는 고정된 inlier/정수 배정 아래의 수치이며 receiver calibration·탐색 선택 불확도를 포함하지 않는다.

**중복 설명:**

- 2위2.115990083 MHz는1위13개 지지점을 전부 포함하고155.825307 MHz 한 점을 더 쓴다. 두 spacing 비는7.0000377이다. 한 finite peak set을 약1/7 spacing으로 다시 설명한 것이므로 별도의 clock 두 개 검출로 세지 않는다.
- 6위44.548861293,8위11.137215323,9위8.909772259 MHz는 **같은9개 지지점**을 각각1,1/4,1/5 spacing으로 설명한다. 동일 RMS가 나오는 이유다.
- 나머지7.422/17.317/25.976 MHz 등의 일부 후보는 RMS5.8–7.2 kHz로12 kHz tolerance에 비해 느슨하다. 높은 tooth 수와 순위만으로 물리적 fundamental을 선언하지 않는다.
- 양의 RF 축은 공통 group8개만으로 약5 MHz/2.5 MHz의 동일8점 모델, 약10 MHz/3.333 MHz의 동일6점 모델,40 MHz/20 MHz의 동일5점 모델이 반복된다. 약200,240,320,375,480,560,595,630 MHz에 가까운 지지점이며 원인 미상이다.

순위 score는 검출된 tooth 수·반복 group 수·잔차로 만든 탐색용 지표다. Screen fidelity, payload SNR, 전송 bitrate 또는 source posterior가 아니다.

### f_byte, f_DDR, lane 수의 현재 결론

60.03 MHz는750×1334×60 Hz,RGB888,3 lanes,연속 전체 payload 전송 가정에서 얻은 가설 seed다. 20.01/240.12 MHz도 함께 seed로 넣었으나 양쪽 극성의 **저장된 상위12개에는 남지 않았다**. 탈락·순위밖 후보 전체가 저장되지 않아 이를 가설 기각으로 해석할 수도 없다. 결론은 **실측 f_byte 미식별**이다. 따라서 f_b=8 f_byte와 f_DDR=4 f_byte 관계에 넣을 확정 실측값도 아직 없다.

14.812010 MHz를 단순 f_byte로 대입하면3 lanes의 합계 raw bit-rate는 약355.488 Mbps다. 750×1334의 RGB888 전체 화면을60 Hz로 보내는 active payload만 약1.441 Gbps이므로, 이러한 전송 가정과는 맞지 않는다. 이것이 압축·partial update·command mode·다른 timing 가능성을 배제하는 것은 아니다. **관측된 comb 간격과 byte clock을 같은 것으로 정의할 근거가 없다는 점**을 보여준다.

실물 lane count는 여전히 미측정이며 공개 schematic의N61 3-data-lane 후보와 수집 회로의 일치 확인이 필요하다. [MIPI_CYCLE_HYPOTHESES.md](MIPI_CYCLE_HYPOTHESES.md)의 근거·조건을 유지한다.

## 6. 다음 대역 선택: 화면 구조와 검증을 함께 사용

기존11-band AM16 gallery를 다시 직접 확인했다.100/160/340/580/640 MHz 등에서 반복 문장 형태가 보이며 세로 간섭도 함께 있다. 개별 display scaling이 달라 밝기만으로 비교하지 않는다.

| 목적 | 우선 대상 | 현재 근거 및 제한 |
|---|---|---|
|화면 복원의 기준 유지|fc100 MHz|문장 형태와 가장 잘 맞는 기존 AM timing; AM64 기준. RF phase가 안정하다는 뜻은 아님.|
|첫 RF 연결 실험|fc100+160 MHz, 특히103–109 MHz overlap|공통30쌍,103.46–104.25 MHz의 row family.106 MHz 중심6 MHz 창에서 training coherence0.294/이후0.293이나 tone mask 후0.045로 감소. 정보성 광대역 정렬은 미검증.|
|다른 RF 위치의 화면 구조|fc580+640 MHz|AM16에서 글자 형태가 보이고 공통23쌍.593.4–594.2 MHz 및638 MHz row families.이전 tone masking 뒤 일부 coherence가 남았으므로 정보성 성분 확인 가치가 있음.|
|중간 band 대조|fc340 MHz|글자 형태가 보이지만 band별 시간·위상 모델의 잔차를 함께 확인해야 함.|
|clutter 대조|fc520+580 MHz의 +IQ 고상관 사례|기존0.902 coherence가 tone masking 후0.000865로 떨어짐. 높은 RF score가 좋은 화면 band를 뜻하지 않는 대조군.|

화면 결합 결과의 training-anchor 구조 투영도는580/640 MHz가 새 fusion 구간에서 약0.083/0.092,160 MHz0.087,340 MHz0.063,520 MHz0.0067이었다. 이 값은 같은 정적 화면의 지정 ROI와 training anchor에 대한 선형 feature proxy이며 원본 pixel fidelity가 아니다.100 MHz 자체의 새 구간 투영도도0.134로 낮아 fixed timing/내용·clutter 혼합의 한계가 남는다.

**판정 기준:** 동기 tone을 고정 제거했을 때도 heldout complex coherence와 문장 구조가 유지되는지 확인하고, 새 screen pattern에서도 추정한 주기·대역이 재현되는지 본다. Row comb는 tracking에 쓸 수 있지만 같은 성분을 검증용 payload로 재사용하면 circular evidence가 된다.

관련 기록: [기존11-band/AM/stitch 보고서](../../../results/iphone6_stitch_20261023/REPORT.md), [image fusion overview](../../../results/iphone6_followup_20261024/image_fusion/overview.json), [narrow overlap 수치](../../../results/iphone6_followup_20261024/narrow_overlap_100_160_global_phase/window_metrics.csv). Global-phase convention별 residual phase 값은 달라지므로 서로 섞지 않았다.

## 7. 재현성과 남은 제한

후처리는 저장된 training_peaks 중 use_for_comb만 사용하여 signed RF 대응과 within-band pair differences를 계산했다. Heldout는 training에서 이미 선택한 피크의 존재·간격 유지 확인에만 사용했다. Half-line·comb alias 감사는 결과를 본 뒤의 탐색 분석이며 독립 사전등록 가설 검정이 아니다.

같은 tone이 여러 차분·histogram bin·receiver pair에 반복 참여한다. 따라서 count를 독립 표본수로 사용한 작은 p-value/표준오차 주장은 하지 않는다. 이 실험은 protocol bit decode, known packet/ECC/CRC 일치, MIPI 공통모드 source 분리 또는 RGB888 pixel decode까지 수행하지 않았다.
