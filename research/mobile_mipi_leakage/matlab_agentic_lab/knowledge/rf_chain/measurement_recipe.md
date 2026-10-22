# 스마트폰 RF 수신 실험 설계와 독립 검토

2026-10-22 / SDR·RF chain 역할. **이 문서는 실행 전 실험 설계이며 새 측정 결과가 아니다.**
관측 상태는 기존 `experiment_log.jsonl`, 문헌 근거는 `sources.jsonl` 및 `claims.jsonl`에 기록한다.

## 1. 먼저 확정할 하드웨어 경로

현재 연결된 SDR 모델·daughterboard는 미확정이다. 다운로드한 USRP2940 문서는 연결 장비의 증거가 아니다.
이미 실행된 TempestSDR GUI는 오프라인 재생 준비 상태이며 새 RF 수집 성공을 뜻하지 않는다.

공식 R2026b 문서의 UHD는 **4.9.0.0**이다. 로컬 USRP 스킬의 UHD 4.6 및 Windows MTU 1498 예시를 그대로 적용하지 않는다.
실제 드라이버/FPGA/운영체제 조합을 확인하고 해당 버전 문서를 따른다.
X300/X310도 daughterboard에 따라 API가 다르다:

| 실장 daughterboard | R2026b 수신 경로 |
|---|---|
| UBX160, OBX160, TwinRX | 지원 조건 확인 후 `basebandReceiver` 또는 Live Data I/O |
| UBX40, WBX, SBX, CBX 등 | `comm.SDRuReceiver` Live Data I/O; `basebandReceiver` 지원으로 가정하지 않음 |

NI294x/295x는 실제 구성과 UHD 전환 상태를 확인해야 한다. 전환은 기존 LabVIEW 측정 환경에 영향을 줄 수 있으므로 장비 식별 및 기존 상태 기록 후 진행한다.
[MathWorks 지원 표](https://www.mathworks.com/help/wireless-testbench/gs/supported-sdr-devices.html).

## 2. `fc >> fm`의 실제 문제

RF 중심주파수 `fc`와 복소 IQ 샘플레이트 `Fs`는 다른 값이다. RF를 LO로 내린 뒤 필요한 양측 sideband 대역을 복소 IQ로 저장한다.
`z(t)=A[1+m a(t)]exp(j[2πΔf t+φ0+βp(t)])+c(t)+n(t)`에서 작은 `m,β`이면 기준 위상 회전 후 실수/허수 방향이 각각 AM/PM에 일차 민감도를 갖는다.
이 식은 검증할 좁은 대역 모델이며 모든 DSI 방사의 보편적 모델로 확정하지 않는다.

단일 정현파의 AM 변조도 `m=0.01`일 때 각 sideband 전력은 carrier 대비 `m²/4`, 즉 약 **−46.02 dBc**다. 작은 PM의 `β=0.01 rad`도 같은 일차 근사다.
이는 계산 예이며 측정한 변조도가 아니다. 강한 carrier·외부 간섭이 ADC/LNA를 포화시키거나 LO 위상잡음이 가까운 sideband를 덮으면 평균 횟수를 늘리는 것으로 해결되지 않는다.

수신 체인: 프로브/안테나 → 상황에 맞는 preselector/감쇠기/LNA → IQ 수신기 → 원본 파일+메타데이터.
간섭이 강하면 LNA 앞 필터/감쇠가 선형성에 유리할 수 있고, 약한 신호만 존재하면 앞단 손실이 NF에 불리하다. 실제 gain sweep과 간섭 전력으로 결정한다.
AGC는 고정하고 receiver gain·필터·케이블·기하구조를 실험 중 유지한다. dBFS/counts를 입력 dBm이나 V/m로 표현하려면 별도 교정이 필요하다.

## 3. 데이터율과 길이: 현재 파일 기준 계산

외부 파일명 메타데이터를 사용했으며 수신기의 실제 설정 readback은 없다. `20 MHz/60 MHz`가 3 dB 대역폭인지 ENBW인지도 미확정이다.

| 기준 파일 | 복소 Fs (MS/s) | 이름에 기록된 BW (MHz) | int16 I,Q 파일 쓰기 (MB/s) | payload (Gb/s) |
|---|---:|---:|---:|---:|
| LG X2 /344.8 MHz | 136.565510 | 60 | 546.26204 | 4.37009632 |
| iPhone 6s /311 MHz | 55.054870 | 20 | 220.21948 | 1.76175584 |
| Galaxy S4 LTE /111.9 MHz | 110.891050 | 20 | 443.56420 | 3.54851360 |
| Galaxy S4 LTE /171.5 MHz (다른 캡처) | 55.816790 | 20 | 223.26716 | 1.78613728 |

한 채널 sc16의 순수 payload는 `32 Fs bit/s`. 1 Gb/s를 전부 payload로 써도 31.25 MS/s가 상한이며 실제 transport overhead만큼 더 낮다.
따라서 현재 1 GbE 경로에서 위 rate의 **연속 host 전송**은 불가능하다. 지원 하드웨어의 온보드 버퍼에 짧게 수집 후 천천히 전송하는 경우는 별개다.
파일의 Fs만으로 과거 장비/링크를 추정하지 않는다. 요청 Fs, 수신 readback Fs, 저장 Fs, 후처리 resampling 이력을 분리한다.

1초 스크리닝 후 유효 후보를 4초 이상 확보하면 60 Hz 가정으로 최대 약240 프레임을 담는다. 실제 안정 구간·blanking·누락 여부로 사용 프레임 수를 다시 센다.
원본 저장량과 장비 버퍼를 먼저 계산하고, 한 파일의 여러 조각을 위상 연속인 것처럼 이어 붙이지 않는다.
[온보드/host 캡처](https://www.mathworks.com/help/wireless-testbench/ug/evaluate-host-capture-performance.html).

## 4. 단계별 측정 recipe

1. **식별:** receiver/daughterboard/serial/driver/FPGA, 안테나 및 LNA 모델, reference clock, 링크속도, 수신 가능대역, 저장속도를 기록한다. 사진에는 프로브 위치·방향·거리 눈금을 포함한다.
2. **연속성:** 지원 Fs에서 짧은 고정 길이 untriggered IQ를 수집한다. 요청값과 실제 readback을 모두 저장한다. LO 변경 후 lock/settling 상태와 버린 초기 샘플 수를 기록한다.
3. **선형성:** 같은 고정 화면에서 gain을 한 단계씩 바꿔 clipping, DC, histogram, 강한 spur/sideband 비율을 비교한다. 특정 신호를 최대로 만드는 gain이 아니라 선형 구간을 선택한다. 조건별 raw를 보존한다.
4. **주파수 후보:** 원래 세 기기의 RF 대역을 우선 재방문하고, 동일 화면·동일 gain의 짧은 캡처로 PSD와 frame/line cyclic score를 비교한다. 최대 PSD peak를 화면 carrier로 자동 선택하지 않는다.
5. **주 측정:** 한 조건을 안정화한 뒤 연속 IQ를 저장한다. 최소 3회 별도 acquisition으로 반복 재현성을 확인한다. 순서 효과를 줄이기 위해 화면 조건 순서는 교차한다. energy-trigger는 약한 화면 대신 강한 clutter만 고르는 선택 편향을 평가한 뒤 도입한다.
6. **메타데이터:** raw SHA-256, 실제 byte 수, complex sample 수, dtype/endian/IQ 순서, overflow/drop 상태, request wallclock, 가능하면 hardware first-sample timestamp를 저장한다.
7. **MATLAB 분석:** raw QC → PSD → multiscale TF → fh/fv 후보 → fractional timing → phase alignment → incoherent/coherent averaging. 같은 원본 frame subset·crop·색상범위를 사용한다. 필터/whitening/RPCA는 별도 분기다.
8. **독립 평가:** 보정에 쓴 화면과 다른 held-out 패턴에서 경계/문자 복원, 위치, false structure를 평가한다. `N=1,4,16,64,200` 중 실제 확보된 프레임만 사용한다. 맞춰진 clutter도 함께 평균될 수 있다.

`capture`의 `timestamp`는 host의 **수집 요청 시간**이지 정확한 첫 RF 샘플 시각이 아니다. `droppedSamples`는 boolean이므로 이를 누락 샘플의 개수로 기록하지 않는다.
drop 발생 시 원본을 진단용으로 보존하되 연속 phase/coherent 분석에서 해당 구간을 제외하거나 hardware timestamp로 gap을 명시한다.
[MathWorks capture](https://www.mathworks.com/help/wireless-testbench/ref/basebandreceiver.capture.html),
[UHD overflow 처리](https://files.ettus.com/manual/page_general.html).

## 5. 필수 대조군과 각자 답하는 질문

| 대조군/조작 | 일정하게 유지할 것 | 해석 범위 |
|---|---|---|
| 수신 입력 50Ω 종단 (LNA 구조에 맞춤) | 수신 설정 | 수신기 내부 spur/LO/DC 기준; 안테나 환경잡음과 다름 |
| 안테나 그대로, DUT 전원 off / 멀리 이동 | 위치/수신 설정 | DUT 연관성; off에도 charger 등 다른 소스가 남을 수 있음 |
| display off, CPU 실행상태 기록 | 전원/수신 설정 | display 연관성; 시스템 상태가 함께 변하므로 단독 확증 불가 |
| all-black/all-white/회색/수직·수평 줄/이동 bar | 밝기·refresh·gain | 영상 내용과 sideband/위상 관계; OLED/LCD 소비전력 차이 별도 기록 |
| 위치 scan: display flex/패널 가장자리/PMIC/다른 영역 | 정확한 거리·방향 | 근접장 공간 연관성; 부품 단정 아님 |
| brightness만 변경 | 동일 패턴 | 밝기/PWM/전원 변조와 영상 성분 분리 |
| 배터리/충전 케이블 비교 | 화면과 수신 설정 | 케이블/접지 경로 기여; 화면 출력·전력상태 동시 기록 |
| LO 위치만 조금 변경, 같은 RF 구간 보존 | 겹치는 RF passband | 수신기 DC/spur와 실제 RF source 구분 |

## 6. 'common mode만 수집'을 입증하는 방법

한 개 안테나의 스칼라 IQ에는 여러 전류경로의 장이 섞인다. 낮은 rank나 세로선만으로 DSI common mode를 판정할 수 없다.
신호 쌍의 동시 교정 측정이 가능하면 동일 기준에 대한 `Vcm=(Vp+Vn)/2`, `Vdm=Vp−Vn`을 계산한다. 이것은 도체 전압 mode 정의이며 방사장 기여도와 동일하지 않다.
작은 CM을 보려면 두 경로의 gain/delay mismatch 및 loading이 DM→CM 변환으로 만들어내는 오차를 교정해야 한다. 접촉으로 화면 동작이나 방사 자체가 변하지 않는지도 비교한다.

기하구조상 가능한 케이블에는 두 선을 함께 감싸는 RF current probe로 순전류를 측정할 수 있다. return/shield까지 포함했는지와 프로브의 RF 전달함수를 반드시 기록한다.
이 측정, 근접장 위치 scan, 안테나 IQ 간의 동일 주파수·패턴·위상 관계를 함께 비교한다. 공통모드 경로를 바꾸는 ferrite/shield 실험도 display timing과 신호무결성 변화가 동반되지 않았는지 확인해야 한다.
[Murata CM 관측 §5-2-3(5)](https://www.murata.com/products/emc/emifil/library/knowhow/basic/chapter05-p1),
[Tektronix differential 측정 오차](https://www.tek.com/en/documents/whitepaper/abcs-probes-primer).

## 7. coherent phase를 해석할 때

다중 수신기라면 공통 reference, 시각 동기, timed start, 실제 채널 phase 교정이 각각 필요하다. 공통 10 MHz/PPS만으로 아날로그 LO phase가 자동으로 동일해지지 않는다.
스마트폰 자체 clock은 수신기 reference에 lock되지 않으므로 한 수신기의 연속 캡처에서도 timing drift/CFO 보정은 남는다. 별도 캡처 사이 절대 hue는 기본적으로 비교 불가능하며 공통 기준을 명시해야 한다.
[Ettus 동기화 및 LO phase 교정](https://files.ettus.com/manual/page_sync.html).

세로 stripe 위상은 amplitude-confidence mask를 적용한 뒤 **고정 기준에 대한 복소 cross-phase**로 비교한다. 어두운 stripe의 임의 hue를 driver 위상으로 해석하지 않는다.
화면 패턴 변경에 따른 반복 구조를 입증하기 전에는 column driver, DSI clock, receiver spur를 경쟁 가설로 유지한다.

## 8. TempestSDR 재생의 함정

- 기존 RIS는 big-endian int16 I,Q이고 RawFile은 native-endian cast다. Windows용 새 little-endian export는 필요하다.
- RawFile `ENABLE_LOOP=1`은 EOF에서 파일을 반복한다. 재생 횟수는 독립 프레임 수가 아니다.
- 원본 소스는 부분 EOF 블록에서도 고정 길이를 callback하므로 tail의 stale/uninitialized 값 위험이 있다. 현재 소스의 블록은 **524,288 scalar = 262,144 complex**다. export를 이 배수로 제한하고 반복 경계는 분석에서 제외한다. 실행 JAR/DLL 버전이 소스와 같은지는 별도 확인한다.
- 블록 배수 export도 EOF에서 읽은 byte가 0인 iteration에 직전 버퍼가 다시 callback될 수 있다. 블록 정렬은 첫 패스의 tail 문제를 완화할 뿐 loop를 안전하게 만들지 않는다.
- 기본 export `2^20 complex`는 LG 7.68ms, iPhone6s 19.05ms, Galaxy111.9MHz 9.46ms다. 전체 화면 비교에는 여러 프레임을 포함하는 길이가 필요하다.
- 원본 내부 drop 이력은 headerless 파일에서 복구되지 않는다. RawFile callback의 drop=0은 재생 플러그인 동작이며 과거 RF 수집의 무누락 증거가 아니다.

근거: `TSDRPlugin_RawFile/src/TSDRPlugin_RawFile.c`의 `ENABLE_LOOP`, `SAMPLES_TO_READ_AT_ONCE`, EOF loop, `TYPE_SHORT`, `cb(...)`; `TempestSDR/src/TSDRLibrary.c`의 `am_demod`.
