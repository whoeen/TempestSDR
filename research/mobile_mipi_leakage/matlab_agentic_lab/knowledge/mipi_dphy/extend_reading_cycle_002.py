"""Append the completed two-document reading pass to the curated cycle-001 DB.

Run after build_knowledge_db.py to reproduce current metadata. This records an
actual manual reading pass; PDF extraction never by itself marks a page as read.
No source PDF is copied or published. Local files are used only for audit hashes.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
DATE = '2026-10-22'

def read_jsonl(name):
    return [json.loads(line) for line in (ROOT/name).read_text(encoding='utf-8').splitlines() if line.strip()]

def save_jsonl(name, rows):
    (ROOT/name).write_text(''.join(json.dumps(row,ensure_ascii=False)+'\n' for row in rows),encoding='utf-8')

sources = read_jsonl('sources.jsonl')
claims = read_jsonl('claims.jsonl')
readings = read_jsonl('reading_log.jsonl')

dsi_initial = set(range(1,7)) | set(range(23,34)) | set(range(53,59)) | set(range(60,63)) | {65,66,77} | set(range(87,94))
arasan_initial = set(range(18,23)) | set(range(25,30))
dsi_added = sorted(set(range(1,120))-dsi_initial)
arasan_added = sorted(set(range(1,56))-arasan_initial)
assert len(dsi_added)==83 and len(arasan_added)==45
dsi_visual = [31,35,43,48,60,68,71,72,75,76,77,84,91,96,101,112,117,119]
arasan_visual = [8,11,12,14,15,18,19,21,23,24,26,27,30,38,42,43,44,53]

for source in sources:
    if source['source_id']=='local_dsi_v13':
        source.update(snapshot='cycle_002',coverage='All extracted text on PDF pages 1-119 read across two passes, including front matter, command/data type tables, ECC/CRC tables, compliance and annexes. Selected visual pages: '+','.join(map(str,dsi_visual))+'.',text_pages_read=119,visual_pages_reviewed=dsi_visual,limitation='Not every page has been visually inspected. Document is user-provided, marked Confidential, and later page headers say DRAFT; authenticity against an official distribution was not independently verified. Source inconsistencies are logged, not silently corrected. Original/full text remain local and excluded from Git. Printed substantive page = PDF page - 12.')
    elif source['source_id']=='arasan_dphy_2019':
        source.update(snapshot='cycle_002',coverage='All extracted text on PDF pages 1-55 read across two passes, including CSI-2 controller chapters, combo PHY and standalone D-PHY PPI/pad/timing tables, deliverables and support. Selected visual pages: '+','.join(map(str,arasan_visual))+'.',text_pages_read=55,visual_pages_reviewed=arasan_visual,limitation='Not every page has been visually inspected. Some embedded pin-label images are low resolution. Vendor implementation evidence, not a normative D-PHY specification or target-phone implementation. CSI-2 and C-PHY behavior are not transferred to DSI D-PHY without qualification. PDF 42 required Poppler to resolve a dark MuPDF render.')

def add_claim(num,text,kind,source,locator,qualification,tags,confidence='high'):
    rec=dict(claim_id=f'MIPI-{num:03}',claim=text,kind=kind,evidence=[dict(source_id=source,locator=locator)],confidence=confidence,qualification=qualification,tags=tags,record_date_kst=DATE,reader='mipi_dphy_research',snapshot='cycle_002')
    for index,old in enumerate(claims):
        if old['claim_id']==rec['claim_id']:
            claims[index]=rec
            return
    claims.append(rec)

add_claim(21,'The DSI term Common Mode fault describes a transmitter/receiver HS-versus-LP state mismatch, not ordinary common-mode electromagnetic radiation.','protocol_fact','local_dsi_v13','section 7.2.2.2, PDF 49 / printed 37','Avoid conflating this recovery/error term with the research target i_CM or V_CM.',['common_mode','terminology'])
add_claim(22,'Null packets can keep lanes in HS while carrying dummy bytes; blanking packets carry timing and may carry arbitrary payload. HS activity duration is therefore not necessarily active-image payload duration.','protocol_fact','local_dsi_v13','sections 8.8.11-8.8.12, PDF 67 / printed 55','The last sentence is an inference for burst segmentation. Actual use is implementation dependent.',['HS','blanking','timing'])
add_claim(23,'In this DSI revision, peripheral-to-host transfers use LP mode on data lane 0; other lanes are unidirectional.','protocol_fact','local_dsi_v13','section 8.9, PDF 80-81 / printed 68-69','Bidirectional LP control traffic should not be modeled as reverse high-speed RGB payload.',['LP','direction','lane0'])
add_claim(24,'RGB666 packed format aligns four pixels to nine bytes; loosely packed RGB666 spends three bytes per pixel with component bits in byte bits 7:2.','protocol_fact','local_dsi_v13','sections 8.8.21-8.8.22, PDF 74-76 / printed 62-64; Figures 36-37 visually reviewed','Image bit depth alone does not determine wire bits per pixel. Confirm selected transport packing before sampling calculations.',['pixel_format','packing','bandwidth'])
add_claim(25,'DSI header ECC protects 24 header data bits using six relevant parity bits; long-packet payload CRC detects errors and does not correct them.','protocol_fact','local_dsi_v13','sections 9.1-9.6, PDF 95-101 / printed 83-89; Table 25 visually reviewed','P6/P7 are unused in DSI. Informative D24-D63 rows in the larger parity table must not be mistaken for this header payload. ECC/CRC cannot restore arbitrary bandwidth-limited analog IQ.',['ECC','CRC','scope'])
add_claim(26,'DSC transport needs its compression mode, PPS and slice configuration. PPS changes take effect after the next vertical sync in video mode or signaled tearing effect in command mode.','protocol_fact','local_dsi_v13','sections 8.8.25-8.8.26, PDF 79-80; Annex D.1.6, PDF 118-119 / printed 106-107','This is the v1.3 DSC profile, not all later DSC versions. The inspected A7 source has DSC disabled.',['DSC','PPS','timing'])
add_claim(27,'Execute Queue synchronizes queued frame-synchronized commands at the next video vertical event or internally processed command-mode tearing event.','protocol_fact','local_dsi_v13','section 8.8.27, PDF 80 / printed 68','Multi-driver synchronization details are outside the specification; this does not identify the physical source of a received stripe.',['TE','synchronization','drivers'])
add_claim(28,'The supplied DSI PDF contains a CRC example comment with an x^15 term, while section 9.6 and Figure 49 specify x^12 and the example constant is 0x8408.','document_observation','local_dsi_v13','PDF 100-101 / printed 88-89 and Annex B PDF 112 / printed 100 line 2516; both figures/code page visually checked','An internal inconsistency, not an official erratum. Implementation should follow a verified normative rule and independent test vectors, not copy the comment.',['source_quality','CRC'])
add_claim(29,'The one-pixel 30-bit and 36-bit packet examples in the supplied PDF show a Word Count field of one although four or five payload bytes are displayed.','document_observation','local_dsi_v13','PDF 71-72 / printed 59-60, lines 1575-1579 and 1597-1600; visual comparison with Word Count definition','Possible editorial inconsistency. No corrected packet hex sequence is asserted here; validate before use as decoder/encoder test vectors.',['source_quality','word_count'],confidence='medium')
add_claim(30,'The Arasan D-PHY PPI byte clock is specified as one eighth of HS bit rate; its 2.5-Gbit/s diagrams show a 1.25-GHz forwarded clock and 312.5-MHz byte clock.','vendor_implementation','arasan_dphy_2019','PDF 11-12,18-19 diagrams and PDF 30 / printed 24 Table 5','Illustrative vendor configuration, not A7 measurements. One label on PDF 11 has an extra decimal point; cross-checked against Table 5 and receiver diagrams.',['clock','units'])
add_claim(31,'The vendor PPI separates HS request, ready, data-valid and receive-active/sync signals; a request edge triggers the PHY start/end sequence.','vendor_implementation','arasan_dphy_2019','PDF 32-34 and 49 / printed 26-28 and 43','PPI control describes internal interface behavior. It is not an RF demodulation decision rule and gives no phone-specific register map.',['HS','gating','PPI'])
add_claim(32,'The Arasan combo PHY exposes periodic deskew-burst request and receive-calibration status signals.','vendor_implementation','arasan_dphy_2019','PDF 38 / printed 32, TxSkewCalHS and RxSkewCalHS rows visually reviewed','Calibration bursts are a candidate non-image activity class, not evidence that A7 or existing captures contain them.',['deskew','clutter','hypothesis'])
add_claim(33,'Arasan describes low-swing HS and larger single-ended LP signaling; these on-wire voltage swings do not by themselves determine the AM or PM index measured by an antenna.','model_qualification','arasan_dphy_2019','section 5.3.2.2, PDF 43 / printed 37','The modulation-index conclusion is physical reasoning. Radiation channel, carrier reference, geometry and state mixture need measurement.',['AM','PM','voltage','radiation'])
add_claim(34,'The vendor Escape-mode received clock is generated from LP signaling and may be aperiodic.','vendor_implementation','arasan_dphy_2019','PDF 36 and 50 / printed 30 and 44, RxClkEsc rows','Do not force all LP control intervals into a constant-period HS model.',['LP','escape','clock'])
add_claim(35,'The described C-PHY maps 16 PPI bits to seven symbols on a three-wire trio, whereas the described D-PHY uses a forwarded DDR clock.','vendor_implementation','arasan_dphy_2019','PDF 25-27 / printed 19-21; PDF 26 and 27 visually reviewed','C-PHY coding and clock relations are not used to infer the present D-PHY devices. Vendor document C-PHY revision labels vary and must be checked before a hardware implementation.',['C-PHY','D-PHY','scope'])

reading_events=[
 dict(reading_id='cycle_002_dsi_remaining',source_id='local_dsi_v13',mode='pdf_remaining_text_read',pdf_pages=dsi_added,additional_pages=83,cumulative_text_pages=119,total_pdf_pages=119,visual_pages=dsi_visual,completed='All extracted page text read across cycles 001 and 002; selected diagrams/tables visually checked',not_completed='All-page visual inspection and authoritative-copy/errata verification were not completed. External D-PHY, DCS and DSC standards referenced by the PDF were not fully acquired/read.'),
 dict(reading_id='cycle_002_arasan_remaining',source_id='arasan_dphy_2019',mode='pdf_remaining_text_read',pdf_pages=arasan_added,additional_pages=45,cumulative_text_pages=55,total_pdf_pages=55,visual_pages=arasan_visual,completed='All extracted page text read across cycles 001 and 002; selected diagrams/tables visually checked',not_completed='All-page visual inspection was not completed. Embedded transmitter pin diagram labels are low resolution; topology inspected, exact pin details rely on textual tables.',render_repair='MuPDF page 42 figure appeared nearly black; Poppler rerender resolved the diagram and was visually inspected.'),
]
for event in reading_events:
    event.update(record_date_kst=DATE,reader='mipi_dphy_research',snapshot='cycle_002')
    readings=[r for r in readings if r.get('reading_id')!=event['reading_id']]
    readings.append(event)

# Topic ranges document what was read, including sections unrelated to immediate RF reconstruction.
dsi_topics=[(1,2,'Title, provenance, legal notices'),(3,10,'Contents, figure and table indices'),(11,12,'Release history and intentional blank'),(13,18,'Scope, normative wording, definitions and units'),(19,21,'Referenced DCS, DBI, DPI, CSI, D-PHY, SDF and DSC documents'),(22,25,'Layers, host/peripheral architecture and modes'),(26,30,'Physical protocol, clock management and power-up'),(31,35,'Lane byte distribution, differing end times'),(36,44,'Split-link architecture, skew and address mapping'),(45,52,'Protocol errors, contention, timers, ACK clearing'),(53,58,'Packets, framing, endian and virtual channels'),(59,62,'Processor packet types and frame-synchronized transaction queue'),(63,66,'Stereo VSS fields, EoTp, color/power, generic/DCS commands'),(67,77,'Null/blanking, return size and all YCbCr/RGB packing formats'),(78,80,'Compressed stream, compression mode, PPS, Execute Queue and direction'),(81,86,'Reverse LP, errors, ACK and read response tables'),(87,91,'Video timing modes and peripheral timing requirements'),(92,94,'TE and command/video compression parameters'),(95,102,'Header ECC, payload CRC and reconstructed-image test CRC'),(103,105,'Compliance, resolutions, optional features and interoperability'),(106,111,'Contention recovery tables and state diagrams'),(112,113,'CRC software example and vectors; comment inconsistency noted'),(114,115,'Optional interlaced timing diagrams'),(116,119,'DSC profiles, slice/buffer constraints and PPS timing')]
arasan_topics=[(1,6,'Cover, legal notices, contents and figure/table lists'),(7,8,'CSI background and vendor IP delivery model'),(9,15,'CSI-2 transmitter features, buffering, interfaces and testbench'),(16,24,'CSI-2 receiver formats, data flow, pinout and testbench'),(25,27,'Combo C-PHY/D-PHY architecture and clock distinctions'),(28,29,'Combo PHY power, trim, clock and reset tables'),(30,34,'HS clock, data handshake and first escape controls'),(35,37,'Escape/ULPS, BTA, direction and LP/error controls'),(38,40,'Deskew calibration, sideband, timing counters and deliverables'),(41,44,'Standalone D-PHY capabilities, HS/LP architecture and clocks'),(45,48,'Pad, power, trim, reset and clock PPI tables'),(49,51,'Data HS/escape/control PPI tables'),(52,54,'Direction, swap, DFT, timing-count, BIST tables and deliverables'),(55,55,'Vendor support and licensing statements')]

page_coverage=[]
source_paths={}
local_map=ROOT/'local_source_paths.json'
if local_map.exists():
    source_paths.update(json.loads(local_map.read_text(encoding='utf-8')))
source_paths['arasan_dphy_2019']=str(ROOT/'cache/arasan_dphy_2019.pdf')
for source_id,total,initial,visual,topics in [('local_dsi_v13',119,dsi_initial,dsi_visual,dsi_topics),('arasan_dphy_2019',55,arasan_initial,arasan_visual,arasan_topics)]:
    document=None
    if source_id in source_paths and Path(source_paths[source_id]).is_file():
        import fitz
        document=fitz.open(source_paths[source_id])
    for page in range(1,total+1):
        topic=next(label for first,last,label in topics if first<=page<=last)
        entry=dict(source_id=source_id,pdf_page=page,text_read=True,read_cycle='cycle_001' if page in initial else 'cycle_002',topic=topic,visual_reviewed=page in visual,visual_scope='selected figure/table or page image inspected' if page in visual else 'not visually inspected',record_date_kst=DATE,reader='mipi_dphy_research')
        if document is not None:
            text=document[page-1].get_text()
            entry.update(extracted_text_characters=len(text),extracted_text_sha256=hashlib.sha256(text.encode('utf-8')).hexdigest())
        page_coverage.append(entry)
    if document is not None:
        document.close()

save_jsonl('sources.jsonl',sources)
save_jsonl('claims.jsonl',claims)
save_jsonl('reading_log.jsonl',readings)
save_jsonl('page_reading_coverage.jsonl',page_coverage)
print(json.dumps(dict(sources=len(sources),claims=len(claims),reading_records=len(readings),page_coverage=len(page_coverage),text_pages=dict(DSI=119,Arasan=55),visual_pages=dict(DSI=len(dsi_visual),Arasan=len(arasan_visual))),indent=2))
