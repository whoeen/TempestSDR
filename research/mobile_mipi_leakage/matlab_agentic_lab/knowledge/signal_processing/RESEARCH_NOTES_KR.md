# RF 신호처리 연구 노트

기록일: 2026-10-22 (Asia/Seoul). 담당: RF 신호처리 역할. MATLAB 측정 데이터
실행 결과는 아직 없으며, 아래는 구현과 검증할 가설이다. 실행 수치는 각
timestamp 폴더의 JSONL에 추가하고, 기존 결과를 덮어쓰지 않는다.

## 주파수의 의미를 먼저 구분한다

수신 RF 중심 `fc`, D-PHY lane bit rate `Rb`, DDR clock, pixel/raster clock,
line rate `fh`, frame rate `fv`, 영상 변조의 최고 주파수는 서로 다르다.
`fc >> fm`이면 수신기가 제공하는 복소 기저대역 IQ에서 관심 중심을 DDC하고,
필요한 양측 측파대를 보존한 뒤 저역통과와 decimation을 한다. RF 중심이
높다는 이유만으로 저장 IQ도 Gs/s여야 하는 것은 아니다. 반대로 `fh`나 `fv`가
낮다는 이유로 대역을 수 kHz로 줄이면 수평 영상 정보를 잃을 수 있다.

`z(t) = A[1 + m a(t)] exp(j[2πΔf t + β p(t)]) + c(t) + n(t)`는 분석용 복소
모형이다. 작은 변조에서 carrier를 기준으로 회전하면 동상 성분 변화가 AM,
직교 성분 변화가 작은 PM에 대응한다. 이는 단일 지배 carrier와 안정한 위상
기준이 있을 때의 근사다. 여러 방사원·multipath·common-mode conversion이
섞인 `arg(z)` 전체를 곧바로 원하는 PM이라고 부를 수 없다.

정현파 AM의 깊이 `m=0.01`이면 각 1차 측파대의 carrier 대비 전력은
`m²/4 = 2.5e-5`, 즉 약 −46.02 dBc이다. 작은 정현파 PM에서도 β=0.01 rad일 때
같은 1차 근사가 성립한다. 이것은 RF 중심 주파수와 별개의 작은 변조도 문제다.
AM 검파 전에 복소 신호를 보존해야 PM과 AM/PM 혼합을 나중에 비교할 수 있다.

## 저랭크 가정의 경계

공간 래스터에서 모든 행에 같은 세로 무늬가 나타나면 `X = 1 cᵀ`이고 rank는
1이다. 따라서 세로선이 많다고 high rank라고 할 수 없다. frame를 열로 쌓은
행렬에서는 정지 화면과 정지 간섭이 모두 low rank일 수 있다. RPCA의
low-rank + sparse 가정은 '화면 + 모든 종류의 간섭'과 같은 뜻이 아니다.

검증 순서는 먼저 행렬의 축을 명시하고, 입력 화면 변경/blank screen/수신 위치
변경에 따라 어느 성분이 같이 바뀌는지 비교하는 것이다. matched subspace나
clutter whitening은 독립적인 reference·training으로 만들고 held-out capture의
화면 내용 보존을 평가한다. 같은 자료로 최적화한 coherence만 올리면 강한
간섭에 정렬되는 결과도 성공처럼 보인다.

## 현재 구현한 단계

1. headerless big-endian int16 I/Q를 blockwise read. 원본 byte offset·개수·SHA 기록.
2. clipping·DC·MAD·I/Q covariance·impropriety 진단. 보정 전에 원본 수치를 남김.
3. centered Welch PSD. ADC-count²/Hz로 표기하며 dBm으로 환산하지 않음.
4. 0.25 row / 1 row / 16 row STFT. 창 시간·hop·FFT 길이·ENBW를 기록.
5. envelope autocorrelation와 제한된 cyclic-frequency probe. 후보를 display
   clock으로 자동 확정하지 않음.
6. 0.4 s streaming envelope로 frame 후보 조사. rectangular integration의 alias
   한계 기록. 최종 판단은 raster drift·독립 측정과 함께 수행.
7. AR order 4/8/16/32의 과거 구간 학습·다음 구간 prediction error 비교.
8. prior timing으로 nearest/cubic fractional raster를 동일 crop/표시 scale에서 비교.
9. P=1/4/8의 AM·무보정 complex average·global phase·row phase 보정 비교.
   phase HSV와 column phase CSV를 동시에 남김.
10. 약한 AM/PM과 큰 clutter가 있는 known-truth synthetic에서 저랭크/복소
    DDC/coherent averaging 동작을 검증. 이 수치를 스마트폰 성능으로 보고하지 않음.

## 세로선과 곡선 gradation을 구분할 실험

확대 또는 원형 경계에서 보이는 줄무늬는 원인 후보가 여러 개다. RF 대역제한의
impulse response/ringing, carrier residual과 래스터 시간축의 beat, fractional
timing 오차, panel/DSI 주기성, 표시용 HSV 위상 wrapping을 분리해야 한다.
특히 phase는 진폭이 거의 0인 곳에서 불안정하므로 그 구역의 hue만 해석하면
잘못된 규칙성을 볼 수 있다. phase wrap을 펼친 결과도 동일하게 불안정하다.

각 열의 복소 위상과 line-to-line coherence, 원본 IQ에서의 signed spectral
sidebands, 출력 창/보간법 변경, frame 수 증가, blank/reference pattern을 함께
비교한다. 이미지 하나의 세로선만으로 LCD column driver, row driver, D-PHY
common mode 중 하나를 특정하지 않는다. Galaxy A7 (2018)은 실제 측정 자료가
없으므로 device-specific clock/lane 정보를 임의 생성하지 않는다.

## 출처 검토에서 발견한 충돌

다운로드된 `matlab-analyze-time-frequency-content/SKILL.md`는 WVD가 MATLAB
toolbox에 없다고 적었다. 공식 [MathWorks wvd 문서](https://www.mathworks.com/help/signal/ref/wvd.html)는
`wvd`, `smoothedPseudo`, 복소 입력을 제공하고 R2018b 도입을 명시하므로,
그 스킬의 해당 설명은 사용하지 않는다. WVD의 cross-term이 실제 RF 성분처럼
보일 수 있다는 해석 문제는 그대로 남는다.

[MathWorks pwelch](https://www.mathworks.com/help/signal/ref/pwelch.html)의 centered
복소 스펙트럼과 PSD 단위 정의를 확인했다. toolbox 없는 경로도 동일한
`|FFT(w·x)|²/(Fs Σw²)` 정규화를 사용하며, 구현 종류를 명시한다.
[STFT 문서](https://www.mathworks.com/help/signal/ref/stft.html)에서 창을 이동하며
DFT를 계산하는 정의를 확인했다. zero padding의 bin 간격과 실제 창의 분해능을
구분해 기록한다.
