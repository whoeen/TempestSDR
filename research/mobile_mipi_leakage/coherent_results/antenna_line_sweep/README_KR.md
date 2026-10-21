# 안테나 1·2 line-period 민감도 스윕

## 결론

1880행 가정에서 유도한 line period뿐 아니라 **1098–1107 samples/line** 범위와
**1100.52**, **1105**, **1106**을 모두 4-point cubic fractional interpolation으로
검사했다. 어느 후보에서도 두 독립 프레임 묶음에 공통으로 남는 읽을 수 있는
2차원 화면 내용은 확인되지 않았다.

후보를 바꿀 때 사선의 기울기가 연속적으로 회전한다. 이는 화면 윤곽이 특정
line period에서 초점을 찾는 모습보다, 협대역 또는 주기 간섭을 raster에 펼칠 때
생기는 줄무늬와 일치한다. 줄무늬는 각 평균 영상에는 강하게 보이지만 홀수 프레임
묶음(1+3)과 짝수 프레임 묶음(2+4) 사이의 horizontal-edge correlation이 거의 0이다.
따라서 이 스윕 범위에서 `화면 복원 실패 = 1880행 line-period 선택 오류`라는
가설은 지지되지 않는다.

## 핵심 수치

| 파일 | frame period (samples) | period/1880 (samples/line) | 해당 후보 log-AM r | 해당 후보 horizontal-edge r | 스윕 내 최대 edge r |
|---|---:|---:|---:|---:|---:|
| 안테나 1 | 2,069,037.548 | 1100.551887 | -0.000438 | -0.000020 | +0.000174 at 1105 |
| 안테나 2 | 2,068,971.403 | 1100.516704 | +0.021285 | +0.001836 | +0.002182 at 1104 |

상관도는 각 후보에서 동일한 1334×750 crop을 사용해 계산했다. crop은
`frame_period/1880` 후보의 4프레임 AM 평균에서 local variance가 가장 큰 circular
window로 한 번만 정한 뒤 모든 후보에 그대로 적용했다. `r`은 독립 묶음의
`log(1+AM)` Pearson correlation이고, edge r은 열 방향 차분의 correlation이다.

## 결과 파일

- `antenna1_line_sweep_montage.png`, `antenna2_line_sweep_montage.png`: 전체 후보 AM 비교
- `antenna1_period_over_1880_halves.png`, `antenna2_period_over_1880_halves.png`: 정확한 1880행 후보의 독립 묶음 비교
- `antenna1_best_edge_halves.png`, `antenna2_best_edge_halves.png`: edge r이 가장 큰 후보의 독립 묶음 비교
- `line_sweep_metrics.csv`: 후보별 수치
- `summary.json`: 입력 형식, 가정, crop 좌표, 수치, 판정
- `antenna_line_sweep.py`: 재현 스크립트

## 해석 범위

입력은 headerless big-endian signed int16 I/Q이며 파일 내부에 sample rate, RF center,
configured bandwidth가 없다. 이번 검사는 제공된 full-file frame period를 **sample
단위로만** 사용했다. 따라서 Hz 단위 RF 해석은 포함하지 않는다.

4프레임 검사는 이 line-period 가설을 빠르게 기각하기에는 충분하지만, 미약한 화면
신호가 전혀 없음을 증명하지는 않는다. 다음 단계는 간섭 tone 제거 또는 subspace
projection 후 같은 독립 묶음 검정을 반복하고, 동기 신호를 별도로 확보해 frame
period를 다시 고정하는 것이다.
