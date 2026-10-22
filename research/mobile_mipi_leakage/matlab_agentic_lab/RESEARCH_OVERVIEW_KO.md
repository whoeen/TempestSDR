# 스마트폰 누설신호 연구실 구축 현황
2026-10-22 · 첫 구축/문헌 조사 사이클

## 지금 된 것과 아직 안 된 것

| 항목 | 상태 |
|---|---|
| 역할별 에이전트 | MIPI/D-PHY, TEMPEST, RF 신호처리, SDR/RF chain 분리 |
| 연구 기록 | 출처·페이지·주장·가정·실패·실험 로그 JSONL, 검색용 SQLite |
| MATLAB MCP | 공식 v0.15.0 설치 파일 검증, Codex 등록, 5개 도구 목록 실통신 확인 |
| MATLAB 스킬 | 핵심/신호처리/레이더/무선/시험·차트 37개 등록 |
| MATLAB 실행 | 첫 batch는 로그인 창 이후 종료1; desktop와 공식 애드온 setup 준비. 인증 및 수치 실행 검증 대기 |
| Toolbox | 로컬 설치 목록: MATLAB, MATLAB Copilot. 추가 Toolbox 가용성 미확인 |
| TempestSDR | Java 준비, GUI 창 생성·응답 확인 |
| 실제 RF 수신 | 장비 모델/연결/안테나·LNA 정보 미확인. 새 측정 없음 |
| 새 MATLAB 복원 결과 | 아직 없음. 코드 작성·정적 검사는 수치 결과와 구분 |

기존 원본은 [GitHub raw IQ 릴리스](https://github.com/whoeen/TempestSDR/releases/tag/mobile-mipi-raw-iq-2026-10-21)에 유지되어 있다.
이 폴더는 기존 실험을 MATLAB으로 옮겨 재검증하기 위한 코드와 지식 저장소다.

## fc가 fm보다 훨씬 높을 때

핵심은 GHz carrier 자체를 이미지로 바로 reshape하는 것이 아니라,
수신기에서 선택한 대역의 **복소 IQ를 보존하고 정합하는 것**이다.

```text
RF → 선택 대역 IQ → 진단/대역 선택 → 복소 DDC → 시간·주파수·위상 정합
   → AM / 상대 PM → frame 평균 → 간섭 분리 가설 비교 → 영상내용 검증
```

작은 변조도 모델을
s(t)=A[1+m_a a(t)] exp(j[2πfc t+φ0+βp(t)])
로 두면, 정합된 기준으로 회전한 기저대역은 근사적으로
A[1+m_a a(t)+jβp(t)]이다.

- AM과 PM 정보가 서로 다른 복소 방향에 나타날 수 있다.
- m_a=0.01 또는 β=0.01 rad이면 단일 정현파 변조의 각 1차 sideband는 약 −46 dBc다. 이는 수식 예시이며 수집 신호의 측정 변조도가 아니다.
- LO phase noise, drift, 강한 clutter, clipping, 수신 필터가 약한 sideband를 가릴 수 있다.
- fh/fv가 낮다는 사실은 영상정보의 최대 변조대역이 낮다는 뜻이 아니다.
- 공통모드 방사라는 물리적 기원과 low-rank라는 행렬 성질은 별개다.
- 1×c(x)의 반복 세로선은 rank 1일 수 있다. RPCA의 L을 곧바로 DSI로 이름 붙이지 않는다.

## Galaxy A7 (2018) 예

| 항목 | 값과 근거 수준 |
|---|---|
| 패널 | 삼성 확인: 1080×2220 Super AMOLED |
| 전송 | 공개 커널 설정: command mode, 4 lane, RGB24, refresh 설정60 Hz |
| lane bit rate | PMS3/230/1·이상적인26 MHz 기준으로 996.666667 Mb/s/lane |
| forwarded DDR clock | 위 가정에서 498.333333 MHz |
| active pixel rate | full-frame60 Hz 가정에서143.856 Mpixel/s |
| RGB888 payload | 같은 가정에서3.452544 Gbit/s total; protocol overhead 제외 |

이 값은 실제 A7 수신 IQ에서 얻은 측정값이 아니다. Command mode에서는
host update와 패널 scan cadence를 구분해야 한다.
LG X2/iPhone6s/S4의 timing을 이 표로 대체하지 않는다.

출처: [삼성 A7 발표](https://news.samsung.com/global/widen-your-world-with-the-galaxy-a7),
[고정 commit의 패널 설정](https://github.com/prashantpaddune/android_kernel_samsung_a7y18lte/blob/97e4fbcdb31efe88b91cd321dae7bbaece36c51a/arch/arm64/boot/dts/exynos/display-lcd_a7y18_common.dtsi).
세부 행·수식·예외는 knowledge/mipi_dphy/notes.md 참조.

## 원·그라데이션·세로선 해석

1. 원형 UI를 따라가는 contour는 데이터 값에 따른 방사/대역제한의 비선형·비단조 mapping일 수 있다.
2. 전체에 일정한 hue ramp/banding이 생기면 CFO 및 fractional timing 잔차도 후보이다.
3. 같은 x에 고정된 선은 frame 동기 간섭, 패킷/blanking 구조, driver 방사 모두 후보이다.
4. 화면 패턴·밝기·수신 위치를 각각 바꾸고 AM·복소위상·주기를 함께 비교해야 원인을 구별할 수 있다.
5. HSV의 H는 RF 위상 표기이며 실제 디스플레이 색상 복원이라고 볼 수 없다.

EM Eye는 **카메라 CSI** 연구이므로 DSI 실증으로 인용하지 않는다.
Erdeljan–Kuhn2024의 banding 모델도 HDMI timing에 기반하므로
DSI에 적용할 때 별도 검증이 필요하다.
현재 그림만으로 LCD column driver를 확정하지 않는다.

## 첫 MATLAB 실행

MATLAB에서 로그인/라이선스 선택을 완료한 뒤:
```matlab
run("C:/Users/leechanghoon/Documents/Codex/2026-09-21/snr-svd/tempestsdr-cloud/research/mobile_mipi_leakage/matlab_agentic_lab/startLab.m")
addpath(fullfile(pwd,"signal_processing"));
results = runtests("signal_processing/testMobileBaseline.m");
assert(all([results.Passed]),"Resolve numerical tests first.");
summary = runMobileBaseline();
```

결과는 새 시간별 폴더에 단계별 PNG/CSV/JSONL/MAT으로 저장한다.
원본 대조, 공통 scale, P1/P4/P8, nearest/fractional,
coherent/no-phase/global-phase/row-phase 및 상대위상을 함께 남긴다.
수치 검증 전에는 새 복원 성능을 주장하지 않는다.

## 상세 노트
- knowledge/mipi_dphy/notes.md
- knowledge/tempest/notes.md
- knowledge/signal_processing/RESEARCH_NOTES_KR.md
- knowledge/rf_chain/notes.md
- signal_processing/README.md
