# 모바일 stitching 연구 — 원문 전체 검토와 측정 준비
2026-10-22

## 완료한 작업
**Christian David O’Connell, *Exploiting quasiperiodic electromagnetic radiation using software-defined radio* (Cambridge, September 2018), 155쪽 전체**를 세 검토 범위로 나누어 읽었다. 주요 수식·그림 36쪽은 원본 렌더로 대조했다. 참고문헌의 원문 117편까지 전부 읽은 것은 아니며, 모든 수식·256개 TMDS codeword를 독립 재유도한 것도 아니다.

[공식 원문 기록](https://www.repository.cam.ac.uk/handle/1810/290902) · DOI [10.17863/CAM.38085](https://doi.org/10.17863/CAM.38085)

| 자료 | 내용 |
|---|---|
| [1–60쪽 독해](reading_001_060.md) | RF/차동방사/IQ, raster, HSV, gradient, 원래 측정 장비·데이터셋 |
| [61–108쪽 독해](reading_061_108.md) | 탐지·cepstrum, clock acquisition/PLL, fractional resampling, complex averaging |
| [109–155쪽 독해](reading_109_155.md) | stitching 수식 대조, HMM 실험, 결론의 한계, TMDS/testcard 부록 |
| [모바일 측정안](MEASUREMENT_PLAN_KO.md) | 가상 subband 대조→A–B–A→대역 확장, 중간 그림·지표·판정 |
| [USRP/RF chain 근거](hardware_notes.md) | 120 MHz 옵션, actual Fs, streaming, LO retune, 소프트웨어 경로 |
| [기존 LG/iPhone6 목록](mobile_capture_inventory.md) | 8개 capture의 대역·길이·SHA·overlap 가능성·기존 위상 결과 |
| [capture metadata 양식](capture_metadata.template.json) | 장치/화면/LO/DDC/Fs/BW/시간/format/누락/정렬 상태 |
| [MATLAB 검증 결과](verification/convention_audit.json) | 상호상관 convention 3개 합성 사례 및 crossover unity |

## 이번 모바일 적용에서 우선할 판단
1. **방법의 후보 타당성은 충분하다.** 사용자의 넓은 sweep 내 복원 관측은 유용하다. 다음 검증 단위는 인접 RF 대역의 독립 구간에서 얻는 복소 정합이다.
2. **stitching과 DSI 소스 분리는 별도 문제다.** 강한 세로선이 overlap alignment를 지배할 수 있다. 같은 화면의 대역들을 합친 뒤, pattern 변화에 따른 내용 복원과 선 성분의 변화를 따로 평가한다.
3. **4장의 시간축 보정이 5장의 선행 조건이다.** 위치 정렬, carrier phase, 시간에 따른 CFO/rate drift를 구분한다. 저자는 p134에서 순차 기록한 harmonic의 주파수 차이로 coherent demodulation이 어려웠다고 직접 기록한다.
4. **현재 원시 파일을 임의로 한 sweep로 합칠 수 없다.** LG 두 중심 사이에는 명목 74.8 MHz gap. iPhone6 238↔308 MHz에는 10 MHz gap. 308/312 MHz는 한 대역이 다른 대역 내부에 포함되며 같은 측정 상태인지 미확인이다.
5. **새 측정은 iPhone6다.** 2026-10-22 MATLAB baseline의 Apple은 iPhone6s였으며 그 결과를 iPhone6의 위상 근거로 대체하지 않는다.

## 원문을 코드로 옮길 때 확인한 사항
- Eq.5.1은 원문에서 이미 ceil. Eq.5.7의 R는 input/output rate이며 번역의 rate multiplier와 역수 관계다.
- Eqs.5.14/5.17/5.20은 MATLAB FFT convention에서 켤레 및 lag 방향을 일관되게 정리해야 한다.
- Eq.5.23의 일반 2차 Butterworth 분자, Eq.5.27 뒤의 real-valued 설명, Eq.5.59의 error-rate 정의도 인쇄식과 구현 의미를 구분했다.
- 첫 band 예외는 pp112–113 본문에 있지만 Algorithm4에는 생략돼 있다.
- Base MATLAB R2026b로 양·음·0 지연을 시험했다. 일관된 정의의 최대 relative error 1.25e−16, zero-phase complementary response 오차 8.88e−16. 코드 정적 분석 issues 0.
- 이것은 인쇄 수식의 일관성 검증이다. 원저자 코드나 전체 모바일 stitching pipeline의 성공을 검증한 결과로 제시하지 않는다.

## 120 MHz 수신기를 이용한 시작 후보
실제 usable passband 100 MHz가 확보된다면 center step 50 MHz/overlap 50 MHz의 세 band로 200 MHz를 덮는 설계를 검토한다. 기존 중심 기준 예시는 LG 294.8/344.8/394.8 MHz, iPhone6 188/238/288 MHz다. **사용자가 확인한 실제 성공 sweep 범위와 RF 응답을 반영해 확정할 값**이다.

먼저 한 번의 넓은 수집을 software subband로 나눠 기준 파형과 비교하고, 실제 retune은 anchor를 재방문한다. 수신 폭, 저장 IQ rate, center sweep span, 합성 폭을 구별한다. 새 RF 수집·실측 stitching은 아직 실행하지 않았다.

## 재현성과 저장
- 로컬 원본: C:/Users/leechanghoon/Desktop/연구/다중모니터 복원/TMDS/Exploiting quasiperiodic electromagnetic.pdf
- SHA-256: aa81cb80e1e91e0ef928934302d222b087336edbb53af866b176181d6c1e4876
- 119,554,888 bytes / 155 pages.
- [reading_log.jsonl](reading_log.jsonl), [sources.jsonl](sources.jsonl), [claims.jsonl](claims.jsonl)는 기존 SQLite/FTS 지식 인덱스에 포함된다.
- 원문/추출문/렌더는 로컬에서 보존하고 Git에서는 제외한다. 공유하는 것은 작성한 연구 노트와 검증 코드·결과다.
- 요청된 pdf-viewer 스킬을 확인했지만 이번 세션에는 display_pdf/interact 도구가 노출되지 않았다. 로컬 PDF를 Codex 우측 패널에 여는 요청은 queued로 반환됐다. 실제 UI 렌더 완료를 확인했다고 주장하지 않는다.
