"""Reproduce the first curated MIPI research snapshot, dated 2026-10-22 KST.

No network. Claims are curated; extraction alone is never marked as reading.
"""
from pathlib import Path
import hashlib
import json
import os

ROOT = Path(__file__).resolve().parent
DATE = '2026-10-22'
COMMIT = '97e4fbcdb31efe88b91cd321dae7bbaece36c51a'
REPO = 'https://github.com/prashantpaddune/android_kernel_samsung_a7y18lte'
KERNEL_BASE = REPO + '/blob/' + COMMIT + '/'
LOCAL_MAP = ROOT / 'local_source_paths.json'
local_paths = json.loads(LOCAL_MAP.read_text(encoding='utf-8')) if LOCAL_MAP.exists() else {}
local_spec_path = os.environ.get('MIPI_DSI_V13_PDF') or local_paths.get('local_dsi_v13')
LOCAL_SPEC = Path(local_spec_path) if local_spec_path else None
LOCAL_SPEC_SHA256 = '8252c82e49f093c21fced2d848d5e3cf391b2fe12a24feb18b921069c2f78dea'

def digest(path):
    if path is None or not path.is_file():
        return None
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

sources = [
    dict(source_id='mipi_dphy_overview', title='MIPI D-PHY official overview', publisher='MIPI Alliance', url='https://www.mipi.org/specifications/d-phy', source_type='official_web', access='public_overview_only', coverage='Overview, Latest Releases, specification access statements', limitation='Full specification not accessed. New v3.5 embedded clock capability must not be applied to a 2018 phone.'),
    dict(source_id='mipi_dsi2_overview', title='MIPI DSI-2 official overview', publisher='MIPI Alliance', url='https://www.mipi.org/specifications/dsi-2', source_type='official_web', access='public_overview_only', coverage='Overview, Capabilities, Latest Release, specification access statements', limitation='Current specification features do not identify the protocol revision implemented by the target devices.'),
    dict(source_id='mipi_dsi_cockpit_2021', title='How Use of DSI-2 and Video Compression Is Essential for Next-Generation Digital Cockpits', publisher='MIPI Alliance', author='Simon Bussieres', year=2021, url='https://www.mipi.org/hubfs/Automotive-Workshop/How-Use-of-DSI-2-and-Video-Compression-Is-Essential-for-Next-Gen-Digital-Cockpits.pdf', source_type='official_pdf', cache_path='cache/mipi_dsi_cockpit_2021.pdf', total_pdf_pages=34, access='public_download', coverage='All 34 pages extracted text read; protocol mode diagrams on pages 7-9 visually reviewed. Image-only automotive quality slides are not claimed to have been fully read.', limitation='Automotive examples and compression performance are not smartphone measurements.'),
    dict(source_id='tek_dphy_tests', title='TekExpress MIPI D-PHY Test Application Datasheet', publisher='Tektronix', version='61W-61487-7, 6 Oct 2025', url='https://download.tek.com/datasheet/D-PHY-Datasheet_61W614877.pdf', source_type='official_pdf', cache_path='cache/tek_dphy_tests.pdf', total_pdf_pages=8, access='public_download', coverage='Text pages 1-8 read; page 4 test table visually checked.', limitation='Vendor compliance test list, not the normative CTS and not evidence of a particular phone emission.'),
    dict(source_id='ti_slla104a', title='Suggestions for High-Speed Differential Connections', publisher='Texas Instruments', author='Chris Sterzik', version='SLLA104A, September 2004', url='https://www.ti.com/lit/an/slla104a/slla104a.pdf', source_type='official_pdf', cache_path='cache/ti_slla104a.pdf', total_pdf_pages=9, access='public_download', coverage='Text pages 1-9 read; page 6 connector/skew diagram and EMI section visually checked.', limitation='General differential interconnect evidence; not a DSI emission amplitude or smartphone source identification.'),
    dict(source_id='arasan_dphy_2019', title='Total MIPI Camera IP Solution CSI-2 v1.3', publisher='Arasan Chip Systems', year=2019, url='https://www.arasan.com/wp-content/uploads/2019/08/Total-MIPI-Camera-IP-Solution_CSI-2-v1.3_Aug-2019.pdf', source_type='official_pdf', cache_path='cache/arasan_dphy_2019.pdf', total_pdf_pages=55, access='public_download', coverage='PDF pages 18-22 and 25-29 text read; section 4.4 on PDF 27 / printed 21 visually checked.', limitation='Used only for shared D-PHY behavior; CSI-2 packet types are not DSI packet types.'),
    dict(source_id='samsung_a7_2018', title='Widen Your World with the Galaxy A7', publisher='Samsung Global Newsroom', published='2018-09-20', url='https://news.samsung.com/global/widen-your-world-with-the-galaxy-a7', source_type='manufacturer_web', access='public_web', coverage='Announcement and Product Specifications table', limitation='Does not disclose DSI lane rate, panel timing, or measurement settings.'),
    dict(source_id='a7_kernel_configuration', title='Samsung-copyright A7 2018 panel configuration and Exynos7885 DSI driver, community mirror', publisher='Samsung code in prashantpaddune community repository', url=KERNEL_BASE+'arch/arm64/boot/dts/exynos/display-lcd_a7y18_common.dtsi', source_type='source_code_mirror', access='public_github', commit=COMMIT, coverage='Entire panel file; board include lines 1-50; dsim_drv.c timing parser excerpts; dsim_reg.c configuration and PLL sections.', files=[dict(path='arch/arm64/boot/dts/exynos/display-lcd_a7y18_common.dtsi',git_blob_sha='788eb7407e89c755e47bcd0c0915dd20b6576625'),dict(path='drivers/video/fbdev/exynos/dpu_7885/dsim_drv.c',git_blob_sha='7eb86b98fe0865b6ca70a6452ed01478c6f1fc63'),dict(path='drivers/video/fbdev/exynos/dpu_7885/dsim_reg.c',git_blob_sha='46f5d2b3ffa3f6c61f5b8c44da280aee1b3cd13e')], limitation='Configuration evidence in a public mirror. Not verified against a Samsung release archive, installed firmware, bootloader state, device revision, or actual RF capture.'),
    dict(source_id='local_dsi_v13', title='Specification for Display Serial Interface (DSI), Version 1.3', publisher='MIPI Alliance', version='23 March 2015', source_type='user_local_pdf', source_basename='MIPI_Alliance_DSI_ver1.3.pdf', total_pdf_pages=119, access='user_local_only', sha256=digest(LOCAL_SPEC) or LOCAL_SPEC_SHA256, coverage='Title/legal/TOC PDF pages 1-6; substantive PDF pages 23-33,53-58,60-62,65-66,77,87-93; figures on PDF 31,77,91 visually checked.', limitation='Full PDF not read. Marked Confidential/All rights reserved. Original and extracted pages are not redistributed or committed. Printed page = PDF page - 12 for cited substantive pages.'),
]
for source in sources:
    source.update(record_date_kst=DATE, reader='mipi_dphy_research', snapshot='cycle_001')
    if 'cache_path' in source:
        source['sha256'] = digest(ROOT/source['cache_path'])
        source['redistribution'] = 'Local cache only; no general redistribution license inferred from public access.'

claims = []
def claim(claim_id, text, kind, refs, confidence='high', qualification=None, tags=None):
    claims.append(dict(claim_id=claim_id, claim=text, kind=kind, evidence=refs, confidence=confidence, qualification=qualification, tags=tags or [], record_date_kst=DATE, reader='mipi_dphy_research'))
def ref(source, locator):
    return dict(source_id=source, locator=locator)

claim('MIPI-001','Forwarded-clock D-PHY transfers one data bit on each clock edge: lane bit rate R_lane = 2*f_DDR and byte rate = R_lane/8.','protocol_fact',[ref('arasan_dphy_2019','section 4.4, PDF 27 / printed 21')],qualification='Applies to the forwarded-clock mode; newer embedded-clock D-PHY modes need a different model.',tags=['DDR','clock','units'])
claim('MIPI-002','Current D-PHY includes optional embedded clocking from v3.5; the overview is not proof that a 2018 handset uses it.','version_scope',[ref('mipi_dphy_overview','Latest Releases')],tags=['version','scope'])
claim('MIPI-003','HS uses terminated differential signaling; LP uses unterminated single-ended signaling. A received emission mixture may include both states.','protocol_fact',[ref('tek_dphy_tests','PDF 3, probing requirements')],qualification='The mixture statement is an inference; signal-state identification requires measurement.',tags=['HS','LP','radiation'])
claim('MIPI-004','DSI video mode streams timed pixel data; command mode can write a local frame buffer. Burst video shortens transfer time within a line.','protocol_fact',[ref('mipi_dsi_cockpit_2021','PDF 4 and 7-10'),ref('local_dsi_v13','section 4.2, PDF 24 / printed 12; section 8.11, PDF 88-91 / printed 76-79')],tags=['command','video','burst'])
claim('MIPI-005','DSI byte distribution is round-robin across lanes; RGB888 uses three successive component bytes. Four lanes therefore do not map to four fixed colors.','protocol_fact',[ref('local_dsi_v13','section 6, PDF 31-33 / printed 19-21; section 8.8.23, PDF 77 / printed 65')],qualification='The resulting lane/color cycle is derived from these two rules; packet headers and command bytes set its phase.',tags=['lanes','RGB888','mapping'])
claim('MIPI-006','Short packets have 4 bytes; long packets have a 4-byte header, payload, and 2-byte footer. Multiple packets can share a single HS transmission.','protocol_fact',[ref('local_dsi_v13','sections 8.1-8.5, PDF 53-58 / printed 41-46')],tags=['packet','overhead'])
claim('MIPI-007','0x3e is the RGB888 video pixel-stream data type. 0x39 is DCS Long Write and includes a command byte before parameters/data.','protocol_fact',[ref('local_dsi_v13','section 8.8.9.3, PDF 66 / printed 54; section 8.8.23, PDF 77 / printed 65')],qualification='Command-mode image transport cannot be decoded by assuming every pixel packet is type 0x3e.',tags=['command','packet','RGB888'])
claim('MIPI-008','A command-mode display has local refresh timing; TE can report timing events to the host. Link activity and panel scanning are distinct processes.','protocol_fact',[ref('local_dsi_v13','section 8.12, PDF 92-93 / printed 80-81')],qualification='An actual phone may use a separate TE pin; this source describes DSI in-band TE. A periodic capture alone cannot identify either path.',tags=['TE','timing','command'])
claim('MIPI-009','Driver and interconnect imbalance creates time-varying common-mode currents; connector skew can raise radiated emissions.','physical_mechanism',[ref('ti_slla104a','PDF/printed 3,5,6; section 2.2 and 2.3')],qualification='This does not establish the dominant source in any of the user captures.',tags=['common_mode','skew','EMI'])
claim('MIPI-010','D-PHY compliance characterization explicitly measures static common-mode mismatch and dynamic common-mode variation in two frequency regions.','measurement_fact',[ref('tek_dphy_tests','PDF 4 tests 1.3.7-1.3.10; PDF 5 tests 1.4.7-1.4.10')],qualification='Test existence is not a measured common-mode spectrum for the target handset.',tags=['common_mode','measurement'])
claim('MIPI-011','Galaxy A7 (2018) has a 6.0-inch 1080 by 2220 Super AMOLED display.','manufacturer_fact',[ref('samsung_a7_2018','Product Specifications table')],qualification='An LCD-specific source/column-driver model is not automatically applicable to AMOLED.',tags=['A7','display'])
claim('MIPI-012','The pinned A7 kernel panel configuration selects s6e3fa7, MIPI command mode, 60 Hz, 4 data lanes, DSC disabled, and MIC disabled.','source_configuration',[ref('a7_kernel_configuration','display-lcd_a7y18_common.dtsi lines 50-68 and 78-81')],qualification='Not a measurement or a verified firmware configuration of the user device.',tags=['A7','command','lanes','compression'])
claim('MIPI-013','A7 source requests dsi-hs-clk=997 and PLL P/M/S=3/230/1. The driver sets fin=26 MHz and divides hs_clk by 8 for byte clock.','source_configuration',[ref('a7_kernel_configuration','panel lines 57-59; dsim_reg.c lines 1341-1382; dsim_drv.c lines 1239-1246')],qualification='This hs_clk variable is the full-rate internal clock/rate representation, not the half-rate forwarded clock.',tags=['A7','PLL','units'])
claim('MIPI-014','With the source PLL formula and ideal 26 MHz reference, R_lane=996.6666667 Mb/s, f_DDR=498.3333333 MHz, byte rate=124.5833333 MHz.','derived',[ref('a7_kernel_configuration','dsim_reg.c lines 1348,1371,1378'),ref('arasan_dphy_2019','section 4.4, PDF 27 / printed 21')],qualification='Driver integer arithmetic reports hs_clk=996 and byte_clk=124; requested 997, integer log, and ideal physical PLL frequency are different. The PLL-stable bootloader branch can skip reprogramming.',tags=['A7','PLL','rounding'])
claim('MIPI-015','At full-frame 60 Hz RGB888 updates, active payload is 3.452544 Gb/s total or 863.136 Mb/s per lane for four lanes; active pixel throughput is 143.856 Mpixel/s.','derived',[ref('samsung_a7_2018','1080x2220'),ref('a7_kernel_configuration','60 Hz and 4 lanes; dsim_reg.c line 1240 RGB24')],qualification='Average full-frame payload demand. Excludes packet/state overhead; command update rate can differ from panel refresh.',tags=['A7','bandwidth','units'])
claim('MIPI-016','fc >> modulation bandwidth permits a complex-envelope description. It does not imply the RF carrier is the pixel clock or that the envelope bandwidth equals fh or fv.','derived_model',[],qualification='fc must identify an observed RF component. Image-dependent payload and burst transitions can occupy much wider bandwidth than row/frame repetition rates.',tags=['AM','PM','fc','fm'])
claim('MIPI-017','Small AM/PM around a nonzero coherent carrier can be linearized as u(t)≈A0[1+a(t)+j*phi(t)]. Carrier strength, smallness, and phase stability must be checked.','hypothesis',[],qualification='D-PHY does not mandate small-index AM/PM radiation. This is a testable local RF model, invalid near envelope zeros or for strong multicomponent interference.',tags=['AM','PM','hypothesis'])
claim('MIPI-018','Common-mode origin does not guarantee low matrix rank. Repeated vertical stripes can themselves form a rank-one row-repeated matrix.','mathematical_fact',[],qualification='Rank is defined after choosing a matrix construction and window. MIPI target versus panel clutter cannot be assigned by rank alone.',tags=['rank','RPCA','clutter'])
claim('MIPI-019','Residual CFO produces phase increments 2*pi*Delta_f*T_row between rows and 2*pi*Delta_f*T_frame between frames; timing mismatch changes raster alignment.','derived_model',[],qualification='These mechanisms can create hue bands and gradients; source attribution needs controls and independent channels.',tags=['phase','HSV','bands'])
claim('MIPI-020','Samples per pixel in a uniform raster model are Fs/fp. During uncompressed multi-lane payload, mean pixel time is b/(N*R_lane), so effective samples/pixel are Fs*b/(N*R_lane).','derived_model',[ref('local_dsi_v13','lane mapping section 6 and format section 8.8.23')],qualification='The latter is an average transport budget, not an isolated pixel sample. Packet overhead, lane superposition, command gating, receive bandwidth, and resampling all matter.',tags=['samples_per_pixel','resampling'])

readings = [
    dict(source_id='mipi_dphy_overview',mode='web_section_read',sections=['Overview','Latest Releases','Get the Specification'],completed='selected sections'),
    dict(source_id='mipi_dsi2_overview',mode='web_section_read',sections=['Overview','Latest Release','Capabilities','Get the Specification'],completed='selected sections'),
    dict(source_id='samsung_a7_2018',mode='web_section_read',sections=['Announcement','Product Specifications'],completed='selected sections'),
    dict(source_id='mipi_dsi_cockpit_2021',mode='pdf_text_read',pdf_pages=list(range(1,35)),visual_pages=[7,8,9],completed='all extracted page text; selected figures only',not_completed='Image-only quality and safety diagrams were not exhaustively inspected.'),
    dict(source_id='tek_dphy_tests',mode='pdf_text_read',pdf_pages=list(range(1,9)),visual_pages=[4],completed='all extracted page text; page 4 table visual'),
    dict(source_id='ti_slla104a',mode='pdf_text_read',pdf_pages=list(range(1,10)),visual_pages=[6],completed='all extracted page text; page 6 diagram visual'),
    dict(source_id='arasan_dphy_2019',mode='pdf_text_read',pdf_pages=list(range(18,23))+list(range(25,30)),printed_pages=list(range(12,17))+list(range(19,24)),visual_pages=[27],completed='selected pages',not_completed='45 other PDF pages not read.'),
    dict(source_id='a7_kernel_configuration',mode='source_code_read',commit=COMMIT,files=[dict(file='display-lcd_a7y18_common.dtsi',lines='all'),dict(file='exynos7885-a7y18lte_common.dtsi',lines='1-50'),dict(file='dsim_drv.c',lines='1233-1246'),dict(file='dsim_reg.c',lines='1234-1245,1334-1398')],completed='selected files/excerpts'),
    dict(source_id='local_dsi_v13',mode='pdf_text_read',pdf_pages=list(range(1,7))+list(range(23,34))+list(range(53,59))+list(range(60,63))+[65,66,77]+list(range(87,94)),visual_pages=[31,77,91],printed_page_mapping='Substantive page number = PDF page number - 12',completed='36 selected PDF pages',not_completed='83 PDF pages not counted as read. Initial truncated output is not counted as complete reading. No original PDF copied into the repository.'),
    dict(source_id='st_an4860',mode='download_attempt',url='https://www.st.com/resource/en/application_note/dm00287601.pdf',completed=False,status='ST request timed out; web PDF tool rejected 13099558-byte PDF. Search excerpts are discovery only; full-page reading not claimed.'),
    dict(source_id='st_an4511',mode='download_attempt',url='https://www.st.com/resource/en/application_note/an4511-common-mode-filters-stmicroelectronics.pdf',completed=False,status='ST and official alternate domain timed out. No reading claim.'),
    dict(source_id='st_other',mode='download_attempt',completed=False,status='ST DSI training and ECMF02-2AMX6 datasheet timed out. See download_log.json.'),
]
for record in readings:
    record.update(record_date_kst=DATE,reader='mipi_dphy_research',snapshot='cycle_001')

W,H,fv,bpp,lanes = 1080,2220,60,24,4
rlane = 230*26e6/(3*2)
htotal,vtotal = W+2+2+2,H+15+3+1
fh,fp = vtotal*fv,htotal*vtotal*fv
numeric = dict(record_date_kst=DATE, device='Galaxy A7 (2018)', measurement_status='No A7 IQ measurement performed in this cycle', source_commit=COMMIT,
    source_config=dict(width=W,height=H,refresh_hz=fv,lane_count=lanes,bits_per_pixel=bpp,mode='MIPI command',pll_reference_hz=26e6,P=3,M=230,S=1,requested_hs_clock_field=997),
    derived=dict(active_pixel_rate_per_second=W*H*fv,active_payload_bps=W*H*fv*bpp,average_payload_per_lane_bps=W*H*fv*bpp/lanes,ideal_lane_bitrate_bps=rlane,ideal_forwarded_clock_hz=rlane/2,ideal_byte_rate_hz=rlane/8,payload_pixel_throughput_per_second=lanes*rlane/bpp,mean_payload_pixel_time_s=bpp/(lanes*rlane),minimum_row_payload_s=W*bpp/(lanes*rlane),minimum_frame_payload_s=W*H*bpp/(lanes*rlane),payload_duty_at_60hz=(W*H*fv*bpp)/(lanes*rlane),driver_integer_hs_clock_mhz=(230*26)//(3*2),driver_integer_byte_clock_mhz=((230*26)//(3*2))//8),
    conditional_raster_example=dict(assumption='Use source porch fields as raster pixel/line counts. Command-mode transport and panel scanning are not established by this calculation.',Htotal=htotal,Vtotal=vtotal,fh_hz=fh,fp_hz=fp,row_s=1/fh,frame_s=1/fv),
    hypothetical_receiver_examples=[dict(Fs_hz=fs,Fs_status='illustrative only, not an A7 acquisition setting',samples_per_pixel_uniform_raster=fs/fp,samples_per_pixel_active_average=fs/(W*H*fv),samples_per_mean_payload_pixel=fs*bpp/(lanes*rlane),samples_per_raster_row=fs/fh) for fs in (20e6,60e6)],
    qualifications=['All clocks are source-based ideal calculations, not measured values.','Driver fin=26 and PMS formula assume the physical reference matches the source; fractional oscillator error and SSC are unmeasured.','The driver returns early if the PLL was already stabilized by the bootloader.','997 requested, 996 integer reported and 996.6667 ideal physical rate should not be conflated.','fh/fp calculation is conditional for a command-mode panel.','Receive bandwidth must be obtained from acquisition metadata; Fs alone is not proof of instantaneous analog bandwidth.'])

for name, records in [('sources.jsonl',sources),('claims.jsonl',claims),('reading_log.jsonl',readings)]:
    (ROOT/name).write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in records),encoding='utf-8')
(ROOT/'a7_2018_numeric_examples.json').write_text(json.dumps(numeric,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if LOCAL_SPEC is not None:
    LOCAL_MAP.write_text(json.dumps({'local_dsi_v13':str(LOCAL_SPEC)},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(dict(sources=len(sources),claims=len(claims),reading_records=len(readings),numeric=numeric['derived']),indent=2))
