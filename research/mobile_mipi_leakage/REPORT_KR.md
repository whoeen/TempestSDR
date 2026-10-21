# 3기종 RPCA / matched subspace 실험

> **2026-09-23 정정:** 이 문서의 Python 실험은 `.rIs`를 little-endian으로 읽었다. 실험실 `RIS2IQ.m`이 규정하는 실제 형식은 **big-endian signed int16 I/Q**이므로, 아래 영상과 RPCA·matched-subspace 수치는 물리 해석에 사용하면 안 된다. 정정 재분석은 [LAB_MEETING_COHERENT_HSV_KR.md](LAB_MEETING_COHERENT_HSV_KR.md)와 [새 결과 갤러리](coherent_results/index.html)를 기준으로 한다.

실행일: 2026-09-21. LG X2(2019), Galaxy S4 LTE, iPhone 6s. 원본 .rIs는 읽기 전용으로 사용했다.

## 관찰 결과

이번에 적용한 공간 RPCA와 데이터에서 학습한 spatial matched subspace는 화면 의존 공통모드 방사만 선택적으로 분리하지 못했다. LG X2에서 고정 세로선은 대부분 남고 키패드/글자가 약해졌다. iPhone에서는 큰 버튼은 남지만 작은 글자와 경계가 손실됐다. 이는 이 데이터와 아래 가정에서 얻은 결과이며, 알려진 순수 공통모드 기준 신호를 사용하는 matched subspace 전체의 실패를 뜻하지 않는다.

Temporal matched는 반복되는 정적 화면에 대한 응답을 1로 고정하므로 세부 내용을 더 보존하지만, 같은 방식으로 반복되는 세로선도 통과시킨다. 간섭의 물리적 발생원이 column driver라는 가설이나 추출 성분이 DSI common-mode라는 사실을 이 영상만으로 입증하지 않았다.

## 주요 지표

세로선 지표 = column 평균에서 61-column 이동평균을 뺀 값의 RMS. 감소율은 nuisance-only 제거율이 아니다. 화면의 세로 구조도 포함할 수 있다. 음수는 증가다.

| 기종 | 방법 | rank | 세로선 RMS 감소 | 독립 raw 기준 MSE 감소 |
|---|---|---:|---:|---:|
| LG X2 (2019) | rpca_lambda1 | 12 | 5.44% | 47.34% |
| LG X2 (2019) | matched_r2 | 2 | 2.14% | 47.84% |
| LG X2 (2019) | temporal_matched_rank1 | 1 | 6.10% | -0.18% |
| Galaxy S4 LTE (171.5 MHz) | rpca_lambda1 | 35 | 11.19% | 48.25% |
| Galaxy S4 LTE (171.5 MHz) | matched_r2 | 2 | 0.90% | 48.50% |
| Galaxy S4 LTE (171.5 MHz) | temporal_matched_rank1 | 1 | 2.48% | 0.23% |
| iPhone 6s | rpca_lambda1 | 60 | 5.03% | 20.90% |
| iPhone 6s | matched_r25 | 25 | 0.40% | 48.59% |
| iPhone 6s | temporal_matched_rank1 | 1 | 0.54% | 1.82% |

Raw 기준 MSE 감소는 잡음 평활화 또는 반복 간섭 보존만으로도 좋아질 수 있다. 실제 화면 ground truth가 없으므로 SNR 개선, 해상도 개선, 문자 복원 성공으로 해석하지 않는다. y-edge 상관도 원본의 잡음을 포함하므로 단독으로 화면 보존율로 해석하지 않는다.

## 입력과 정렬

각 측정본의 첫 40 frame. 기존 복원 코드의 line/frame period와 circular crop을 사용하고, complex IQ DC 제거 → complex 선형보간 raster → content-profile 수평 정렬 → AM → 프레임 median으로 정규화 → log-AM 순서로 처리했다. 수치 분석은 native raster, PNG montage만 축소한다. Median filtering, TV, 생성형 복원은 사용하지 않았다.

Galaxy 111.9 MHz는 기존 3기종 benchmark에 있던 측정본으로 별도 대조 결과도 보존했다. 기록에 키패드가 더 잘 보이는 것으로 명시된 171.5 MHz 측정본을 주 비교 대상으로 추가했다. 171.5 MHz는 기존 timing/crop을 사용하되 이 실험에서 수평 profile registration을 다시 추정했다. 과거 MATLAB offset trace를 그대로 복사한 결과는 아니다.

- Galaxy S4 LTE (111.9 MHz): `data/111.9mhz_20m_110.89105m_galaxyS4lte_rightmiddle.rIs`, active [1920, 959], fs=1.10891e+08 Hz, fH=116153.241090 Hz.
- Galaxy S4 LTE (171.5 MHz): `data/171.5mhz_20m_55.81679m_galaxS4lte.rIs`, active [1912, 923], fs=5.58168e+07 Hz, fH=116153.425400 Hz.
- iPhone 6s: `data/311m_55.05487m_20m.rIs`, active [1334, 750], fs=5.50549e+07 Hz, fH=112613.234000 Hz.
- LG X2 (2019): `data/LGX22019_344.8M_60M_136.56551M.rIs`, active [1440, 720], fs=1.36566e+08 Hz, fH=88679.652541 Hz.

## RPCA: penalized stable PCP

$$Y=L+S+N,\qquad \min_{L,S}\frac12\|Y-L-S\|_F^2+\tau\|L\|_*+\tau\lambda\|S\|_1.$$

행렬은 H×W 평균 log-AM 이미지다. 전체 scalar mean만 분리했다가 복원한다. tau = sigma_mean (sqrt(H)+sqrt(W)), lambda = multiplier / sqrt(max(H,W)); multiplier=0.5, 1, 2를 모두 저장하고 기본값은 사전 지정한 1이다. sigma_mean은 별개 frame half 평균의 차/2에 대한 MAD 추정이다. 간섭이 유색이고 frame 상관이 있을 수 있으므로 이 tau는 실용적 규제 강도이며 최적 잡음 경계 보장이 아니다.

각 반복에서 full exact SVD thresholding과 entrywise soft thresholding을 교대한다. 최대 160회, 상대 변화 2e-5까지 실행하며 수렴 여부·목적함수·fixed-point 오차를 저장했다. High rank만으로 sparse 성분 가정이 충족되지 않는다.

## Spatial matched subspace

$$\widehat y=H(H^T R^{-1}H)^{-1}H^T R^{-1}y.$$

각 raster row를 W차원 관측으로 본다. H는 학습 20 frame 평균의 RPCA(lambda=1) 결과에서 학습한 right singular vector다. R은 학습 frame의 평균을 뺀 temporal residual에서 추정하고 10% diagonal loading한다. 따라서 R은 시간 변화 간섭을 모델링하며 고정 세로선은 제거되지 않는다. 이 H는 검증된 common-mode 기준 패턴이 아닌 데이터 유래 후보 공간이다.

학습: 1,3,...,39번. 검증: 2,6,...,38번. 시험: 4,8,...,40번. 검증 10장을 다시 5+5장으로 나눠 ranks={2,4,8,16,32,64} 중 학습 RPCA rank 이하에서 raw-reference MSE를 최소화한다. 시험 frame은 rank 선택에 사용하지 않는다. 추가 unweighted subspace control도 저장했다.

시험 지표는 검증 10장에 적용한 결과와 처리하지 않은 시험 10장 평균 사이의 MSE/SSIM이다. 동일한 저랭크 필터를 양쪽에 적용해서 생기는 인위적인 repeatability 상승을 피했다. 전체 40장 출력은 시각화·최종 후보용이며 독립 시험 추정치로 취급하지 않는다.

## Temporal matched subspace

$$x_p=a s_p+n_p,\quad a=\mathbf 1,\quad w=R^{-1}a/(a^T R^{-1}a),\quad \widehat s_p=w^Tx_p.$$

Frame×pixel 행렬에서 반복되는 화면 성분의 temporal signature a=ones를 명시했다. 시간 방향 rank=1은 이미지의 공간 rank=1을 뜻하지 않는다. 전체 공분산을 픽셀 [::4,::4]에서 추정하고 10% diagonal loading했다. 이상적으로 신호의 aa^T 항은 unity-response 제약 아래 가중치에 영향을 주지 않는다. 유한 표본에서는 신호-잡음 교차항 영향이 남는다. 공분산 추정 격자를 제외한 픽셀의 raw-reference MSE도 별도로 기록했다.

동일한 정적 간섭 역시 a=ones이므로 보존된다. 별도의 interference-only 측정이나 source-specific signature 없이는 화면과 구별할 수 없다.

## 랭크 해석

이전 LG X2의 effective rank 108.64는 frame 평균을 제거한 (frame·row)×candidate-column 행렬 값이었다. 이번 H×W 평균 이미지의 rank와 직접 비교할 수 없다. 고정 세로 무늬 b(x)가 모든 row에 같다면 I=1_H b^T이므로 세로선 개수와 상관없이 spatial rank=1이다. 그런 세로선은 low-rank L에 들어갈 수 있다. 또한 일정 화면과 고정 간섭은 frame×pixel 표현에서 모두 시간 방향 rank=1이다.

AM/log-AM은 비선형 변환이다. IQ에서 z=s+i인 경우 abs(z) 또는 log(abs(z))는 두 물리 신호의 합으로 분해되지 않는다. 이 실험의 L/S는 통계적 영상 성분이며 독립된 물리 방사 전류가 아니다.

## 다음 측정에 필요한 구별 정보

동일 수신 설정에서 알려진 테스트 패턴을 바꾼 측정, 신호원이 분리된 probe/reference 채널, 또는 DSI lane/packet 관련 기준 주기와 위상 정보를 확보하면 H를 화면 관련 성분으로 정의할 근거가 생긴다. 화면 off는 clock/driver 동작까지 바꿀 수 있어 자동으로 동일 간섭 기준이 되지 않는다. 실제 common-mode 전류의 전기적 확인도 별도 측정이 필요하다.

## 재현과 검증

`run_separation.py --selftest` 후 `run_separation.py --device all`, 이어서 `temporal_and_report.py`를 실행한다. NumPy/Pillow만 필요하다. 원본 capture 경로와 parameter는 코드에 명시돼 있다. results/provenance.json, acquisition.json, split.json으로 입력·구현·평가 구분을 추적한다.

합성 저랭크+sparse+Gaussian 데이터의 RPCA truth 상대오차는 results/numerical_selftest.json에 기록됐다. Matched estimator의 subspace unity-response와 covariance-weighted noise variance도 수치 검증했다. 실측 모든 RPCA의 수렴 상태는 각 summary.json에 있다.

- [Stable Principal Component Pursuit](https://arxiv.org/abs/1001.2363)
- [Matched Subspace Detectors](https://www.mssc.mu.edu/~daniel/mscs6960/spring2010/ScharfFriedlanderTSP94.pdf)

## 결과 파일

results/index.html: 기종별 모든 비교 이미지. 각 폴더의 components.npz: baseline, RPCA L/S/N, 공간 matched 결과와 H/R/weights. temporal_matched_rank1.npy: 시간 matched 결과. metrics.csv와 각 convergence.csv: 수치 지표. logam_frames.npy: 정렬 40-frame cache.
