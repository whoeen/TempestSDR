# O’Connell 원문 검토: 109–155쪽과 구현 대조
검토일: 2026-10-22. PDF 페이지와 인쇄 페이지 번호가 일치한다.

원문: Christian David O’Connell, *Exploiting quasiperiodic electromagnetic radiation using software-defined radio*, Cambridge, 2018. [공식 저장소](https://www.repository.cam.ac.uk/handle/1810/290902), DOI 10.17863/CAM.38085.

## 검토 범위와 증거
- 전체 텍스트 109–155쪽을 읽었다. 출력이 잘린 142–150쪽은 별도로 재독했다. 151쪽은 256개 TMDS 값의 표를 텍스트와 원본 배치로 확인했으나 모든 코드워드를 재계산한 것은 아니다.
- 시각 대조: 110, 112–116, 119–121, 128–129, 149–151, 155쪽. 단순 OCR로 수식 부호를 확정하지 않았다.
- 109–130: 5장 전체. 131–136: 결론/미해결 문제. 137–146: 참고문헌 목록. 147–152: TMDS 인코더·디코더·표. 153–155: 시험 영상 설계.
- 참고문헌 목록을 읽었다는 것은 인용된 117개 문헌의 원문까지 모두 읽었다는 뜻이 아니다.
- 로컬 원본 SHA-256: aa81cb80e1e91e0ef928934302d222b087336edbb53af866b176181d6c1e4876, 119,554,888 bytes, 155 pages.
- 초기에 검색된 Erdeljan 2023 DisplayPort 학위논문은 5장 내용이 다르므로 이 번역의 출처에서 제외했다.

## 1. 5장의 두 실험은 목적과 대역폭이 다르다
1. **공간 해상도 개선**: 119/121쪽, Fig. 5.8. 1 MHz 녹음 9개, 0.5 MHz overlap, 합성 5 MHz. 동일한 800×525 total raster, fp=25.2 MHz. 중심 clock harmonic의 가장 좋은 단일 대역과 비교했다. 더 선명한 문자/눈금/십자를 관찰했다. 이것은 비트 전체/임의 RGB 복원 실험과 구별한다.
2. **TMDS 상태 분류**: 119–129쪽. 160 MHz 녹음 3개, 80 MHz overlap, 합성 320 MHz, fc=756 MHz=3fb, fb=252 MHz. 120쪽에서 장치별 emission pattern을 별도 학습하고 red/green/blue/white/black의 5색으로 제한한다.
3. 방사는 네 선쌍의 혼합이며 전이의 크기로 상승/하강 부호를 직접 얻지 못했다(119–122). 동일 TMDS 문자도 케이블별 관측 파형이 달라졌다(Fig.5.9).
4. HMM은 40개 RGB 문자 조합 상태, 원래 counter까지 포함하면 2,773개. modified Viterbi survivor별 counter로 계산량을 줄인다(124–127). 관측은 threshold 0.3의 binary transition pattern이며 같은 장치 profiling에서 emission probability를 얻는다.
5. Fig.5.13의 최소 **표시된** pixel error rate는 약 0.31, 단순 분류는 약 0.50이다. 그래프에서 읽은 근사치이며 데이터 파일 재계산값이 아니다. 완전한 RGB decode의 증거로 인용하지 않는다. Eq.5.59 인쇄식은 일치하는 픽셀 비율을 쓰면서 error rate라고 부르므로 지표 정의도 구현 전에 정리해야 한다.

## 2. 붙여넣은 번역과 원문을 구별해야 하는 지점
| 위치 | 원문을 직접 확인한 내용 | 구현에서 채택할 해석 |
|---|---|---|
| p110 Eq.5.1 | 목표 B′에 대해 이미 ceil을 사용 | ceil은 번역자가 새로 보탠 단계가 아니다. 실제 덮은 B는 Eq.5.2로 별도 계산 |
| p112 Eq.5.7 | R=입력 Fs/출력 Fs | 번역에는 역수로 표시. 입력 좌표의 증가량 R과 출력률 증가 L/M을 별도 이름으로 사용 |
| Eqs.5.8/5.11 | L/M=출력 Fs/입력 Fs | 이 식들은 서로 일치. 큰 실수 Fs를 문자 그대로 LCM에 넣지 않고 허용 오차를 둔 rational/fractional resampling 사용 |
| pp113–114 Eqs.5.14/5.17/5.20 | 아래의 켤레·lag 차이 확인 | MATLAB FFT convention에 맞춘 한 정의로 고정하고 양·음 delay 시험 |
| p114 Eqs.5.15/5.16 | 지수 floor(log2(N+P−1))+1 | 붙여넣은 ceil+1과 다름. 선형 상관에는 Nfft≥N+P−1이면 충분; 원문 prose와도 표현 차이 있음 |
| p115 Eq.5.23 | 분자 ωx | DC gain 1인 2차 Butterworth 분자는 ωx². 원문 fx=Fs/4의 정규화 예에서는 ω̃x=1이어서 차이가 가려짐 |
| p116 Eq.5.27 다음 문장 | HL 자체를 unit circle에서 real-valued라고 표현 | 실수 계수라도 HL(e^jω)는 일반적으로 복소수. zero-phase인 것은 HL(e^jω)HL(e^−jω)=|HL|² |
| pp112–113 vs p119 Algorithm4 | 본문에는 첫 band 정렬·필터 생략을 명시 | 첫 band를 기준으로 넣는 분기를 구현. y=0과 상관하지 않음 |
| p118 Eq.5.37 | exp(−jπBn/Fs) | 정확히 B/2 하향 이동. 이 식에는 factor-of-two 오류 없음 |

### 상호상관: 독립적인 MATLAB 검증
인쇄된 Eq.5.17을 MATLAB의 fft/ifft로 계산하면
\[
r[d]=\sum_n w[n+d]\,y[n]^* .
\]
이는 Eq.5.14의 복소켤레다. 알려진 합성 신호
\[
w[n]=e^{j\phi}y[n-d_0]
\]
에 대해 peak는 d=d0, angle r[d]=φ이다. 따라서 이 정의에서 일관된 정렬은
\[
x[n]=w[n+\hat d]e^{-j\arg r[\hat d]}.
\]
인쇄된 Eq.5.20의 n−τ를 Eq.5.17에 그대로 연결하면 비영 지연의 방향이 반대가 된다. 이를 원저자의 코드까지 검증한 것으로 확대하지 않는다. 인쇄 수식 간 일관성에 대한 확인이다.

[검증 함수](verification/verifyStitchConventions.m), [실행 결과](verification/convention_audit.json):
- base MATLAB R2026b, 합성 complex random signal, finite zero extension, delay +7/−11/0 samples.
- 수정된 일관 정의 relative L2 error: 최대 1.25×10⁻¹⁶.
- 인쇄 5.17→5.20 그대로 연결: 비영 지연 error 약 1.38/1.43.
- Eq.5.35의 정규화 W=4 예제 crossover 합 unity error: 8.88×10⁻¹⁶.
- MATLAB Code Analyzer issues 0. 이 검증은 전체 stitching, fractional delay, W=8 finite filtering, 실측 모바일 성공을 검증한 것이 아니다.

## 3. 실제 stitching 성립에 숨어 있는 조건
- Eq.5.17의 “overlap 밖은 0이므로 사전 필터 불필요”는 이상적인 band support 설명이다. 실제 필터 roll-off, DC spur, 강한 간섭, finite-window leakage를 포함하면 유효 overlap mask와 gain/phase calibration이 필요할 수 있다.
- Eq.5.35는 **같은 복소 파형**을 complementary filter로 합칠 때의 항등식이다. 각 녹음이 서로 다른 신호 상태이거나 channel response가 다르면 unity 합만으로 경계 왜곡이 없어지지 않는다.
- L-R order W=8은 저자의 실험 선택이다. fractional bandwidth, overlap, 위치, 허용 ripple에 따라 검증한다. Fig.5.7에는 overlap 밖 감쇠가 남는다는 실패 예가 있다.
- zero-phase filtering은 offline 비인과 처리다. finite block에서는 양 끝 transient를 버리고 유효한 공통 구간만 비교한다.
- one-frame 내 상관 peak 탐색과 밝은 blanking template Eq.5.21은 HDMI/DVI raster 가정이다. MIPI packet burst/command mode와 실제 panel refresh의 시간축을 별도로 확인한다.
- 상대 phase/delay가 추정돼도 절대 RF 위상이나 differential/common-mode 소스 정체가 식별되는 것은 아니다.

## 4. 결론에서 저자가 직접 남긴 미해결점
- p134: band를 차례로 붙이며 잔류 위상 오차가 누적된다. 알려진 구간을 이용한 추가 위상 최적화를 후속 과제로 제안한다.
- p134: 서로 다른 시점에 수집한 clock harmonic의 미세한 frequency 차이 때문에 unrotation으로 coherent demodulation을 얻지 못했다고 기록한다. 모바일 HSV/부호 복원에서 특히 중요한 한계다.
- p134의 공통 clock SDR rack이 정렬을 모두 제거한다는 전망은 실제 장비의 LO 초기 위상·analog path delay까지 자동 보장하는 설명으로 사용하지 않는다. 현재 UHD/WBX 자료의 retune phase 특성과 함께 검토한다.
- pp134–135: binary observation 대신 complex template, 혼합 선로 분리, device profiling 개선이 남아 있다.
- p135: smartphone의 위치 이동 문제를 미래 과제로 언급한다. 모바일 stitching 실증 결과로 읽지 않는다.

## 5. 부록이 모바일 실험에 주는 것
- Appendix A: TMDS의 8→10 bit, running disparity, line blanking reset, RGB 동시 세 채널은 이 HMM을 구성하는 구체적 규칙이다. 이것을 MIPI-DSI에 그대로 이식할 수 없다.
- Appendix B: 선명도·시간축·색별 coupling을 구분할 수 있는 시험 영상 설계가 유용하다. 비대칭 위치 표식, x/y edge, pixel-period stripe, 단색 RGB/회색, 랜덤 pattern, 글자를 독립적으로 비교한다.
- 단, TMDS 밝기 16이 clock과 동일한 주기를 만든다는 설계 이유는 MIPI에도 적용된다고 가정하지 않는다.
- 원문을 따라가더라도 최종 모바일 평가는 단일 band→동일 capture 가상 subband→순차 실측 band 순서로 분리해야 주파수 합성과 시간 비정상성을 구별할 수 있다.
