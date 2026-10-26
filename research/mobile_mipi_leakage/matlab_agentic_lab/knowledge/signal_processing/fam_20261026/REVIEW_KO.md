# FAM·복소 IQ: iPhone 6 CSP 적용 검토

날짜: 2026-10-26. 상태: 원문 학습·수식 검토·실측 설계 완료. 이 문서는 새로운 FAM 실측 결과를 보고하지 않는다.

## 1. 읽은 범위와 출처

- 사용자 첨부 FAM 본문: Definition, implementation steps 1–5, conjugate extension, coherence equations (1)–(10), BPSK/DSSS 예제까지 읽었다. 138개 댓글 전체를 정독했다고 주장하지 않는다. 공개 페이지의 indexing 관련 댓글을 추가 확인했다.
- [Spooner, FAM, 2018-06-01](https://cyclostationary.blog/2018/06/01/csp-estimators-the-fft-accumulation-method/): 본문·수식·기술적 설명의 직접 출처.
- [Spooner, Conjugation Configurations, 2016-02-29](https://cyclostationary.blog/2016/02/29/conjugation-configurations/): eqs. (1)–(2), (18), 복소 신호의 두 2차 통계.
- [Spooner, SCF](https://cyclostationary.blog/2015/09/28/the-spectral-correlation-function/): 서로 다른 spectral components의 상관 정의.
- [Roberts, Brown, Loomis, 1991](https://doi.org/10.1109/79.81008): IEEE SPM 8(2),38–49, 서지·초록 확인. 이번에 이 논문 전체 PDF를 읽었다고 주장하지 않는다.
- 사용자 인용 “The Significance of IQ Data in CSP”: 제공된 내용을 검토했다.
- 아래 좌표 변환과 실험 조건은 위 정의에서 유도한 연구 메모다. 새로운 측정 결과와 구별한다.

## 2. 이번 연구에서 구별할 통계

기존 100/160MHz overlap coherence는 두 녹음의 동일 RF 성분 간 복소 파형 일치도다. FAM의 auto cyclic spectral coherence는 한 녹음 안의 서로 다른 두 주파수 성분 간 상관을 본다. 앞선 낮은 overlap coherence만으로 자기 순환정상성이 없다고 결론낼 수 없다. 반대로 높은 자기 cyclic coherence가 두 녹음의 coherent stitching 가능성을 보장하지 않는다.

이 문서의 convention은 symmetric lag와 시간 Fourier 계수 exp(-j2παt)다.

- Non-conjugate NC: R_NC^α(τ)=<x(t+τ/2)x*(t-τ/2)exp(-j2παt)>.
- Conjugate C: R_C^α(τ)=<x(t+τ/2)x(t-τ/2)exp(-j2παt)>.
- SCF: S^α(f)=∫R^α(τ)exp(-j2πfτ)dτ.
- NC spectral pair: X(f+α/2)X*(f-α/2).
- C spectral pair: X(f+α/2)X(α/2-f).

명칭은 헷갈리기 쉽다. 이 문헌에서 NC의 lag product에는 별표가 한 개, C에는 없다. 원문의 일반 cross estimator S_xy를 사용하면 NC는 y=x, C는 y=x*로 계산한다. C를 기존 spectral-bin pair의 별표만 지우고 같은 좌표·분모로 처리하면 틀린다.

C_NC^α(f)=S_NC^α(f)/sqrt(P(f+α/2)P(f-α/2)).
C_C^α(f)=S_C^α(f)/sqrt(P(f+α/2)P(α/2-f)).

SCF는 복소수로 저장해야 한다. |SCF|나 coherence 크기만 보존하면 timing phase 정보가 사라진다. power가 바닥인 bin의 정규화는 불안정하므로 두 분모 PSD의 신뢰 구간을 기록한다. NC α=0의 auto coherence는 일반적으로 1이므로 그 자체를 검출 증거로 쓰지 않는다.

## 3. CFO·지연·시간척도 변환: 직접 유도

모델: y(t)=x(a t-τ0) exp(j(2πνt+φ)), a>0.
이 τ0는 x의 시간 좌표에 있는 지연이며 y 관측 시간에서의 지연은 τ0/a다.

S_NC,y^α(f)=(1/a) exp(-j2πατ0/a) S_NC,x^(α/a)((f-ν)/a).

S_C,y^α(f)=(1/a) exp(j2φ) exp(-j2π(α-2ν)τ0/a)
             S_C,x^((α-2ν)/a)(f/a).

따라서 x의 feature (f0,α0)는 다음으로 이동한다.

| 변화 | NC | C |
|---|---|---|
| feature 좌표 | (a f0+ν, a α0) | (a f0, a α0+2ν) |
| 일정한 위상 φ | 소거됨 | 2φ로 나타남 |
| a=1 지연 위상 | -2πατ0 | -2π(α-2ν)τ0 |
| 같은 관측 채널 전제 | 반드시 필요 | 반드시 필요 |

NC의 α는 일정한 CFO에 불변이다. f축은 CFO에 이동한다. 시간축 오차는 α도 늘이거나 줄인다. C의 α축은 2ν만큼 이동한다. 두 종류를 함께 비교하면 CFO와 시간척도 가설의 검증에 도움이 된다. 신호가 C 특징을 갖지 않으면 이 경로의 CFO 추정은 사용할 수 없다.

일반 (n,m) moment에서는 carrier 항이 (n-2m)ν를 갖는다. n=2,m=1은 0, n=2,m=0은 2ν다. 고차 moment가 무조건 유리하지는 않으며 약한 신호에서 추정 분산·관측시간 부담이 커진다.

중요: NC auto-SCF로 상수 RF 위상 φ를 추정할 수 없다. C에서도 2φ이므로 π 모호성이 남고, 미지 신호·채널 위상과 분리돼야 한다. FAM은 stitching의 모든 정렬 파라미터를 자동 결정하는 알고리즘이 아니다.

## 4. 100/160MHz에 적용할 좌표와 이전 추정치

입력 Fs=124.0828 MS/s는 사용자 제공 값. nominal bandwidth=120MHz. 저장 표현 big-endian int16 I,Q, RF 방향은 기존 검토의 I-jQ 가설을 유지하고 반대 부호 대조를 보존한다.

두 녹음의 중심주파수 차이60MHz는 conjugate α에 nominal 120MHz 차이를 만든다. 따라서 두 subband를 같은 RF 중심, 예를 들어106MHz로 DDC하고 같은 필터·표본률을 사용한 다음 residual CFO를 비교해야 한다.

이전 +712.642796Hz가 같은 물리 성분의 CFO이고 적절히 시간척도를 맞췄다면:
- NC α: 이 CFO로는 이동하지 않음.
- C α: 예상 이동 +1425.285593Hz.
이 수치는 CSP 관측값이 아니라 이전 CFO 가설에서 계산한 검증 예측이다.

기존 row112802.551754/112802.550122Hz 및 frame59.96946Hz는 1881-row prior에서 나온 후보다. CSP에서 이를 강제로 맞추거나 harmonic이라고 미리 결론내리지 않는다. broad scan의 후보와 비교 표식으로만 사용한다. 두 row 값의 차이는 약0.001632Hz라서 1초급 비모수 α-grid만으로 그 차이를 직접 분리하지 못한다. Sub-bin 추정 주장은 별도 오차·phase-stability 검증이 필요하다.

## 5. FAM 구현 규약

입력 x[rL+n], n=0..N'-1, r=0..P-1.
Hamming channelizer window a[n], hop L, slow-time window g[r].

1. 채널별 local FFT U_k[r]=Σ_n a[n]x[rL+n]exp(-j2πk n/N').
2. local FFT를 global-time Fourier reference로 변환:
   X_k[r]=U_k[r]exp(-j2π f_k rL/Fs).
3. 두 채널의 X_k[r]Y_l*[r]g[r]를 slow-time FFT.
4. blog convention에서 f=(f_k+f_l)/2,
   α=(f_k-f_l)+q Fs/(PL).
   직접 X_kX_l을 사용하는 C 구현의 좌표는 f=(f_k-f_l)/2, α=f_k+f_l+q Fs/(PL)이다. y=x*를 쓰는 generic cross 구현과 혼동하지 않는다.
5. q에 signed FFT bin을 쓴다면 FFT output과 함께 fftshift하고, unshifted index를 쓴다면 modulo wrapping을 정확히 처리한다. “fftshift는 항상 틀림”이라는 의미가 아니다.
6. NC/C에 맞는 PSD denominator와 허용 principal domain을 적용한다. 구간 밖 주파수의 PSD를 외삽하지 않는다.
7. 실제 기록 길이는 (P-1)L+N'이며, α FFT grid의 N=PL과 구별해 기록한다. 가급적 실제 guard samples를 읽고 zero-padding 여부를 남긴다.
8. Δf≈Fs/N'는 channelizer bin spacing이다. 실제 분해능은 window mainlobe/ENBW와 함께 보고한다. Δα=Fs/(PL)는 FFT spacing이며 정확한 추정 불확실성과 동일하지 않다.
9. 서로 다른 channel-pair estimate를 (f,α) grid에 배치할 때 중복·가중치·버린 경계를 기록한다. axis convention은 synthetic known cycle로 검증한다.
10. 고밀도 N'^2 P 배열을 전부 만들지 말고 channel-pair batch를 처리하면서 cyclic-domain profile과 필요한 SCF slices를 저장한다.

추가 정규화·위상 규약:
- U_a=Σ|a[n]|², G_0=Σg[r]일 때 비정규화 FFT의 기본 density scale은1/(Fs U_a G_0)다. NC k=l,q=0이 같은 창·평균의 양측 PSD와 같아야 한다. 복소 IQ에 일측 PSD의×2를 적용하지 않는다. 비영 q에서는 channel response의 평활화·감쇠를 확인한다.
- local block 원점n0로 계산한 cyclic phase를 공통 전역 시각으로 환산할 때 exp(-j2παn0/Fs)를 적용한다. 서로 다른 녹음의 실제 공통 시작 시각은 알려지지 않았으므로 임의 생성하지 않는다.
- weighted pair correlation을 같은 채널 energy로 정규화하면 Cauchy–Schwarz 범위를 유지할 수 있으나 이는 smoothed channel-pair 지표다. 점별 population coherence와 구별한다. |C|와 |C|²도 구별한다.

CDP(α)=max_f |C^α(f)|는 전체 f에서 최대를 취한다. f=0 slice와 다르다. 최대값은 다중 탐색의 편향을 가지므로 상위 quantile, 유효 spectral support 폭, repeated-block persistence도 함께 저장한다.

MATLAB Signal Processing Toolbox를 이용해 resample/AA FIR/pwelch를 처리하고, FAM의 channelization·pair accumulation은 명시적인 FFT로 구현할 수 있다. stft/mscohere 결과에 FAM 이름을 붙이지 않는다. 댓글의 출처 불명 구현을 복사·실행하지 않는다.

## 6. 실제 데이터용 다중 해상도 설계

복원·평균·notch 전의 IQ에서 발견 단계를 시작한다. 이미 row를 맞춘 파형만 분석하면 알고리즘이 주입한 반복성을 발견할 위험이 있다.

A. 넓은 RF 범위 발견:
- 두 수신본 각각 native bandwidth에서 coarse NC/C 분석.
- 106MHz subband만 보고 전체 화면 대역/bit cycle을 판단하지 않는다.
- cyclic support가 큰 RF 구간을 찾고, overlap 안의 공통 후보와 각 단독 대역 후보를 나눠 기록한다.

B. 동일 RF subband 정밀 분석:
- nominal106MHz에서 양쪽 녹음을 같은 필터로 DDC.
- AA 후 q=16이라면 Fs'=7.755175MS/s. 앞선 canonical-frame TF의7.860316886MS/s와 다른 격자다.
- 예시 N'=128,L=32. 채널 spacing60.587305kHz.
- N=2^20, P=32768이면 관측시간135.209844ms, Δα7.395911Hz, 약8.1frame.
- N=2^23이면1081.678750ms, Δα0.924489Hz, 약64.9frame. 이 긴 구간은 전체 dense FAM보다 발견된 소수 α 주변의 targeted cyclic estimation에 적합하다.
- 긴 관측에서 drift가 있으면 α peak가 번지므로 sliding-block feature 위치/복소 위상도 저장한다.

C. 필터의 관측 가능성:
- NC는 f±α/2 양쪽 성분이 모두 통과해야 한다.
- C는 f+α/2와 α/2-f가 모두 통과해야 한다.
- 일반 LTI filter는 NC SCF에 H(f+α/2)H*(f-α/2), C에는 H(f+α/2)H(α/2-f)를 곱한다.
- 원하는 α보다 passband가 좁으면 관련 frequency pair를 잘라낸다.
- 낮은 Fs는 같은 N으로 더 오래 관측하게 해주지만 기존 기록에 새 정보를 추가하지 않으며 버린 RF 성분을 복구하지 않는다.
- 120MHz RF slice만으로 Gbps D-PHY bit rate/byte rate를 직접 유일하게 결정할 수 없다. 관측된 harmonic/subharmonic·gating 주기와 lane interleaving 후보를 별도 모델 비교해야 한다.

## 7. 잡음·세로선·허위 cycle 대조

- 이상적인 zero-mean proper WSS noise는 NC α≠0 및 C 통계의 기대값이0이다. 유한 표본 추정값은0이 아니다.
- deterministic single tone은 C에서 doubled-tone 위치, 여러 coherent tone은 NC에서 difference frequencies를 만든다. clock, source/column driver도 cyclostationary일 수 있다.
- 그러므로 “cycle 있음 → MIPI payload” 또는 “주기적 간섭은 CSP에서 사라짐”은 성립하지 않는다.
- 원본 대조를 유지하고 PSD line 주변 mask 여부와 유효 pair 수를 기록한다. line masking으로 원하는 정보를 지울 수도 있다.
- synthetic checks: proper colored Gaussian noise, 알려진 cycle의 BPSK/AM, single tone/two tones, known CFO/time scaling, finite delay.
- 경험적 null threshold는 전체 CDP 검색과 같은 smoothing·overlap·grid를 사용한다. overlapping blocks를 독립 표본이라고 세지 않는다.
- spectral phase randomization만으로 tone beating false positive가 해결된다고 가정하지 않는다. tone-preserving 대조도 필요하다.
- 후보 선택 구간과 확인 구간을 분리하고, 보정 없는 원본·CFO only·time only·both를 동일 조건으로 비교한다.
- 서로 순차 취득한 녹음은 동일한 random realization이 아니다. 반복 통계 일치가 즉시 sample-wise 위상 합성 가능성을 뜻하지 않는다.

## 8. Stitching에 연결하는 방법

1. auto NC/C SCF와 cyclic coherence로 RF·α 후보를 찾는다.
2. 반복 측정/held-out 구간에서 지속되는 feature인지 확인한다.
3. 같은 RF 좌표에서 NC α spacing과 C α 이동을 비교해 SFO/CFO 모델을 검증한다.
4. 원본 IQ를 보정한다.
5. 공통 유효 주파수 쌍의 cross statistics와 실제 overlap phase slope로 delay/phase를 재평가한다.
6. unmasked/masked 평가, timing 잔차, delay comb ambiguity, 같은 프레임의 화면을 확인한 뒤 LR stitching에 반영한다.

NC cyclic phase는 signal-selective delay 추정에 유용할 수 있지만 single α에서는 modulo1/α 모호성이 있다. 실제 수신 경로의 주파수별 위상과 unknown source cyclic phase도 포함될 수 있으므로 위상 기울기를 곧바로 cable delay로 해석하지 않는다.

## 9. 다음 실행의 필수 산출물

- native IQ identity/offset/Fs, DDC 중심, AA filter, 출력률, 데이터 길이, N',L,P, normalization, valid-domain mask.
- NC/C SCF magnitude·phase·coherence의 (f,α) 지도.
- CDP와 RF support map; row/frame 후보는 사후 비교선.
- block별 α 이동과 cyclic phase, CFO·time correction ablation.
- synthetic/null/held-out 대조와 후보 신뢰도.
- 해당 후보를 사용했을 때만 다음 stitching 결과를 비교.

현재 판정: 원문은 낮은 SNR·강한 주기 간섭 상황에서 “반복 구조가 어디에 있는가”를 조사하는 데 적합한 근거다. 실제 iPhone DSI/HS cycle 검출 또는 stitching 개선은 아직 FAM으로 측정되지 않았다.
