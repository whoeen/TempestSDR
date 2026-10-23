# iPhone 6 / iPhone 6s 측정 IQ 재복원 — 2026-10-23

## 실제 실행 결과

MATLAB R2026b에서 원시 RIS를 다시 읽어 처리했다. 기존 iPhone 6 파일 6개에서는 키패드 또는 홈 화면의 구조가 보이며, iPhone 6s는 숫자·일부 작은 문자까지 식별된다. 새로 발견한 105 MHz iPhone 6 파일에서는 반복 줄무늬가 우세하고 비밀번호 화면은 아직 확인하지 못했다. 이 보고서는 '실제 측정 신호에서 UI 구조가 보임'을 기록하며 완전한 원본 RGB 복원이나 정답 영상 기반 정확도를 주장하지 않는다.

[전체 갤러리와 프레임 누적 비교](index.html) · [원본 파일 및 측정조건 근거](raw_provenance.json) · [코드 해시](code_provenance.json)

## 1. 찾은 파일과 측정 조건

| 구분 | 파일 식별 | 중심주파수 MHz | 저장 복소 IQ MS/s | 명목 수신 BW MHz | 현재 영상 |
|---|---|---:|---:|---:|---|
| iPhone 6s | 311m_55.05487m_20m | 311 | 55.054870 | 20 | 키패드 숫자·문자 확인, P32 |
| iPhone 6 | book34_238 | 238 | 124.085710 | 60 | 키패드 구조, P8 |
| iPhone 6 | bottom_middle_238 | 238 | 124.085710 | 60 | 키패드, P8/P16/P32 |
| iPhone 6 | topleft_238 | 238 | 124.085710 | 60 | 키패드 숫자·윤곽, P8 |
| iPhone 6 | book93_238 | 238 | 124.085710 | 60 | 키패드 구조, P8 |
| iPhone 6 | response_308 | 308 | 124.085710 | 60 | 홈 화면 아이콘, P8/P16/P32 |
| iPhone 6 | response_312 | 312 | 124.085710 | 49 | 홈 화면 아이콘, P8 |
| iPhone 6 / 3월 13일 | 비밀번호화면_LCD커넥터부분 | 105 | 25 | 미확정 | 반복 줄무늬, 화면 미확인 |

기존 측정본은 Desktop/mobile/0625에서 확인했다. 추가 105 MHz 파일은 Desktop/연구/APMC 2026/5. 모바일/iphone6에서 찾았다. 합계 iPhone 6 7개 + iPhone 6s 1개, 원본 23,255,139,072 bytes다. 0-byte 파일은 복원 대상으로 포함하지 않았다.

기존 파일의 Fs/fc/BW는 파일명 및 기존 manifest의 외부 메타데이터다. 새 파일의 25 MS/s와 105 MHz는 정확한 파일 경로를 참조하는 기존 코드와 같은 날짜 LabVIEW 측정 화면을 대조한 조건이며, RIS 헤더에서 읽은 값이 아니다. 별도 사진의 BW 20 MHz는 동일 측정임이 확정되지 않아 채택하지 않았다. 파일명에 book이 있어도 실제 추출 화면은 키패드로 보이므로 파일명만으로 표시 패턴을 단정하지 않았다.

## 2. 이번 처리와 과거 실패의 차이

입력은 headerless **big-endian signed int16, interleaved I/Q**, 복소 샘플당 4 bytes로 읽었다. 복소 표현은 I+jQ다. 과거 P488 등 일부 결과는 little-endian 해석을 사용했으므로 해당 실패를 이 데이터의 복원 한계로 사용할 수 없다. 이전 스크립트의 I-jQ와는 위상 부호가 반대가 되지만 진폭은 동일하다.

처리 순서:

1. 입력 경로·크기·포맷·메타데이터를 확인하고 각 사용 raw block의 SHA-256을 기록.
2. 행/프레임 시간에 맞춰 복소 IQ를 Catmull–Rom cubic으로 fractional sampling. 가장 가까운 샘플 방식도 대조군으로 저장.
3. 행 평균 진폭 프로파일로 프레임 수평 지연을 정렬.
4. AM 평균, 위상 무보정 복소 평균, global phase 보정 평균, 행에 따른 선형 위상 보정 평균을 각각 계산.
5. 1/4/8 또는 1/8/16/32/64 프레임의 중간 영상과 수치 저장.
6. 최종 표시용 cyclic 재배치·대비 조정 및 열 평균 제거 대조군, 상대 위상 HSV 출력.

MATLAB의 pwelch/resample/stft가 현재 설치에서 확인되지 않아 기존에 검증된 base MATLAB PSD/보간 구현을 사용했다. 이번 실행은 STFT/DSI bit decoder 실행을 의미하지 않는다. 저장 프레임은 원시 파일의 실제 위치에서 읽었고 파일 반복 재생을 누적 프레임으로 세지 않았다.

## 3. 누적 프레임 수에 따른 변화

아래 값은 **AM 홀수/짝수 프레임 평균의 상관**이며 SNR·원본 영상 일치도·복원율이 아니다.

| 측정 | P8 | P16 | P32 | P64 |
|---|---:|---:|---:|---:|
| iPhone 6s / 311 MHz | 0.8992 | 0.9428 | 0.9676 | — |
| iPhone 6 / bottom-middle 238 MHz | 0.6267 | 0.7688 | 0.8581 | — |
| iPhone 6 / home 308 MHz | 0.6743 | 0.8101 | 0.8879 | — |
| iPhone 6 / password 105 MHz, 최초 timing | 0.9648 | 0.9745 | 0.9774 | 0.9792 |

6s의 UI는 잘 유지된다. 기존 iPhone 6 P32에서는 잡음이 줄어드는 동시에 일부 숫자·윤곽이 수평으로 번지거나 이중으로 보인다. 따라서 P8도 함께 보존하고, 상관 상승만으로 P32가 항상 더 좋은 영상이라고 판단하지 않는다. 홀짝 결과도 같은 timing/reference를 공유하므로 완전히 독립된 정답 검증이 아니다.

105 MHz의 높은 상관은 영상 식별 성공을 뜻하지 않는다. 반복되는 간섭도 이 통계량을 높인다. 최초 P64에서는 frame56–64의 수평 정렬값이 +24열 탐색 상한에 도달했다. 이는 잔여 드리프트가 있다는 구체적 증거이며 별도의 timing 보정 대조 실험 대상으로 삼았다.

## 4. 행/프레임 시간과 샘플 수

| 측정 | samples/행 | samples/프레임 | 출력 열수 | samples/출력 열 |
|---|---:|---:|---:|---:|
| 기존 iPhone 6 | 1100.001052 | 2068001.978244 | 1100 | 1.000000957 |
| iPhone 6s | 488.884548 | 917636.666798 | 750 | 0.651846064 |
| 새 iPhone 6 105 MHz / 최초 추정 | 221.622758 | 416871.953206 | 1100 | 0.201475235 |

기존 6개 iPhone 6 파일에는 동일한 prior timing(fH=112805.083 Hz, 1880행)을 사용했다. 개별 파일의 물리적 DSI timing을 새로 측정한 결과가 아니다. 6s도 기존 별도 설정을 사용했다.

새 파일은 최초 2^23 복소 샘플(25 MS/s 가정에서 약0.3355초)의 진폭 자기상관으로 추정했다. fH 후보112804.2996 Hz, fV 후보59.97045 Hz이며 프레임/행 비는1880.99795다. 1880/1881/1884행을 비교했을 때1881행 조건에서 반복성이 가장 높았다. 단, 반복 신호가 패널·DSI·다른 간섭 중 어디에서 나온 것인지는 이 결과로 확정되지 않는다.

**samples/출력 열은 samples/실제 표시 픽셀과 다르다.** 새 파일은 약222개의 획득 샘플/행을1100열로 보간하여 표시한다. 보간은 새 RF 대역폭이나 독립 해상도를 만들지 않는다. Fs나 수신 fc에서 DSI byte rate, DDR clock, lane bit rate를 바로 계산할 수 없다.

## 5. 위상·세로선 해석

최종 HSV는 global-phase 보정 복소 평균의 상대 위상을 Hue, |global 평균|/AM을 Saturation, AM 표시값을 Value로 사용했다. 위상 기준은 선택 영역 복소 합의 angle이며 각 결과의 phase_reference_rad에 기록했다. 진폭 하위15% 또는 일관성0.2 미만은 채도를 제거했다. 이 마스크가 위상 신뢰도의 정답 보장은 아니다.

frame_progression.csv의 mean_coherent_over_incoherent 및 presentation_summary의 coherent_over_am은 **row-phase-fit 결과**의 비율이다. HSV에 사용한 global 평균의 지표와 혼동하면 안 된다.

세로선은 최종 결과에서도 남는다. 현재 위상은 수신된 혼합 신호의 위상이며 이 선을 LCD column driver로 확정할 수 없다. 열 평균 제거는 반복 세로 성분을 줄이는 표시 대조군이고 실제 UI의 세로 구조도 제거할 수 있다. RPCA/특정 subspace로 방사원을 분리했다는 주장은 이번 결과에 포함하지 않는다.

## 6. 그림을 읽는 방법

갤러리의 최종 AM/column-removal/HSV는 각 패널별1–99% 범위 대비를 사용한다. 반면 각 실행 폴더의 Pxxx_comparison.png는 첫 프레임에서 고정한 진폭 범위를 공유한다. 누적 변화의 공정한 비교는 이 고정 범위 그림을 함께 본다.

처음 presentation/의750열 자동 crop은 일부 iPhone 6 키패드 오른쪽을 잘랐다. 이를 발견해 presentation_v2/에서는 **1100열 전체를 보존**했다. iPhone 6s의 기존750열 crop은 유지했다.1334행 선택 및 cyclic 시작 위치는 표시 가정이며 원본 전체 raster도 보존되어 있다.

## 7. 재현과 로그

- surveyIphoneArchive.m: 기존6개 파일 P8 조사.
- inspectIphonePasswordCapture.m: 새 파일 자기상관·PSD 진단.
- previewIphonePasswordTiming.m: 1880/1881/1884행 대조.
- extendIphoneRecovery.m: 선택 기존2개와6s P32, 새파일P64.
- finalizeIphoneRecovery.m: 표시용 추출, 열 제거 대조군, 위상 HSV.
- tools/build_iphone_recovery_gallery.py: 결과를 HTML로 모음. IQ 신호연산 없음.

원시 파일을 덮어쓰지 않았다. 첫 P32 시도는 JSON 배열 방향 때문에 계산 시작 전에 실패했고 failed_run.json에 남겼다. 활성 행/열 segment를 명시한 _v2 폴더에서 재실행했다. MATLAB 원시 배열(.mat)은 로컬에 남겨두며, Git에는 코드·해시·CSV·선택된 PNG·보고서를 보관한다.

## 8. 105 MHz 시간 정렬 보정 대조 실험

refineIphonePasswordTiming.m을 실제 실행했다. 최초 실행의 frame2–48에서 수평 이동량의 기울기를 추정해 프레임 주기를416871.953206 → **416871.866419 samples/frame**으로 바꾸었다(−0.086787 sample/frame). 행 주기는 유지했고 정렬 탐색 범위는±24 → ±96열로 확대했다.

주기 회귀에 쓰지 않은 frame49–64에서 정렬값 범위는 기존21.07~24열(9프레임 상한 포화)에서 **0.057~0.595열(포화0)**로 바뀌었다. 이 구간의 평균 프로파일 상관은0.982007 → **0.999062**다. 따라서 이 프로파일에 대한 잔여 drift는 실질적으로 줄었다.

그러나 P64 화면은 여전히 세로선·물결무늬가 우세하고 비밀번호 키패드를 식별할 수 없다. AM 홀짝 상관도0.979189로, 정렬 개선이 곧 화면 분리 성공은 아님을 보여준다. 현재 결론은 **이 시간 정렬과 AM/global/row-phase 평균 처리로는 새105 MHz 파일의 화면 복원에 성공하지 못했다**는 것이다. 다른 대역·신호원 분리까지 불가능하다는 결론은 아니다.

이 대조에서 프레임 주기와 탐색 범위를 함께 바꾸었으므로 두 효과를 완전히 분리한 실험은 아니다. 새 frame49–64도 동일 frame1 프로파일에 정렬되므로 완전 독립 영상 검증은 아니다.

[보정 수치와 설정](password_105_P064_refined/refinement.json) · [보정 후 영상](presentation_refined/password_105_P064_refined_comparison.png)

## 9. 클라우드 원시 데이터 동기화

새105 MHz RIS(623,739,072 bytes)를 기존 whoeen/TempestSDR 데이터 릴리스에 추가했다. GitHub가 반환한 SHA-256과 크기가 로컬 원본과 일치한다. GitHub asset 이름은 업로드 과정에서 영문·기호로 정규화되었으며 manifest가 원본 한국어 파일명과 매핑한다.

[원시 RIS 다운로드](https://github.com/whoeen/TempestSDR/releases/download/mobile-mipi-raw-iq-2026-10-21/iphone6_._LCD._2026.03.13.11.59.08.54.rIs) · [업로드 검증 기록](cloud_raw_upload.json) · [20개 데이터셋 최신 manifest](RAW_IQ_RELEASE_MANIFEST_20261023.json)
