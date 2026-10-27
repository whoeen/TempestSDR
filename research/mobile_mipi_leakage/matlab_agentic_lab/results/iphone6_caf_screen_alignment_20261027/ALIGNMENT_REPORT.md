# iPhone 6 100 MHz — 네 복원본 공통 화면 정렬

전력 → 복소 CAF 잔차 → 위상 기준 투영 → lag-product 위상에 **하나의 동일한 좌표 변환**을 적용했다. 기존 그림에서 좌우로 나뉘었던 문장이 이어진다. 영상별로 따로 이동시키거나 phase를 회전시키지 않았다.

[비교 갤러리](index.html) · [전체 화면 비교](montage_screen_B23.png) · [같은 문자 영역 확대](zoom_screen_B23.png)

## 정렬값

|항목|값|
|---|---:|
|학습 구간|B1만 사용|
|가로 시작점|562.0 / 1100 시간 bins|
|표시용 활성 구간 폭|894.5 bins|
|세로 시작 행|562 / 1881 — 기존 값 유지|
|좌우 방향|+1, 좌우 반전 없음|
|가로 원점 탐색 간격|0.25 bin|
|가로 폭 탐색 간격|0.5 bin|
|표시본 크기|750×1334|
|전체 시간 구간 보존본|1100×1334|

B1에서 알려진 원본 화면의 문자 패턴과 |CAF−B1 white CAF|의 변동을 사용해 전역 이동·가로 폭·방향을 추정했다. 학습 목적함수 상관은 0.13992, 전체 750열로 다시 계산한 값은 0.10899이다. 이는 좌표 선택의 지표이며 복원 정확도나 신뢰수준이 아니다. 원본 픽셀을 측정 영상에 삽입하지 않았다. 가로 폭은 **표시 정렬 가설**이며 실제 MIPI pixel clock 또는 lane bitrate를 확인한 값이 아니다.

## 두 종류의 출력

- native: 전체 1100-bin 주기를 그대로 보존한다. 정수 원점을 이동하며, 경계를 넘으면 다음 행으로 이어지는 flat-raster row carry를 적용한다. 복소 보간 없이 기존 측정 bin을 재배열했다.
- screen: 같은 원점에서 894.5-bin 구간을 750개 표시 열에 대응시킨다. 복소 CAF/lag-product를 먼저 선형 보간하고 그 뒤 크기·위상을 계산한다. wrapped phase 각도 자체를 선형 보간하지 않았다.

공통 좌표는 u=(562+r)×1100+562+894.5×(c+0.5)/750이다. 측정 bin 중심 n+0.5를 기준으로 하며 전체 1881×1100 raster의 경계에서는 주기적으로 이어진다. native의 가로 항은 562+(c+0.5)이다. 모든 네 종류·B1/B2/B3/B23에 같은 mapping을 적용했다.

B23은 B2/B3의 전력·복소 lag-product·정규화 분모를 평균한 뒤 만든 화면이다. 평균 위상각을 직접 사용하지 않았다. 이전 B1 흰 행 기준, 위상 기준, 색상 범위는 그대로 유지했다. phase는 rho<0.2인 곳을 회색으로 가렸다. phase는 lag-product 위상이며 절대 RF 위상 또는 원본 RGB 색상이 아니다.

## 파일

- screen_B23_power.png: 전력
- screen_B23_caf_residual.png: 복소 CAF 잔차의 크기
- screen_B23_phase_projection.png: 고정 위상 기준으로 투영한 CAF 잔차
- screen_B23_lag_phase.png: 복소 lag-product 위상
- native_B23_*: 1100 bins 전체 보존 버전
- B1/B2/B3도 각각 같은 이름 규칙으로 저장
- aligned_views_B23.mat: 정렬된 실제 전력·복소 CAF 잔차·투영·복소 lag-product·분모·rho
- alignment_parameters.json: 정렬 추정·대안 후보·좌표·위상 정의
- source_snapshot/: 실행 MATLAB 코드

MATLAB alignCafScreens27(새 출력 폴더)로 재현한다. 필요한 원본 complex_caf.mat 및 reconstruction_views.mat는 이전 [complex CAF 결과 묶음](https://github.com/whoeen/TempestSDR/releases/download/mobile-mipi-raw-iq-2026-10-21/iphone6_complex_caf_channels_20261027.zip)에 있다. 이전 원본과 분석 수치는 변경하지 않았다. 이번 작업은 요청한 기존 네 복원 영상의 공통 좌표 정렬이다.
