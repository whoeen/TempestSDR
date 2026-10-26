# Signal Processing / Wavelet Toolbox 설치 감사

작성: 2026-10-26. 읽기 전용 점검이다. 이 에이전트는 설치 프로그램, MATLAB, mpm install을 실행하지 않았고 기존 설정·제품·script를 변경하지 않았다. 설치/실행 소유자는 root 에이전트다.

## 1. 현재 설치와 실제 경로

| 항목 | 확인값 |
|---|---|
| 기존 MATLAB root | C:/Program Files/MATLAB/R2026b |
| 현재 prodcontents | C:/Program Files/MATLAB/R2026b/appdata/prodcontents.json |
| 초기 점검의 제품 keys | MATLAB 26.2 win64; MATLAB Copilot 26.2 win64 |
| Signal Processing / Wavelet | 설치 시작 전 제품 목록에서 둘 다 없음 |
| mpm executable | C:/Users/leechanghoon/Downloads/mpm.exe |
| mpm 파일 | 84,762,976 bytes; 수정 UTC 2026-10-23T09:39:03.682Z |
| 설치 GUI launcher | C:/Users/leechanghoon/Downloads/matlab_R2026b_Windows.exe |
| 이미 풀린 GUI installer | C:/Users/leechanghoon/Downloads/_temp_matlab_R2026b_Windows/setup.exe |
| Agentic Toolkit 실제 root | C:/Users/leechanghoon/Downloads/matlab-agentic-toolkit-main/matlab-agentic-toolkit-main |
| 설치 skill | C:/Users/leechanghoon/.agents/skills/matlab-install-products/SKILL.md |

초기 점검에서는 mpm의 실행 version/signature와 toolbox 사용권을 새로 검사하지 않았다. 이후 설치 소유자가 시작한 로그에서 MPM 2026.8이 확인됐으며, 아래 진행 상황에 기록했다. mpm 파일 존재는 제품 설치 성공이 아니다. Oct22 inventory의 MATLAB 실행 version은26.2.0.3386108이었다. C:/Program Files/MATLAB/R2025a 폴더도 남아 있지만 이번 대상은 확인된R2026b다.

Toolkit의 Configuration_and_Troubleshooting.md는 skills와 MATLAB 제품 설치를 구분한다. Signal-processing skill 등록과 MCP 작동이 Signal Processing Toolbox/Wavelet Toolbox 설치를 대신하지 않는다. 기존 environment/SETUP_STATUS.json에는37개 skill,공식 MCP v0.15.0,수치 실행 성공이 기록돼 있다.

## 2. 지난 실패는 어디였나

기존 작업 폴더:

C:/Users/leechanghoon/Documents/Codex/2026-09-21/snr-svd/tempestsdr-cloud/research/mobile_mipi_leakage/matlab_agentic_lab/results/iphone6_stitch_20261023/cache/mpm-20261023

그 안에는 mpm_download.ps1,mpm_prepare_input.ps1,mpm_install.ps1 세 파일만 있다. 예정된 mpm_input_r2026b.txt는 없다.

**정확히 확인된 실패 단계:** mpm_prepare_input.ps1의 Invoke-WebRequest가 아래 공식 input-template URL을 가져오는 단계다.

https://www.mathworks.com/content/dam/mathworks/mathworks-dot-com/products/mpm/mpm-input-r2026b.txt

script는 UseBasicParsing과 Mozilla/5.0 UserAgent를 사용했고, 성공하면 destinationFolder를C:\Program Files\MATLAB\R2026b로 바꾼 뒤 noJRE=true,caller=agent를 넣도록 작성됐다. 그러나 input 파일이 남지 않았다. 실행 기록 results/iphone6_stitch_20261023/EXECUTION_RECORD.json의 toolboxes.template_fetch_install_attempt에는 다음이 저장돼 있다.

> HTTP access denied twice; installation not completed

따라서 현재 증거는 **template HTTP 접근 거부로 준비 단계가 중단됨**을 지지한다. Toolbox payload 다운로드,license activation 또는 mpm의 실제 제품 설치 실패로 혼동하지 않는다. **원래 HTTP 숫자 status code와 응답 headers는 보존된 script/실행JSON에서 확인되지 않았다.403이라고 추정해 적지 않는다.** 해당 작업 폴더에는 stderr/log도 없다.

기존 script가 요청하던 제품은 Signal Processing Toolbox + Image Processing Toolbox였다. 이번 요청은 **Signal Processing Toolbox + Wavelet Toolbox**이므로 기존 prepare/install script를 그대로 재실행하면 제품 선택도 틀린다.

C:/Users/leechanghoon/AppData/Local/Temp/mathworks_leechanghoon.log는 마지막에Oct22 R2025a 제거 성공과support-package 탐색을 담고 있다. 그 안의 Signal/Wavelet 이름 목록은Oct23 mpm 설치 성공 증거가 아니다.

## 3. 오늘 공식 경로 확인

- 공식 [MPM 페이지](https://www.mathworks.com/products/mpm.html)의R2026b link를 따라 **위와 같은 template URL을 web 도구로 정상 읽었다**. 로컬 PowerShell의 접근까지 검증한 것은 아니다.
- 그 template에서 정확한 제품명은 product.Signal_Processing_Toolbox 및 product.Wavelet_Toolbox다. 기존 설치에 제품을 추가할 때 destinationFolder는 기존MATLAB root를 사용하도록 명시돼 있다. Checksum은 ?checksum=UjIwMjZi이며 수정하면 안 된다. [R2026b template](https://www.mathworks.com/content/dam/mathworks/mathworks-dot-com/products/mpm/mpm-input-r2026b.txt)
- Windows mpm은 administrator 실행이 필요하다. 설치된 제품은 건너뛰며 필요한 제품 dependency를 포함한다. 공식 문서는 현재 mpm을 받도록 안내한다. [Get MATLAB Package Manager](https://www.mathworks.com/help/install/ug/get-mpm-os-command-line.html)
- 공식 mpm 문서는 기존root에 제품을 추가하는 방식과 --inputfile 단독 사용을 지원한다. --inputfile와 --release/--products 등 다른 옵션을 섞지 않는다. [mpm install](https://www.mathworks.com/help/install/ug/mpminstall.html)

공식 GitHub input-files 경로도 문서에 링크돼 있으나, 추정한R2026b raw URL은이번 점검에서404였다. 그 URL을 작동하는 대체 download 경로로 추천하지 않는다. 기존root 추가 설치는 공식적으로 지원되므로 단순히 root가 존재한다는 이유로 새 MATLAB 설치 경로를 만들 필요는 없다.

## 4. 다음 실행: 새 input 준비 후 기존 root에 두 toolbox 추가

아래는 **root가 준비·검토 후 실행할 명령 형식**이며 이번 감사에서 실행하지 않았다. 기존Oct23 파일은 보존한다. 새 작업 폴더는 skill의 timestamp 규칙에 맞춰 실행 소유자가 정한다.

1. 새 ASCII PowerShell script를 Write tool로 작성하고, 기존 공식R2026b template URL을 내려받는다. max-one retry 규칙과HTTP 실패 기록을 유지한다.
2. 새 input에서 다음 설정만 활성화한다. 나머지 product lines는 comment로 유지하고 원래checksum은 보존한다.

    destinationFolder=C:\Program Files\MATLAB\R2026b
    noJRE=true
    caller=agent
    product.Signal_Processing_Toolbox
    product.Wavelet_Toolbox

3. 다운로드/입력검증이 성공한 후 **유일한 mpm option은 --inputfile**인 다음 명령을 administrator로 실행한다. NEW_INPUT는root가 만든새파일의절대경로다.

    "C:\Users\leechanghoon\Downloads\mpm.exe" install --inputfile="NEW_INPUT_ABSOLUTE_PATH"

PowerShell 실행 wrapper는절대 MpmPath/InputFile를 받고 아래형식을사용한다. 경로의spaces 때문에 input argument의내부따옴표를유지한다.

    $installArgs = @('install', ('--inputfile="' + $InputFile + '"'))
    $process = Start-Process -FilePath $MpmPath -ArgumentList $installArgs -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode

wrapper자체는skill대로 .ps1로저장하고다음처럼호출한다.

    powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "NEW_INSTALL_WRAPPER_ABSOLUTE_PATH"

User가이미설치를승인한맥락은root가판단한다. 이읽기감사에는추가확인질문이필요하지않았다. 본문은새script나input의존재를주장하지않는다.감사에기록된위설정은실행된설정이아니다.

## 5. 준비 download가 다시 막힐 때의 공식 대안

이미있는R2026b interactive installer로기존root에Signal Processing과Wavelet을추가하는경로가있다. [Add Toolboxes and Products](https://www.mathworks.com/help/install/ug/add-to-existing-installation.html)

- 실행파일: C:/Users/leechanghoon/Downloads/_temp_matlab_R2026b_Windows/setup.exe
- 설치root: C:/Program Files/MATLAB/R2026b
- 제품: Signal Processing Toolbox; Wavelet Toolbox

공식Support 설명은같은root를선택하면MATLAB재설치가필요없으며,installer를실행할때MATLAB을닫아야한다고한다. 따라서현재shared desktop의checkpoint와종료/재시작은root가serialize해야한다. 이agent가세션을닫지않았다. [MathWorks Support: additional toolboxes](https://www.mathworks.com/matlabcentral/answers/101885-how-do-i-install-additional-toolboxes-into-an-existing-installation-of-matlab)

Noninteractive setup.exe의installer_input.txt 경로는별도File Installation Key와product installation files를요구한다. 기존MathWorks account로그인만으로그키가이미있다고가정하면안된다. [Noninteractive installer](https://www.mathworks.com/help/install/ug/install-noninteractively-silent-installation.html)

## 6. 성공 판정

기존matlab.exe가있다는것만으로이번toolbox추가성공을판정할수없다.설치process종료와exit status를기록하고현재prodcontents에서두제품key를확인한다.이후root가소유한MATLABsession에서version/toolbox목록과필요함수호출을검증한다.기존captured IQ나분석코드는이설치감사에서변경하지않았다.

읽은자료: 설치skill전체,현재prodcontents,Oct22setup/inventoryJSON,Oct23세script와EXECUTION_RECORD,기존MathWorkslog의header/tail및관련행,toolkittroubleshooting의설치/MCP섹션,위공식web문서.기존계정token/credential파일은열지않았다.


## 7. 같은 날 설치 소유자의 새 실행 — 설치 성공, 실행 검증 별도

설치 소유자가 직접 HTTP 요청의 403 재발을 확인했다고 보고했다. 이 숫자는 **Oct26 새 시도**의 보고값이며, 원래 Oct23 기록에 없던 status code를 소급해서 확인한 것은 아니다.

소유자는 같은 공식 URL의 497-line template를 web 도구로 읽고 원본과 편집본을 다음 작업 폴더에 저장했다.

C:/Users/leechanghoon/Documents/Codex/2026-09-21/snr-svd/tempestsdr-cloud/research/mobile_mipi_leakage/matlab_agentic_lab/results/iphone6_cfo_timing_20261026/install

- mpm_template_web.txt: 공식 template 원본 보존본
- mpm_input_r2026b.txt: 이번 두 제품을 활성화한 입력
- mpm_install.ps1: 소유자가 시작한 설치 wrapper

읽기 점검에서 편집본의 활성 설정은 기존 R2026b root, noJRE=true, caller=agent, product.Signal_Processing_Toolbox, product.Wavelet_Toolbox, ?checksum=UjIwMjZi였다. 설정은 이번 요청과 일치한다.

실제 실행 로그는 **C:/Users/leechanghoon/AppData/Local/Temp/mathworks_leechanghoon.log**에서 확인했다.

| 로그 시각 KST | 확인된 상태 |
|---|---|
|2026-10-26 15:07:28|새 MPM 실행 시작; MPM version 2026.8|
|15:07:29|제품 metadata 다운로드 시작|
|15:07:30|제품 metadata 다운로드 완료|
|15:07:51|support package metadata 취득 시작|
|15:07:59|support package metadata 취득 완료|
|15:09:11|manifest cache 생성 및 제품 등록 완료|
|15:09:17|Exiting with status 0; End - Successful|

최종 로그에서 설치 성공(exit status 0)을 확인했다. 설치 후 prodcontents.json의 제품 keys에는 MATLAB, MATLAB Copilot 외에 **Signal Processing Toolbox 26.2 win64**와 **Wavelet Toolbox 26.2 win64**가 추가됐다. 이는 제품 설치의 증거이며, 현재 MATLAB 세션의 사용권 및 pwelch/cwt 등 실제 함수 실행 검증은 설치 소유자가 별도로 진행한다. 이 감사 에이전트는 installer나 MATLAB을 실행하지 않았고 설치 설정을 변경하지 않았다.
