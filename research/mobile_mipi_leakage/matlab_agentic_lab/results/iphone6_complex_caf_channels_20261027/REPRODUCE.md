# 실행 순서

MATLAB R2026b. Signal Processing Toolbox의 sinc 등 사용. 원본은 read-only이며 Fs=124082800 Hz, BE int16 I/Q, I−jQ 가설이다.

1. 저장소 matlab_agentic_lab와 signal_processing을 MATLAB path에 추가한다.
2. 새 결과 폴더를 지정해 extractIphoneCaf27(out)를 실행한다. 기존 결과를 덮어쓰지 않도록 거부한다. raw 파일·reference PNG·이전 native_fold.mat/preflight.mat의 경로는 소스에 명시되어 있다. frozen_dependencies.mat에 정확히 소비한 trainingRaster/fs/f0/dc를 보존했다.
3. fitIphoneCaf27(out), validateCafText27(out), renderIphoneCaf27(out), renderCafModelResidual27(out)를 차례로 실행한다.
4. fitDsiCafFir27(out), auditIphoneCaf27(out), auditCafIqOrientation27(out), auditCafDeposition27(out)를 실행한다.
5. Python tools/build_complex_caf_gallery27.py는 기존 출력만 읽어 index.html을 만든다.

실행 직후 fitIphoneCaf27에 추가한 반대 IQ 전체 탐색 옵션은 실행하지 않았다. 실제 auditCafIqOrientation27은 선택 후보 고정 rate/delay에서만 비교한다. 초기 소스는 code_initial/, 마지막 소스와 SHA256은 code_snapshot/ 및 execution_record.json에 있다. FIR 초기 미수렴 실행은 fir_initial/, 마지막 실행은 최상위다.

MAT/FIG는 release ZIP에 보존하고 Git에는 넣지 않는다. 원본 RIS를 중복 변환하거나 바꾸지 않았다.
