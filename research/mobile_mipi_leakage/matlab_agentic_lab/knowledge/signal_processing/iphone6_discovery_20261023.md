# iPhone 6 측정본 탐색 — 2026-10-23

이 노트는 원본 파일 및 기존 실험 기록의 읽기 전용 조사다. 새 복원과 MATLAB 수치 분석은 root 실행 담당이 별도로 진행한다. 원시 파일은 변경하지 않았다.

## 1. 기존 manifest의 iPhone 6 측정본 6개 실제 존재 확인

기준 폴더: `C:/Users/leechanghoon/Desktop/mobile/0625`. 동일 파일명과 동일 크기의 사본이 `C:/Users/leechanghoon/Downloads`에도 있다. 이번 조사에서 이 여섯 대용량 원본의 전체 SHA-256을 재계산하지 않았다. 동일 크기만으로 byte-identical 사본이라고 확정하지 않는다.

공통 설정은 외부 기록 기준 Fs=124.085710 MS/s. 헤더 없는 signed int16 big-endian I,Q 인터리브,4 bytes/complex sample. 수신 BW와 Fs는 서로 다른 값이며 raw 내부에 기록돼 있지 않다.

| ID | fc MHz | 기록 BW MHz | 실제 bytes | Fs로 계산한 길이 s | Manifest 크기 |
|---|---:|---:|---:|---:|---|
| iphone6_book34_238m | 238 | 60 | 2,613,600,000 | 5.265715 | 일치 |
| iphone6_bottom_middle_238m | 238 | 60 | 2,435,400,000 | 4.906689 | 일치 |
| iphone6_topleft_238m | 238 | 60 | 4,039,200,000 | 8.137923 | 일치 |
| iphone6_book93_238m | 238 | 60 | 3,504,600,000 | 7.060845 | 일치 |
| iphone6_response_308m | 308 | 60 | 3,623,400,000 | 7.300196 | 일치 |
| iphone6_response_312m | 312 | 49 | 5,346,000,000 | 10.770781 | 일치 |

파일명:
- `238M_60M_124.08571_topleft_iphone6_book34page_.rIs`
- `238M_60M_124.08571M_bottom middle_iphone6.rIs`
- `238M_60M_124.08571M_topleft_iphone6.rIs`
- `238M_60M_124.08571M_topmiddle_book93page_iphone6.rIs`
- `308M_60M_124.08571M_bageung hwameon_iphone6.rIs`
- `312M_49M_124.08571M_baeung.rIs`

근거: `raw_iq/RAW_IQ_RELEASE_MANIFEST.json`,`DATASETS.md`,`knowledge/stitching/mobile_capture_inventory.md`.

## 2. 기존 19개 manifest 밖의 추가 원시 캡처

- 경로: `C:/Users/leechanghoon/Desktop/연구/APMC 2026/5. 모바일/iphone6/iphone6_비밀번호화면_LCD커넥터부분_2026년03월13일11시59분08.54초.rIs`
- 실제 파일 크기: **623,739,072 bytes**
- 이번 조사에서 전체 원본 SHA-256 계산: `e4dcb3c7a958d9c9bdddfb3c6f7c9ab29ac1a5e22ce6a0e5247a4789216e08e1`
- 파일 수정 시각: 2026-03-13 11:59:16 KST. 파일명 시각 11:59:08.54와 가까우며, 수정 시각만으로 acquisition start/end를 확정하지 않는다.
- I/Q int16 가정 sample count: **155,934,768 complex samples**
- Fs25 MS/s 가정 길이: **6.23739072 s**
- 첫256 bytes를 직접 확인했으며 XML/ASCII metadata header 징후 없음. 짧은 헤더 확인만으로 전체 포맷을 완전히 입증하지 않는다.

### 설정 근거의 강도

| 항목 | 자료 | 현재 상태 |
|---|---|---|
| 기기 iPhone 6,비밀번호 화면,LCD connector 위치 | 원본 파일명,3월13일 발표자료 iPhone6 SDR 측정 사진 | 외부 acquisition label |
| fc105 MHz,Fs25 MS/s | Downloads/iphone6_reconstruct.m lines8–9,33;iphone6_reconstruct_v2_2.m lines10–11;iphone6_em_reconstruct_v2.m lines6–11 | 정확한 파일명을 참조하는 기존 코드 설정 |
| fc105 MHz,SampleRate25M/s,RX1,Continuous | ProgressReport_20260313_이창훈.pptx slide7 embedded image19 실제 LabVIEW 수집 화면 직접 확인 | 당시 실제 UI 사진과 코드가 일치;해당 파일과 start timestamp 직접 연결은 아직 없음 |
| BW20 MHz | 같은 발표자료 slide6 image18 신호수집 UI에 fc105MHz/BW20M | 다른 UI 화면이며 위 raw와 직접 연결 미확인. raw BW를20MHz로 확정하면 안 됨 |
| >i2 interleaved IQ | iphone6_reconstruct.m lines99–109,같은폴더 input_rls3.m | 코드 명시;과거 em_reconstruct.m 계열은 native-endian 오류 |
| IQ 부호 | reconstruct.m은 I−jQ,기존 lab baseline은I+jQ | 복소켤레 관계;AM은 동일,주파수/위상 부호가 반대. 보고서에 convention 명시 필요 |
| frame~59.98Hz,line~113kHz | iphone6_em_reconstruct_v2.m lines31–42 및 발표자료slide8 total1884lines | 과거 추정. 해당코드 little-endian이므로 새검증 필수 |

### 상충하며 채택하지 않은 코드 설정

Downloads/MIPI_DSI_ChannelQuant_1.m~_8.m은 같은 원본을 iPhone6s,실수 int16,Fs1GHz,fc478.205MHz로 기술한다. 기본 MIPI_DSI_ChannelQuant.m은 Fs1GHz/fc247MHz/float32 header 추정을 갖는다. 파일명·실제 LabVIEW 사진·다른 직접참조 코드와 일치하지 않는다. 코드의 ‘확정’이라는 주석을 acquisition fact로 승격하지 않는다. 105MHz/25MS/s IQ 가설로 우선 시험하되 원시 포맷 진단과 시간 반복성을 독립 확인한다.

‘pixel_clk137.5MHz’,‘Htotal1669/Vtotal1374’,‘3lane R/G/B 고정’ 등 기존 스크립트 및 발표자료의 프로토콜 추론 역시 이번 데이터 복원의 고정 사실로 사용하지 않는다. payload 시작 lane,패킷 overhead,burst 시간과 panel scan timing을 분리해야 한다.

### 빈 파일과 발견되지 않은 파일

- 같은 폴더 `2026년03월19일22시58분56.67초.rIs`는 **0bytes**로 복원 입력이 될 수 없다.
- 코드가 참조하는 `iphone6_비밀번호화면_상단엣지_2026년03월13일11시57분52.84초.rIs`는 Desktop/Downloads/Documents의 이번 rg 파일명 검색에서 발견되지 않았다. 존재하지 않는다고 단정하지 않으며 외장E: 등은 이번 탐색범위 밖이다.

## 3. 실시간 복원 기록과 오프라인 오류

`Desktop/mobile/0625/docs/experiments/2026-07-27_iphone6_background_live_settings_check.md`의 기존 기록에는 실시간 screenshot의 center311.8MHz,BW60MHz,monitor resolution124.08575MS/s,average50,filter data4/10가 있다. 당시 시험파일은308MHz/60MHz와312MHz/49MHz. 정확히 같은설정/수집시점 파일인지는 확인되지 않았다. `filter data4/10`를 단순 fourth-PSD-peak로 해석한 것은 검증되지 않은 가설이다.

기존 `tf_results/iphone6/reconstruction_p488*.png` 및 `make_iphone6_attempt.py`는 little-endian 처리 결과의 표시 계열이다. P488에서 UI가 없다는 과거 결론은 올바른 big-endian IQ 복원의 한계로 인용하면 안 된다. 기존 유효 big-endian P24는 `coherent_results/three_devices_big_endian/iphone6`에 있다.

이 조사에서 확인한 과거1880×1100 raster,fh112805.083Hz 역시 prior fit이다. 실제DSI panel total geometry라고 단정하지 않는다. 940×2200과1880×1100은같은2,068,000samples/frame의 시간열 재배열이다.

## 4. iPhone6s와 구별

- `311m_55.05487m_20m.rIs`는 기존 라벨상iPhone6s. Fs55.054870MS/s,fc311MHz,BW20MHz.
- `20260625_fs55.05487m_fc311m_25m_smallh_iphoneergentcallidisplay.rIs`는기종미확정 유지.
- Desktop/mobile/0625/iphone6.png 및 iphone6_40_largeh.png 이름만 보고iPhone6임을확정하면안된다. 실제UI표시Fs55.05465/55.05487M,fc295/311MHz이어서다른6s계열기록과혼재가능.

## 5. 읽은 원문 자료 범위

- `C:/Users/leechanghoon/Desktop/연구/ProgressReports/ProgressReport_20260313_이창훈.pptx`: 10장텍스트전체;slide6,7,8 embedded관련사진/그래프직접확인.
- `C:/Users/leechanghoon/Desktop/연구/ProgressReports/ProgressReport_20260320_이창훈.pptx`:6장텍스트확인,새raw연결정보없음.
- `C:/Users/leechanghoon/Downloads/iphone6_dphy_analysis.pptx`:9장텍스트확인,프로토콜추론자료이며rawacquisition metadata로사용하지않음.
- 위파일을수정하거나외부업로드하지않았다. 이미지추출은임시경로에서읽기검증용으로만수행했다.

실제 LabVIEW 설정 확대: [slide7 acquisition controls](iphone6_discovery_assets/labview_20260313_slide7_controls.png). 파일 목록과 metadata 상태는 [JSON](iphone6_discovery_20261023.json)에 저장했다.
