# O’Connell 원문 정독 기록: PDF/인쇄 쪽 61–108

- 문헌: Christian David O’Connell, *Exploiting quasiperiodic electromagnetic radiation using software-defined radio* (2018).
- 원문 파일: C:/Users/leechanghoon/Desktop/연구/다중모니터 복원/TMDS/Exploiting quasiperiodic electromagnetic.pdf
- 읽은 범위: 61–108쪽 전체. 본문, 수식, 각주, 표, 그림 설명을 페이지별 추출본으로 연속 정독했다. 80쪽은 장 끝의 공백 페이지다.
- 시각 대조: 66, 78, 83, 89, 90, 92, 93, 96, 99, 100, 101, 105쪽을 원본 PDF에서 렌더링하여 확인했다. 특히 99–101쪽의 수식 문제는 OCR 추측이 아니라 인쇄 수식과 대조했다.
- 작업 상태: 문헌 해석 및 측정 설계 제안이다. 이 기록에서 새 RF 측정이나 MATLAB 수치 실험을 수행하지 않았다. 이 파일은 전체 원문 중 담당 범위만 보증한다.

## 1. 페이지별 읽기 범위

| 쪽 | 확인 내용 |
|---|---|
| 61–64 | Welch PSD, CNR/중앙값 바닥 지표, 수동 탐색의 한계, 홀수 고조파 후보 분류 |
| 65–68 | 후보 모드 점수, TMDS blanking의 진폭/위상 구조, 자기상관과 FFT/제로패딩 |
| 69–72 | power cepstrum, frame/line quefrency, 후보 고조파의 주기성 결합 |
| 73–76 | rho-score, threshold/false positives, 탐지 알고리즘 1 |
| 77–80 | 고조파 선택, 실제 보이는 영상과 장치 탐지의 차이, Chapter 3 결론 |
| 81–84 | Chapter 4 문제 정의, HDMI clock 측정, 오실레이터 오차, HSV 위상 회전 |
| 85–88 | 고정 CFO acquisition, DDS, frame 평균 FIR 및 PLL 입력 decimation |
| 89–92 | PID, 위상 검출, NCO, unrotation, HSV 시간 변화 및 PLL 고장 양상 |
| 93–96 | overlapping Allan deviation, variable-rate Lanczos resampling, drift 그림 |
| 97–100 | fixed-point 위치 누산기, 정밀도, coherent 평균 통계와 Rice 진폭 편향 |
| 101–104 | 복소 평균의 분산, integrate-and-dump/IIR, 1,728 frame 실험 결과 |
| 105–108 | 동일 데이터의 real/complex 평균 그림, 거리/차폐 모형, Chapter 4 결론 |

## 2. 원문의 구조: stitching보다 앞서 확보한 것

Chapter 3는 “강한 RF peak”와 “화면을 운반하는 peak”를 구별하는 탐지 단계다. Chapter 4는 찾아낸 고조파의 공통 clock을 추적하여 **복소 위상과 영상의 시간 좌표를 함께 고정**한다. 두 보정은 서로 대체되지 않는다.

1. 횡방향 위치가 일치해도 frame별 복소 위상이 달라지면 평균에서 원하는 신호가 상쇄된다.
2. 복소 위상이 일치해도 시간 좌표가 drift하면 서로 다른 pixel을 평균하여 경계가 무너진다.
3. 원문의 clock tracking은 HDMI/TMDS의 특정 clock 고조파와 pixel rate의 알려진 관계를 이용한다. 이 관계를 MIPI-DSI 데이터 lane, HS clock, 표시 패널 scan clock에 그대로 대입할 근거는 이 장에 없다.

따라서 모바일 적용에서 중요한 선행 작업은 “논문의 PID를 복사하는 것”보다 **어느 관측 성분이 어느 시간 좌표를 안정적으로 대표하는지 식별하는 것**이다.

## 3. Chapter 3에서 가져올 것과 가져오면 안 되는 것

### 원문 관찰/방법

- p61 Eq.3.2의 CNR은 PSD 특정 bin과 전체 median의 비이다. 화면 신호와 잡음을 분리한 물리적 SNR 추정치가 아니다. 논문 실험의 peak 간격 탐색 파라미터는 f_min = 8 MHz이다.
- pp63–65는 VDU 후보 모드와 홀수 clock 고조파를 대응시키고, 주파수 허용 오차 epsilon = 0.005를 확률 모형에 사용한다. 이는 그 논문의 모드 후보 탐색 가정이지 현재 장비 교정 정확도나 모바일 timing 오차의 허용 기준이 아니다.
- pp65–66 Fig.3.4: 해당 TMDS blanking에는 bit transition이 많아 진폭이 커지고, control character 변화가 적어 unrotation 후 위상 분산이 낮아지는 구간이 나타난다.
- pp66–71 Eq.3.14–3.26: overlap-normalized autocorrelation과 power cepstrum을 비교한다. power cepstrum은 log power spectrum의 IFFT 절댓값 제곱이다. 이 데이터에서는 frame/line peak의 구분이 더 선명하다. “항상 autocorrelation보다 우수하다”는 보편적 결론이 아니다.
- pp72–76 Eq.3.27–3.37: 예상 row/frame quefrency에서 값을 읽고 rho_c = L_v,c L_h,c h_c^2로 고조파 점수를 만든다. 사용 threshold 10^-4는 원문의 스케일, 창, 데이터에 종속된다.
- pp77–79 Fig.3.11: 장치/주기성을 탐지해도 raster 내용이 눈에 보이지 않을 수 있다. 가장 강한 carrier나 가장 낮은 고조파가 항상 가장 유용한 영상 대역은 아니다.

### 모바일로 옮길 때의 제한

- DSI command mode, burst 구간, blanking 전송 형태가 확인되지 않은 상태에서 “HDMI와 같은 밝은 blanking 사각형이 반드시 있다”고 가정하지 않는다.
- fh/fv 주기성은 신호 선별의 근거가 되지만 source identity의 증명은 아니다. 패널 row/column driver, 전원 또는 공통 clock에 동기된 clutter 역시 동일한 주기성을 가질 수 있다.
- 홀수 고조파 모델, VESA total geometry, h_c^2 정규화, 원문의 threshold는 모바일 데이터에 자동 적용하지 않는다.
- cepstrum 입력 단위/로그 기준과 FFT 정규화를 저장해야 한다. 원문의 dBμV^2 표기를 물리적 잡음 전력 단위처럼 해석하지 않는다. 단위 없는 정규화 로그 스펙트럼과 정해진 창/FFT 규모로 비교하는 구현이 더 명료하다.

## 4. Chapter 4의 정확한 처리 연결

### 4.1 Acquisition: 고정 오차 제거 (pp84–87)

원문은 RF에서 선택한 clock harmonic을 수신기의 DC/LO 누설점에 너무 가깝게 놓지 않고, 수신 대역 안에 충분히 포함시킨다(Eq.4.4). PSD 관찰 길이를 최소 약 1초로 권고하여 고조파 주파수의 bin 간격을 1 Hz 이하로 만든다(Eq.4.9). bin 간격은 추정 정확도/오차 보증과 다르다.

수신 IQ에 고정 NCO의 conjugate를 곱해 고정 offset을 제거한다(Eq.4.7–4.8). 이 단계는 thermal drift를 제거하지 못한다. Fig.4.4에서 큰 단조 위상 회전은 줄지만 장시간 위상 곡선은 여전히 변한다.

원문의 DDS 설정은 beta = 64 bit phase accumulator와 alpha = 10 bit lookup table이다(pp86–87). 이는 당시 구현의 정밀도/연산량 선택이며, 현재 구현에서 반드시 LUT를 사용해야 한다는 뜻은 아니다.

### 4.2 Tracking: frame 평균을 입력으로 하는 PLL (pp87–93)

- Eq.4.13–4.16: M = round(Fs/f_PLL), f_PLL = fv, b[i] = 1/M. 한 frame 길이의 boxcar FIR를 적용하고 M배 decimate한다.
- 원문 사례의 FIR cutoff는 약 26.5 Hz. 이 수치는 약 60 Hz frame 주기의 boxcar 응답에 종속된다. 별도의 통용 PLL loop bandwidth 수치로 사용하면 안 된다.
- Eq.4.18: e[n] = q_w[n] conj(u_t[n]). error의 argument로 위상 차를 얻는다.
- Eq.4.19와 Fig.4.7: PID가 추정한 drift로 NCO를 구동하고, 원래 wideband IQ에 그 conjugate를 곱한다(Eq.4.20).
- 실험 tuning: K_P = 5 Hz/rad, K_I = 2 Hz^2/rad, K_D = 0.1 rad^-1. 원문에서 경험적으로 선택했다(p90). **loop update rate, detector gain, harmonic index, 신호 세기 등이 바뀌는 모바일에 그대로 사용할 보편 상수가 아니다.**
- Fig.4.9: 30 frame을 세로로 나열하면 acquisition만 수행한 결과는 시간이 지날수록 hue가 바뀐다. tracking 후 대체로 한 hue를 유지하나 blanking/content 사이의 상대 위상은 남는다.

**구현 주의:** Eq.4.19에는 PID 조합 밖에 추가 합산이 있으며, 교과서의 단순 positional PID와 같다고 읽으면 안 된다. PLL rate에서 얻은 추정치를 원래 Fs로 전달할 때 인덱스, 보간/hold, FIR group delay 및 경계 지연을 명시해야 한다. 원문의 고정 f_PLL=fv는 clock이 지속적으로 존재하고 frame 평균이 유효한 관측량이라는 조건을 포함한다. HS burst가 없는 시간이나 약한 clock 구간에서는 phase detector를 정지/마스킹하거나 별도의 모델을 검증해야 한다.

### 4.3 위상 변화와 기존 HSV banding의 관련성 (pp84–92)

Fig.4.3은 h*fp와 receiver fc의 차이가 크면 한 row 안에서도 여러 번 hue가 회전함을 보여준다. Fig.4.9는 작은 잔차가 frame 여러 개에 걸친 hue 변화로 나타남을 보여준다. 원문은 rainbow banding 및 변하는 band 폭을 PLL 잔차/진동의 진단 단서로 사용한다(p91).

이를 모바일에 적용할 때 banding 자체로 LCD column driver를 특정할 수 없다. 일정 CFO의 위상 램프를 raster로 접으면 연속적인 색 띠가 생긴다. 원/숫자 주변에서만 띠가 두드러지는 것은 그 위치에서 진폭이 커져 상대 위상 hue가 더 잘 보이는 경우, 내용에 의존하는 위상, 필터/대역제한의 응답 등이 모두 후보이다. 구별하려면 같은 IQ의 (a) raw phase, (b) 고정 CFO 제거, (c) drift 제거, (d) 진폭 threshold를 동일하게 유지한 위상 그림을 순서대로 비교해야 한다. 원문은 모바일의 특정 세로선이 어느 회로에서 나왔는지 증명하지 않는다.

### 4.4 시간 좌표: variable-rate resampling (pp94–98)

원문 Eq.4.24–4.27은 다음을 함께 사용한다.

- 추정 pixel rate: f_p_tilde[n] = f_p + f_d + f_t_tilde[n]
- 출력 pixel 하나당 진행할 입력 sample 수: R[n] = Fs/f_p_tilde[n]
- 연속 입력 위치: nu[m+1] = nu[m] + R[floor(nu[m])]
- 그 위치에서 complex IQ를 interpolation한다.

주의할 점은 이 R가 “출력 sampling rate / 입력 sampling rate”가 아니라 **입력 sample / 출력 pixel**이라는 것이다. Chapter 5의 resampling 비율 정의와 방향을 혼동하지 않아야 한다.

Lanczos kernel radius K = 2를 사용했다(p95). 원문도 큰 downsampling 비율에는 먼저 anti-aliasing filter가 필요하다고 명시한다. Lanczos interpolation으로 수신하지 않은 대역 정보를 만들 수 없다.

Fig.4.11: 60 frame 동안 단순 nominal-rate resampling은 약 200 pixel의 횡방향 drift를 보이고, variable resampling은 이를 고정한다. phase unrotation만으로는 이 시간 오차가 해결되지 않는다.

pp97–98 Eq.4.31–4.32: averaging 동안 누적 drift를 0.1 pixel 이내로 제한하는 표현 정밀도를 계산한다. 25.2 MHz, 20초 사례는 beta > 32.23 bit이다. 64 bit 구현으로 계산한 수천 년의 한계는 **누산기 양자화 오차만의 이론 한계**이고 실제 clock 추정이나 표시 상태의 안정성 보증이 아니다.

### 4.5 averaging과 안정성 (pp93–94, 98–107)

- Eq.4.21은 unwrapped phase의 second difference에 기반한 overlapping Allan deviation이다. 원문 그래프 단위는 rad/s이며, 보통의 fractional-frequency ADEV로 보고하려면 reference frequency와 2π 정규화가 추가로 필요하다.
- Fig.4.10은 tracking 후 장시간 척도에서 ADEV가 감소하는 사례다. Eq.4.23은 최소점을 averaging 시간 선택에 사용한다. 실제 적용에서는 유한 표본 수/신뢰구간, cycle slip, 내용 변화, 추정기에 의해 강제로 평탄화된 phase를 함께 보아야 한다. 가장 오른쪽의 단일 최소점만으로 최적 길이를 확정하지 않는다.
- Eq.4.33은 동일 좌표의 stationary pixel을 여러 frame에서 관측한다. 동기된 목표와 평균에서 위상이 분산되는 간섭/잡음을 구분한다.
- Eq.4.45는 complex mean을 취한 뒤에 demodulation한다. 반대로 매 frame의 abs를 먼저 평균하면 Rice/Rayleigh magnitude bias가 남는다.
- 독립 zero-mean noise이고 목표 복소 위상이 완전히 맞을 때 component variance는 sigma^2/F, amplitude-to-standard-deviation 비는 sqrt(F)배, dB 이득은 10 log10(F)이다. 이것을 현재 측정의 물리적 SNR로 부르려면 목표/잡음 정의와 독립 검증이 필요하다.
- integrate-and-dump Eq.4.54는 모든 frame을 저장하지 않아도 복소 누산기 한 장으로 계산할 수 있다. exponential smoothing Eq.4.55의 component variance는 gamma*sigma^2/(2-gamma). 과거 내용의 잔상이 남는 조건을 기록해야 한다.
- 실험: d = 9 m에서 1,728 frame 평균, acquisition f_d = 120.5 Hz. Fig.4.14는 nominal/고정 offset 보정만으로는 text가 선명해지지 않으며, Fig.4.15는 tracking 후 complex averaging에서 text와 cross가 읽히는 것을 보인다. magnitude 평균 그림은 약 22.45–25.54 μV, complex 평균은 0–11.08 μV로 서로 color scale이 다르다. 그림 밝기 자체를 공통 scale의 정량 SNR 비교로 사용하면 안 된다.

## 5. 인쇄 원문에서 확인한 통계 수식 문제

이 항목은 번역/OCR 오류가 아니라 **원본 p99–101 렌더에서 확인한 표기/논리 문제**다. 복소 평균의 실용적 장점은 유효하나 아래 식을 그대로 코드/증명에 복사하지 않는다.

| 위치 | 원문 문제 | 일관된 해석/수정 |
|---|---|---|
| p99 Eq.4.37 | Gaussian log likelihood 정규화 항 부호가 맞지 않고 관측 수 표기가 N/F로 섞임 | log L = -F/2 log(2π sigma^2) - sum((y_i-mu)^2)/(2 sigma^2) |
| p99 Eq.4.38b | second derivative를 +F/sigma^2로 인쇄 | -F/sigma^2이어야 Eq.4.39의 Fisher information F/sigma^2와 일치 |
| p100 Eq.4.44 | interferer의 합까지 F를 곱한 괄호로 묶음 | sum의 mean은 F mu cos(phi) + mu_n sum cos(phi_n[i]) |
| p100 Eq.4.46 | 평균 interferer 항에 1/F가 없음 | E(mean의 실수부) = mu cos(phi) + (mu_n/F) sum E cos(phi_n[i]) |
| p100 Eq.4.47 앞 문장 | zero cross-correlation이면 phase가 uniform이라는 주장 | zero cross-correlation만으로 uniform phase distribution은 따라오지 않음. 필요한 조건은 alignment 이후 간섭의 복소 평균이 0이고 적절히 감소하는 covariance |
| p101 Eq.4.49–4.50 및 결론 | component variance와 complex variance, 복소 평균의 무편향성과 magnitude의 무편향성이 혼재 | 각 성분 variance sigma^2/F, E|z-Ez|^2는 2 sigma^2/F. abs(E z)=mu와 E abs(z)=mu는 다름. finite F에서 abs(complex mean)도 Rice bias를 가짐 |

결론적으로 “complex mean은 알려진 고정 phase의 Gaussian mean 추정에서 효율적”이라는 제한된 통계 명제와, “최종 magnitude가 어떤 간섭에서도 무편향”이라는 주장은 구분해야 한다. 현재 목표와 같은 frame-synchronous driver clutter는 complex averaging 후에도 남을 수 있다.

## 6. LG / iPhone 6 stitching 측정을 위한 적용 판단

다음은 원문 사실과 분리한 **제안**이다. iPhone 6s 결과를 iPhone 6 결과로 대체하지 않는다.

### 6.1 100 MHz sweep 관찰이 뒷받침하는 범위

여러 center frequency에서 화면이 복원되는 것은 해당 RF 범위에 화면 관련 정보가 존재한다는 유용한 관찰이다. 서로 다른 순차 capture가 동일한 복소 waveform의 서로 겹치는 spectral 부분인지는 추가 검증 대상이다. 일부 band는 다른 공통 clock/driver 성분이 우세할 수 있으며, 각 band에서 magnitude 영상이 보인다는 조건만으로 상대 위상/지연이 식별되지는 않는다.

### 6.2 측정에서 확보할 최소 항목

1. 장치별 고정 test screen, 표시 밝기, 회전, refresh 상태, 터치/애니메이션 상태 및 capture 순서. 정적인 screen에서도 전송 burst/패널 반전 주기가 여러 frame일 수 있으므로 반복 주기를 직접 확인한다.
2. 실제 sample rate와 usable RF bandwidth를 별도로 기록한다. USRP 사양의 순간 BW, 파일 Fs, sweep 전체 span을 같은 수로 쓰지 않는다.
3. 각 center의 연속 IQ, RX gain/필터/clock/time source, retune 시점 및 안정화 구간, overflow, 실제 readback frequency. 각 band의 phase reference와 raw sample offset을 보존한다.
4. 동일 anchor band를 A–B–A 순으로 재측정한다. A1/A2에서 동일한 시간 좌표/복소 파형을 다시 얻을 수 있는지 먼저 검증한다.
5. 넓은 한 번의 capture에서 가상 overlap subband들을 분할하여 stitch하는 내부 대조 실험을 먼저 한다. 이는 filter, delay/phase 부호, amplitude complement, edge transient를 검증한다. 실제 retune/순차 측정의 재현성을 증명하는 실험은 별도로 수행한다.

### 6.3 복소 일관성 확인 지표

- 시간 정렬 후 overlap complex coherence를 별도 frame/window에서 평가한다. fitting에 사용한 동일 samples에서 높은 coherence가 나온 것은 독립 검증이 아니다.
- overlap 위상차를 단일 상수로 설명할 수 있는지, 주파수에 대한 선형 slope(상대 delay)가 필요한지, 시간에 따른 slope(잔여 CFO)가 남는지 분리한다.
- 반복 capture에서 얻은 delay/drift estimate, 위상잔차, complex gain 및 주파수 응답의 신뢰도를 보존한다. 한 단계의 오류가 이후 band로 누적되는지 anchor-return과 역방향 sweep으로 확인한다.
- 화면 전체가 아닌 목표 내용 영역, 세로선 우세 영역, 저진폭 영역을 분리해 coherence와 개선을 비교한다. 저진폭 phase에는 mask를 적용한다.
- 화면 pattern 변경을 독립 확인에 사용한다. 목표 screen의 구조/경계가 바뀔 때 변화하는 성분과 안정적으로 남는 세로선을 비교하되, 안정적으로 남는 성분이라는 사실만으로 물리적 source를 단정하지 않는다.
- 가능하면 동일 wideband capture를 기준으로 complex NRMSE/overlap error와 영상 경계 복원 품질을 함께 비교한다. 고대역을 붙였다는 사실만으로 식별 가능한 화면 정보가 증가했다고 판단하지 않는다.

### 6.4 모바일에서 직접 재검증할 가정

- clock harmonic과 raster pixel rate의 일대일 관계가 있는가?
- 동일한 nominal frame이 byte/burst/line 수준에서도 재현되는가?
- retune 사이 시간 변화가 scalar phase, delay 및 clock drift로 설명되는가?
- 목표 데이터와 driver clutter가 같은 clock에 잠겨 있는가? 그렇다면 coherent averaging만으로 둘을 분리할 수 없다.
- 대역별 수신 경로/방사 경로 응답 차이는 overlap에서 안정적으로 추정 가능한가?

원문 Chapter 4를 정확히 옮긴다는 것은 위상 회전 제거와 시간 좌표 보정을 함께 검증하는 것을 뜻한다. 신호 주기성을 확인한 다음 그 관계가 유효한 구간에서만 frame averaging과 band stitching을 적용하는 것이 모바일 이식의 핵심이다.
