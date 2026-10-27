# RGB888·3-lane DSI codebook: 원문 검증 메모

작성 2026-10-27. 문헌 검증과 정수 연산 검산만 수행했다. MATLAB 실행·실제 IQ 디코딩을 수행한 결과가 아니다. 3 data lanes, 750-pixel 단일 행 packet, RGB888은 이번 실험의 가설이며 iPhone 6의 실제 설정으로 확인되지 않았다.

## 원문과 독해 범위

1. 사용자 보유 MIPI Alliance Specification for DSI v1.3, 23-Mar-2015 DRAFT. 경로: C:/Users/leechanghoon/Desktop/MIPI_Alliance_Specification_DSI/MIPI_Alliance_DSI_ver1.3.pdf. 이번에 PDF32–35, 53–56, 58, 64, 66, 77, 98–102의 추출 텍스트를 직접 읽었다. 인쇄 page=PDF page−12. DRAFT/Confidential 표기를 보존하며 공식 배포판 진위 확인 및 재배포는 하지 않는다. 기존 sources.jsonl의 local_dsi_v13 항목과 같은 파일이다.
2. Keysight M8085A MIPI D-PHY Editor User Guide, M8085-91040, Edition6.2 June2019: pp.32–33(EoTp),68–69(HS sync·LSB-first),116(HS-0/leader). 공식 PDF: https://www.keysight.com/ge/en/assets/9018-04458/user-manuals/9018-04458.pdf
3. ST AN4860 Rev4: Table7 pp.38–39(DT와mode), Fig45 p.42(RGB888). 공식 검색 추출로 확인했으며 전체 PDF 정독이라고 주장하지 않는다. https://www.st.com/resource/en/application_note/dm00287601.pdf
4. TI SNLA356, DS90UB941AS-Q1 DSI Bringup Guide: §2.1 p.2에서 RGB888 DT0x3E와video mode 확인. 해당 TI chip의 지원범위를 모든 DSI로 일반화하지 않는다. https://www.ti.com/lit/an/snla356/snla356.pdf (이번 공식 검색 인덱스: https://www.ti.com.cn/litv/pdf/snla356)
5. Espressif MIPI DSI LCD Detailed Guide, Protocol Layer·DCS Layer·Common Color Formats and Data Types 절: https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/mipi_dsi_lcd.html . 이 페이지의 legacy D-PHY 계산에서 8b/10b overhead를 붙이는 부분과 0x37을 DCS Read Response로 부르는 표는 DSI v1.3 원문과 일치하지 않아 모델 근거에서 제외한다. 원문의 DT0x37은 Set Maximum Return Packet Size이다.
6. Linux upstream include/video/mipi_display.h: DCS command0x2C/0x3C 및 DSI DT0x39/0x3E 독립 구현 교차확인. https://raw.githubusercontent.com/torvalds/linux/master/include/video/mipi_display.h . moving master로서 규범 문헌 대체물이 아니다.

## 확정할 수 있는 프로토콜 규칙

- DSI는 packet byte를 LSB부터 직렬화하며, WC와 CRC의 multi-byte 값은 낮은 byte부터 보낸다(DSI §8.3 PDF55/인쇄43, §8.4.1 PDF56/44).
- HS sync는 byte표기로 B8, 시간순 bit로 00011101이다(Keysight p.68 및116). PHY SoT는 모든 활성 data lane에서 병렬로 수행된다(DSI §6 PDF32/20). packet stream에 B8 하나를 삽입하여 세 lane으로 분배하는 모델은 틀리다.
- 한 HS transmission에는 여러 packet이 연결될 수 있다. packet 사이에는 별도 sync word가 없으며 DT/WC로 경계를 센다(§8.1 PDF53–54/41–42, §8.5.1.2 PDF58/46). 따라서 packet마다 새로운 SoT를 강제하면 안 된다.
- Lane distributor는 HS transmission의 연속 byte stream에 round-robin을 적용한다. HS 시작의 byte0은 lane0이다. 같은 HS 안의 새 packet은 앞선 packet 누적 byte수를 반영한다. packet 내부에서 lane번호를 다시0으로 초기화하지 않는다(§6과§8.1의 결합).
- 마지막 byte수가3의배수가 아니면 일부 lane이 한 byte-clock 먼저 끝날 수 있다. 존재하지 않는 data byte를 0으로 padding하여 전송한 것처럼 취급하지 않는다(§6.1.3 PDF33/21, Fig9 PDF35/23).
- EoTp는 PHY EoT/HS-trail과 별개의 고정4byte packet 08 0F 0F 01이며 VC도0으로 고정이다. 다른 packet과 동일하게 lane분배한다(§8.8.2 PDF64/52; Keysight p.33). EoTp 기능은 비활성일 수 있다(§8.1 PDF53/41). PHY종료 상태와 그 지속시간은 별도 모델이다.
- RGB888 video packet은 DT3E, payload는 R,G,B 순서이며 각 성분8bit이다(§8.8.23 PDF77/65). RGB888 화면이라고 무조건 DT3E인 것은 아니다. command-mode memory write는 DT39 long packet 안에 DCS command와 RGB parameters를 싣는다(§8.8.9.3 PDF66/54).

## 조건부 codebook: 750 pixels, 3 lanes

Video long packet의 WC=3×750=2250=0x08CA이다. 구조는 DI, CA,08,ECC,2250payloadbytes,CRC_L,CRC_H이며 총2256bytes다. WC에는 header/footer가 포함되지 않는다. DI=(VC<<6)|DT.

|VC|Video header DT3E WC2250|DCS header DT39 WC2251|
|---|---|---|
|0|3E CA 08 09|39 CB 08 12|
|1|7E CA 08 1F|79 CB 08 04|
|2|BE CA 08 10|B9 CB 08 0B|
|3|FE CA 08 06|F9 CB 08 1D|

DCS경우1byte명령2C(write-memory-start) 또는3C(continue)가 RGB앞에 추가되므로 WC2251이다. 750pixels가 하나의 packet에 들어간다는 가정이다. 실제chunking/partial-update/multirow-packet이면 WC부터 달라진다.

ECC는 DSI §9.3 PDF98–99/86–87의 P0–P5식에 따라 JavaScript로 계산했다. 독립검산: header08 0F 0F→ECC01(고정EoTp), 37 F0 01→3F(Fig46 PDF99/87). ECC는 header24bits만 보호하며 화면payload CRC와 다르다.

CRC는 §9.6 PDF100–101/88–89: polynomial x^16+x^12+x^5+1, initFFFF, payload LSB-first, final register를 낮은byte부터 전송. reflected implementation의 polynomial8408, finalxor0을 사용했다. 독립검산: empty→FFFF, payload01→1E0E(Fig21 PDF55/43). 2250bytes 모두FF이면 CRC7B93(전송93 7B), 모두00이면 CRC754A(전송4A 75). 흑백혼합행의CRC는 해당행 전체payload에서 계산해야 하며 알 수 없는문자의CRC를knownpilot으로 고정하면 안 된다.

### Header때문에 달라지는 lane별 color phase

HS시작 직후의 첫video packet(또는 누적stream offset mod3=0)에서:

|byte-clock slot|lane0|lane1|lane2|
|---|---|---|---|
|PHYsync|B8|B8|B8|
|0|DI|CA|08|
|1|ECC|R0|G0|
|2|B0|R1|G1|
|3|B1|R2|G2|
|…|…|…|…|
|751|B749|CRC_L|CRC_H|

즉 R→lane1, G→lane2, B→lane0이며 B가R/G보다한byte-clock 늦는다. 대역제한채널이세lane을합치면 이 지연은 byte-cycle structure를 바꾼다. 단순히lane0=R,lane1=G,lane2=B로 놓으면 header4byte offset을 잃는다. 다만 이는전송색상의순서에대한모형이지 EM수신채널의물리lane이름을관측으로 식별했다는 뜻이아니다.

시작laneoffset a, packet내byteindex k이면 lane=(a+k) mod3. 다음packet a_next=(a+WC+6) mod3(long), 또는(a+4) mod3(short)이다. 새SoT에서는 a=0으로복귀한다. 750pixel video길이2256mod3=0이라 자체만반복하면phase유지. 같은길이 DCS는2257mod3=1이라중간LP재진입없이연결하면 headerlanephase가0→1→2→0으로순환한다. 끼어드는short/null/blanking packet도누적해야한다. 이조건에서3-packet modulation이생길수있지만실제폰에서검출됐다는증거는아니다.

## rate/cycle에서 할 수 있는 것과 할 수 없는 것

R_lane를lane당bit/s로정의하면 f_byte=R_lane/8, forwarded DDRclock의fundamental f_clk=R_lane/2이다. DDR이라는말을bitrate와clockfrequency에섞어쓰지않는다. RGB888 3lane의payload처리속도는 ideal활성구간에서 f_pixel=3R_lane/24=f_byte이다. 영상의raster pixelclock은burst/blanking때문에이활성pixel throughput과다를수있다.

현재112802.5501974424Hz를1row/packet cadence라고 가정하면 T=8.8650478us이다. video2256bytes는lane당752bytes=6016UI이다. packet이그한주기안에모두들어가야하므로 R_lane>=6016/T=678.620142Mb/s, f_byte>=84.827518MHz가조건부하한이다. SoT/HSentry/trail/blanking/다른packet시간은추가이므로실제lane속도는더클수있다. 반대로검출주기가packet이아니거나750pixels가한packet이아니면이하한의전제도무효이다. 이값으로lane bitrate를측정했다고표시하면안된다.

## 흰색/검정 두 codeword의 유용성과 한계

이상적payload두종류는 white FF FF FF와black00 00 00이다. 그러나3lane RGB888에서는같은색이계속되는구간의각lane이모두1또는모두0의NRZ run이된다. byte경계에서반드시전이가발생하지않는다. 따라서clock/HS상태를제외한이상적constantpayload자체가항상 f_byte line을만드는것은아니다. codebook은단일pixel의독립2개RFsymbol보다 boundary의역할을포함해야한다:

- white→white, white→black, black→white, black→black의context.
- SoT/header→payload와payload→CRC/EoTp의전이.
- lane별복소결합계수, skew, 수신bandfilter.

전이미분 e_l[n]=s_l[n]−s_l[n−1]을방사기저후보로쓰면긴white와black모두interior에서는0이다. 제곱 |e_l|^2은white→black과black→white의방향까지지운다. 이것이power-onlytemplate의명시적퇴화사례다. 실제CM방사가순수미분이라고확정하는것도아니므로 NRZ/transition/clock-gated basis를분리하여holdout으로비교한다. 화면glyph의antialiasing회색픽셀은2색가정의잔차/추가codeword로남겨야한다.

## cyclic template의 해석

사용자표현의2차정상(WSS)이아니라2차cyclostationary를검정한다. 정의R_x(n,tau)=E[x[n+tau]x*[n]]가n에대해P주기일때이를alpha=k/P Fourier계수로전개한다. power g[n]=E|x[n]|^2는 tau0인특수한단면일뿐이다. 같은power profile을가진다른bitstream이많으므로 g[n]일치만으로header/문자bitdecode를확정할수없다. 엄밀한WSS라면비영alpha의2차cyclic계수는0이다.

사각HSgate g[n]=P_HS·1(mod(n−n0,P)<D)는첫근사로유용하지만bandfilter,channelmemory, clock/LP누설,여러packet 때문에실제power는두값일필요가없다. FAM으로찾은alpha를packet/row가설로두고codebook 기반 예측의독립적상관과다른후보대조로의미를정한다.

## 적용시 우선 보존할 후보와 불확실성

최소bank: video3E 및DCS39(2C/3C), VC0–3, packetstartlanephase0–2, EoTp유무, 한HS당single/multiplepacket. mode/phase후보를한꺼번에과적합하지말고독립검증 점수와조건수를기록한다. HS-0/prepare/trail시간과lane별RFresponse는측정전unknown이다. B8시점이맞는다는것만으로lane수와각lane채널은분리되지않는다(모든lane이같은B8을송신하기때문).

원문에근거한bitstream→세lane→LSB직렬화→NRZ/transition basis→해당RF대역제한→fractional sampling 순서를권한다. IQ에0/1bytes를직접대입하는template를물리적forwardmodel로취급하지않는다. 최종성공판정은header와packetboundary검출, held-outtiming/coherence, ECC/CRC일관성, 실제문자내용개선을별도로한다.
