# SDR / RF chain 연구 노트
작성일: 2026-10-22. 이 문서는 측정 계획이며 새 수신 실험 결과가 아니다.

독립 RF chain 검토와 구체적 실험 순서는 [measurement_recipe.md](measurement_recipe.md)에 있다.
문헌·로컬 소스·유도 계산·설계 가설은 `claims.jsonl`에서 구별한다.
`tools/rf_capture_metadata_template.json`의 null은 미확인이며 0이나 false로 대체하지 않는다.
아래 로그인 상태는 초기 batch 시도의 관측 기록이다. 이후 desktop 세션의 로그인/초기화 완료 여부는 별도 확인해야 한다.

## 현재 검증 상태
- 공식 MATLAB MCP v0.15.0 바이너리와 애드온 SHA-256 검증 완료.
- MCP initialize / tools/list 통신 성공. 실제 MATLAB 계산은 MathWorks 로그인/라이선스 대기.
- MATLAB R2026b 설치 제품 목록은 MATLAB, MATLAB Copilot. 상용 DSP/Radar Toolbox 설치는 확인되지 않았다.
- 기존 TempestSDR JAR를 작업 runtime에 복사하고 공식 Temurin Java 8을 설치했다. GUI 프로세스의 창 제목 TempestSDR, Responding=true 확인.
- Windows에서 Realtek PCIe GbE 1 Gbps 링크 확인. PnP 목록에서 SDR 장치 미식별. 이것이 Ethernet SDR 부재의 증거는 아니다.
- Downloads의 USRP2940 자료/프로젝트 파일은 장비 모델의 정황 자료일 뿐 현재 연결 장비 확정 근거가 아니다.

## 수신 경로와 기록
안테나/근접장 프로브 → 필요시 preselector → 저잡음 증폭기와 감쇠기 → IQ 수신기 → 원본 저장 → MATLAB.
순서·gain·filter는 실제 강한 간섭원의 전력과 LNA 선형성을 확인한 뒤 결정한다.
LNA 뒤 감쇠기는 이미 발생한 LNA 압축을 복구하지 못한다. AGC는 AM 변조도를 바꾸므로 비교 실험은 fixed gain이 기본이다.

각 캡처에 다음을 저장한다:
device, screen-pattern-id, brightness, refresh-mode, power/charger state,
receiver model/firmware, fc_Hz, Fs_Hz, analog bandwidth_Hz, decimator/filter,
gain settings, antenna/probe/orientation/distance, reference-clock,
sample format/endian, overflow/discontinuity counters, duration, timestamp,
source SHA-256, script/git SHA, units and calibration.

현재 파일명 유래 bandwidth는 수신기 설정 메타데이터이며 측정한 ENBW가 아니다.
수신 대역폭 B와 복소 Fs는 같지 않다. LO 주변 선택 대역을 IQ로 보존하면
GHz 부근의 RF를 원래 RF 캐리어율로 저장할 필요는 없지만, 획득 대역 밖의
sideband와 누락된 위상 정보는 후처리로 복구할 수 없다.

## fc >> fm, 작은 AM/PM
분석 모델:
s(t)=A[1+m_a a(t)] exp(j[2πfc t+φ0+βp(t)]).
작은 m_a, β이고 LO가 원하는 캐리어와 정합되면
z(t)≈A exp(jφ0)[1+m_a a(t)+jβp(t)].
기준 복소 캐리어로 회전한 실수 방향은 AM, 허수 방향은 PM 민감도가 있다.
이는 유도된 좁은 대역 소신호 모델이며 DSI 방사가 이 모델에 맞는지는 검증 대상이다.

- fc가 높다는 이유만으로 복조가 불가능한 것은 아니다.
- 변조도와 잡음/클러터, LO phase noise, CFO/drift, 포화, 대역폭이 실제 제한이다.
- 강한 피크를 carrier로 선정하면 화면과 무관한 발진을 추적할 수 있다.
- carrier PLL/평균 제거의 대역폭이 fv/fh sideband를 없애지 않는지 검증한다.
- 한 샘플의 angle은 낮은 진폭에서 불안정하다. confidence mask와 기준 정의가 필요하다.
- DSI packet/burst cadence, panel refresh, lane clock은 동일한 주파수가 아니다.

## 분리 실험
1. black/white/checkerboard/moving vertical bar/constant screen 조건을 동일 gain으로 수집한다.
2. 화면 변경, brightness 변경, probe 위치 변경을 한 번에 하나씩 조절한다.
3. envelope, complex IQ, cyclic statistics의 fh/fv 후보와 반복성을 비교한다.
4. integer timing baseline → fractional timing → phase alignment 순서로 단계별 ablation을 한다.
5. coherent average와 magnitude average를 같은 raw frame 집합·scale로 비교한다.
6. reference-based cancellation / prewhitening / notch는 보존한 raw baseline 대비 평가한다.
7. low rank / sparse는 데이터 배열 방식에 종속한다. 세로선 v(x)1(y)^T는 오히려 rank 1일 수 있다.
8. RPCA의 sparse 가정, matched subspace의 독립 reference 조건을 만족하는지 먼저 확인한다.
9. frame 증가에 따라 신호와 frame-locked clutter가 함께 개선될 수 있으므로 읽기 성능·holdout pattern을 평가한다.

## TF domain
row 길이의 STFT는 row 내부 국소성에 유리하지만 60 Hz급 frame sideband를 분해하지 못한다.
긴 창은 좁은 주파수 구분에 유리하지만 row/column 위치를 섞는다.
가로 영상좌표와 직렬 RF 시간 사이에는 DSI lane striping/packet/blanking 매핑이 있다.
동일 column의 여러 row 샘플을 이어 붙인 축은 원 RF의 연속 시간이 아니다.
보고서에는 window samples, window duration, hop, NFFT, bin spacing, ENBW를 함께 기록한다.
zero-padding은 주파수 정보 해상도를 증가시키지 않는다.

## TempestSDR 입력
원본 RIS는 headerless big-endian signed int16 I,Q다.
기존 RawFile 플러그인은 int16를 host byte order로 해석한다
(TSDRPlugin_RawFile/src/TSDRPlugin_RawFile.c, int16 cast).
Windows에서 원본 RIS를 바로 int16로 열면 잘못된 값이다.
MATLAB exportRisForTempest.m로 새 little-endian 파일을 만들고 JSON sidecar를 붙인다.
GUI는 grayscale 기준 비교용이고, AM/PM/HSV 및 coherent 연구 원본은 복소 IQ로 유지한다.

## 다음 실측에 필요한 정보
사용자에게 요청한 receiver 모델/USB 또는 Ethernet/안테나/LNA 답변 대기.
현재 장비를 확인하기 전에는 firmware, IP, NIC MTU, gain을 변경하지 않는다.
