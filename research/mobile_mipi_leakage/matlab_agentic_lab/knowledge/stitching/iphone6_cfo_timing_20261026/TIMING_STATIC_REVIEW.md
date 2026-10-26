# analyzeIphonePairTiming 정적 검토

검토일: 2026-10-26. 검토 대상: lab/analyzeIphonePairTiming.m (380 lines).

- SHA-256: ad2cc4a7dd91b8270f04031acd67eb8a886f5aa54d78f384a81c80cc4748f50e
- 읽은 의존 함수: readRisIqBlock, sampleGuardedIqFft, resamplePeriodicAm.
- MATLAB, checkcode, 수치 실행은 하지 않았다. 실행 소유자의 정적 분석 및 실제 실행 검증은 별도다.
- 다른 에이전트가 작성한 분석 코드는 수정하지 않았다.

## 확인 결과

실행을 막을 구문, CFO 부호, 중복 보정 또는 훈련·평가 혼용 문제를 수동 검토에서 찾지 못했다. 이 결론은 실행 성공이나 모델의 물리적 정확성을 증명하지 않는다.

1. **훈련과 평가:** 기본 훈련 frame 0:7, 평가 72:79. 평균 PSD, AM row-block 선택, AM lag 회귀와 적용 CFO는 훈련 데이터만 사용한다. 평가 frame에서도 tone phase slope를 측정하지만 진단 출력에만 사용하며 고정 보정값으로 환류하지 않는다. 기존에 같은 데이터의 다른 구간·사전 지식을 살펴본 이력이 있으므로 새 화면을 사용한 완전 맹검은 아니다.
2. **시간 보정 부호:** FFT(profile_current) × conj(FFT(profile_ref))의 양의 lag는 현재 신호를 앞으로 더 읽는 방향이다. fitted P=P0+slope 및 query=origin+(k+u)P−readStart는 이 규약과 맞는다. 코드에 독립적인 정수 lag 합성 검증도 있다. 실제 검증 실행은 별도다.
3. **CFO의 시간 기준:** 원본 IQ를 conjugate한 뒤의 fbb를 사용한다. exp(−j2π CFO × absolute_native_sample/Fs)를 fractional interpolation 전에 적용한다. block마다 위상을 0으로 재시작하지 않는다. 714 Hz는 후보 탐색 seed이며 별도 상수 보정으로 한 번 더 적용하지 않는다.
4. **CFO와 RF 배치의 결합:** ratio=PA/PB, δB=fB−(fcA+fA−fcB)ratio, νA=Fpilot−fcA, νB=(Fpilot−fcB)ratio로 정의한다. 각 arm의 D=(νA PusedA−νB PusedB)/Fs를 그대로 사용해야 한다. 두 보정 모두 적용한 arm에서는 D=(fcB−fcA)PA/Fs다. 예전 fcB PB/Fs−fcA PA/Fs 또는 별도 qEmp를 추가하면 시간축 항을 중복 반영한다.
5. **프레임 위상:** single frame의 B 배치는 exp(+j2πD(u+k)), 이미 pilot frame phase를 제거한 평균의 B 배치는 exp(+j2πDu)다. 둘을 바꾸면 kD 위상을 중복 적용하거나 누락한다. 파일 origin에서 생기는 고정 위상은 training alignment가 처리할 수 있으나, 평가 frame에서 다시 맞추면 안 된다.
6. **보간 범위:** 최대 |P−P0|<4, frame≤100의 허용 범위에서도 query는 주어진 2^21 raw block의 512-sample guard 안에 머문다. 보간 후 grid 길이는 원래 프레임보다 크므로 이 경로에서 downsampling alias를 새로 유발하지 않는다. 유한 guard와 FFT 주기 확장 오차는 helper의 기존 한계로 남는다.

## 출력에서 확인해야 하는 한계

- AM 반복 특징이 HS/SoT/DSI packet이라고 해독된 것은 아니다. Uniform affine 시간축 모델이며 개별 행마다 임의 보정한 결과가 아니다.
- AM 회귀에는 잔차가 있지만 slope의 신뢰구간은 없다. row-block들이 서로 상관되어 있으므로 단순히 58개 독립 관측으로 취급한 과도한 정밀도를 주장하지 않는다.
- 공통 tone 후보는 최대 3개이며 1 MHz 이상 떨어져 있어도 같은 간섭원 또는 harmonic family일 수 있다. 잔여 위상·frame별 주파수와 candidate 간 CFO MAD를 확인해야 한다.
- phase unwrap과 amplitude null이 CFO 추정에 미칠 영향은 진단 값으로 남아 있다. 위상 모델의 고정 예측이 평가 구간에서 유지되는지 확인하기 전 source clock 분리 성공으로 부르지 않는다.
- raw arm도 공통 grid로 보간한 control이다. 원래 ADC sample 배열과 동일하다는 뜻이 아니다. ordinary mean, AM mean, pilot를 기준으로 위상을 맞춘 mean이 별도로 저장된다. Pilot mean은 그 후보 tone을 강조할 수 있으므로 화면 fidelity로 해석하지 않는다.
- 회귀 intercept는 진단용으로만 저장하고 query origin에 적용하지 않는다. 따라서 출력 residual은 실제 적용한 slope-only 예측에 대한 값으로 읽는다.

## 실행 소유자의 마지막 확인

새 toolbox 환경에서 checkcode 및 실제 함수 실행, tone 후보/AM 잔차의 수치 점검, 보정별 동일 평가 구간·동일 표시 스케일, 강한 tone 제거 후 결과를 확인한다. 검토자는 MATLAB을 호출하지 않았다.

추가 검토: 작성 중 추가된 frozen_cfo_phase_trace 그림(363–378행)도 확인했다. demodulation seed에서 공통 pilot 기준으로 되돌린 위상에 고정 CFO를 한 번 빼는 식이다. 첫 chunk의 위상 0 정렬은 표시용이며 실제 데이터 보정에 반영되지 않는다.
