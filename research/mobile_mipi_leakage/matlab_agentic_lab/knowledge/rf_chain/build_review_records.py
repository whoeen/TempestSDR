"""Build RF review records; metadata arithmetic only, no RF device access."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATE = "2026-10-22"

SOURCES = [
    ("rf_mw_supported_r2026b", "https://www.mathworks.com/help/wireless-testbench/gs/supported-sdr-devices.html", "Supported Radio Devices", "R2026b", ["UHD version", "Supported FPGA Image Flavors and Network Interfaces", "USRP X300/X310 Daughterboard Support", "Equivalent National Instruments Radios"]),
    ("rf_mw_capture_r2026b", "https://www.mathworks.com/help/wireless-testbench/ref/basebandreceiver.capture.html", "capture", "R2026b", ["Syntax", "length and UseRadioBuffer", "Output data types and transients", "timestamp", "droppedSamples"]),
    ("rf_mw_host_performance", "https://www.mathworks.com/help/wireless-testbench/ug/evaluate-host-capture-performance.html", "Evaluate Host Capture Performance", "R2026b", ["Introduction", "Configure Behavior When Samples are Dropped", "Evaluate Performance at Multiple Sample Rates"]),
    ("rf_uhd_general", "https://files.ettus.com/manual/page_general.html", "General Application Notes", "4.11.0.0-0-g0d7ed3b1", ["Two-stage tuning", "DSP Tuning", "Sample rate notes", "Master clock rate and Nyquist", "Overflow notes"]),
    ("rf_uhd_sync", "https://files.ettus.com/manual/page_sync.html", "Device Synchronization", "current manual retrieved 2026-10-22", ["Common Reference Signals", "Synchronizing the Device Time", "Align CORDICs in the DSP", "Align LOs in the front-end"]),
    ("rf_murata_cm", "https://www.murata.com/products/emc/emifil/library/knowhow/basic/chapter05-p1", "Conductor conduction and common mode", "retrieved 2026-10-22", ["5-1 Introduction", "5-2-1 cable radiation example", "5-2-3(5) Observation of common mode and normal mode"]),
    ("rf_tek_probe_errors", "https://www.tek.com/en/documents/whitepaper/abcs-probes-primer", "ABCs of Probes Primer", "retrieved 2026-10-22", ["Understanding Difference and Common-mode Signals", "CMRR empirical test", "Minimizing Differential Measurement Errors"]),
]

claims = [
    ("RFC001", "source_fact", "R2026b Wireless Testbench lists UHD 4.9.0.0; local skill instructions assuming 4.6 require revalidation.", ["rf_mw_supported_r2026b"]),
    ("RFC002", "source_fact", "X300/X310 daughterboard support differs: UBX160/OBX160/TwinRX support baseband capture; Other boards including UBX40/WBX/SBX/CBX have Live Data I/O only.", ["rf_mw_supported_r2026b"]),
    ("RFC003", "source_fact", "capture timestamp is the host capture-request datetime, not the hardware first-sample time. droppedSamples is a boolean status, not a lost-sample count.", ["rf_mw_capture_r2026b"]),
    ("RFC004", "source_fact", "Initial capture samples can include radio-path transients. UseRadioBuffer true and false select different integrity/throughput constraints.", ["rf_mw_capture_r2026b", "rf_mw_host_performance"]),
    ("RFC005", "source_fact", "UHD overflow behavior depends on device, transport and mode; the receive metadata reports the event. Continuing data does not prove sample continuity.", ["rf_uhd_general"]),
    ("RFC006", "source_fact", "Common frequency reference, time alignment, timed DSP starts, and analog LO phase calibration address different synchronization requirements.", ["rf_uhd_sync"]),
    ("RFC007", "research_inference", "A receiver's 10 MHz/PPS synchronization does not lock an independent smartphone display oscillator; capture timing/CFO drift remains to be estimated.", ["rf_uhd_sync"]),
    ("RFC008", "source_fact", "A current probe around the relevant complete cable senses net current; ideal opposing normal-mode currents cancel. Probe scope and enclosed return/shield paths matter.", ["rf_murata_cm"]),
    ("RFC009", "source_fact", "Measurement path mismatch and frequency-dependent CMRR create errors; matched probes and symmetric connections are required for mode measurements.", ["rf_tek_probe_errors"]),
    ("RFC010", "research_inference", "An antenna IQ mixture plus low rank is insufficient to identify DSI common mode; calibrated electrical-mode measurements and spatial/control experiments are needed.", ["rf_murata_cm", "rf_tek_probe_errors"]),
    ("RFC011", "local_source_observation", "RawFile casts int16 in host byte order and sends alternating scalar I/Q values. Windows playback requires a separate little-endian copy of the documented big-endian RIS.", ["tempestsdr_rawfile", "rf_local_dataset_inventory"]),
    ("RFC012", "local_source_observation", "RawFile ENABLE_LOOP=1 rewinds at EOF, and callback reports drop=0; replay count is not independent frame count and original acquisition loss is unknown.", ["rf_local_rawfile_loop"]),
    ("RFC013", "local_source_inference", "RawFile's partial EOF read can leave the rest of a fixed-size callback buffer stale/uninitialized. Use complete scalar block exports and exclude replay boundaries; runtime DLL/source identity remains unverified.", ["rf_local_rawfile_loop"]),
    ("RFC014", "derived_calculation", "One sc16 complex stream needs 32*Fs bit/s payload. A 1Gb/s link has an ideal ceiling of 31.25MS/s before overhead, below all four existing reference file sample rates.", ["rf_local_dataset_inventory"]),
    ("RFC015", "derived_calculation", "Small sinusoidal AM index 0.01 produces each first-order sideband at 10log10(0.01^2/4)=-46.0206dBc. Small PM beta=0.01rad has the same first-order result; this is not measured device modulation.", []),
    ("RFC016", "local_metadata_observation", "The antenna files have no embedded Fs. The smartphone rate/BW/fc values in DATASETS.md are external metadata, mostly filenames; actual receiver readback and BW definition are unavailable.", ["rf_local_dataset_inventory"]),
    ("RFC017", "research_design", "Use fixed-duration untriggered captures initially. An energy trigger may select strong clutter rather than weak screen-correlated modulation; establish detection bias before using it.", []),
    ("RFC018", "research_design", "Compare calibrated CM/DM channels, current-probe observations and antenna IQ under controlled pattern/position/brightness changes; a stripe or its low-confidence phase alone does not identify a column driver.", ["rf_murata_cm", "rf_tek_probe_errors"]),
    ("RFC019", "derived_calculation", "exportRisForTempest default 2^20 complex samples is 7.68ms at LG rate, 19.05ms at iPhone6s rate, and 9.46ms at Galaxy111.9 rate; these are too short for multi-frame averaging.", ["rf_local_dataset_inventory", "rf_local_export"]),
]

def jsonl(path, records):
    path.write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in records), encoding="utf-8")

def main():
    source_path = ROOT / "sources.jsonl"
    existing = [json.loads(x) for x in source_path.read_text(encoding="utf-8-sig").splitlines() if x.strip()]
    added = [{"source_id": sid, "url": url, "title": title, "version": version, "kind": "official_documentation", "sections_read": sections, "date": DATE, "coverage": "selected sections only; not entire document"} for sid,url,title,version,sections in SOURCES]
    added += [
        {"source_id":"rf_local_dataset_inventory","path":"research/mobile_mipi_leakage/DATASETS.md","kind":"local_metadata","sections_read":["Smartphone captures","Antenna captures","Binary format"],"date":DATE},
        {"source_id":"rf_local_rawfile_loop","path":"TSDRPlugin_RawFile/src/TSDRPlugin_RawFile.c","kind":"local_source_code","lines":[36,39,198,210,222,230,231,234,251,263],"sections_read":["defines","readasync complete function"],"date":DATE},
        {"source_id":"rf_local_export","path":"research/mobile_mipi_leakage/matlab_agentic_lab/signal_processing/exportRisForTempest.m","kind":"local_source_code","sections_read":["complete function as present during review"],"date":DATE},
    ]
    all_sources = {x["source_id"]:x for x in existing}
    all_sources.update({x["source_id"]:x for x in added})
    jsonl(source_path,list(all_sources.values()))
    jsonl(ROOT / "claims.jsonl", [{"claim_id":i,"kind":k,"claim":c,"source_ids":s,"date":DATE,"status":"proposed_protocol_not_new_rf_measurement" if k=="research_design" else "recorded"} for i,k,c,s in claims])
    jsonl(ROOT / "reading_log.jsonl", [{"source_id":x["source_id"],"date":DATE,"sections_read":x.get("sections_read",[]),"access":"public_web_text" if "url" in x else "local_file","complete_document_read":False if "url" in x else x["source_id"]=="rf_local_export","notes":"Only listed sections were reviewed; no full literature coverage claim."} for x in added])
    rates = [("lgx2_344p8",136565510,60e6),("iphone6s_311",55054870,20e6),("galaxy_s4_111p9",110891050,20e6),("galaxy_s4_171p5",55816790,20e6)]
    budget={"date":DATE,"kind":"derived_calculation_from_external_metadata","not_a_new_measurement":True,"formulae":{"payload_bps":"Fs*32","disk_bytes_s":"Fs*4","default_export_duration_s":"2^20/Fs","one_gbe_ideal_sc16_ceiling_sps":"1e9/32","small_am_per_sideband_dbc":"10*log10(m*m/4)"},"ideal_one_gbe_sps":1e9/32,"am_example_index":0.01,"am_example_per_sideband_dbc":10*math.log10(.01**2/4),"devices":[{"capture_key":k,"stored_fs_hz_filename_metadata":fs,"receiver_bw_hz_filename_metadata":bw,"disk_bytes_s":fs*4,"payload_bps":fs*32,"default_export_duration_s":2**20/fs,"four_second_raw_bytes":fs*4*4} for k,fs,bw in rates]}
    (ROOT/"numerical_budget.json").write_text(json.dumps(budget,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    template=json.loads((ROOT.parents[1]/"tools"/"rf_capture_metadata_template.json").read_text(encoding="utf-8"))
    assert template["status"]=="template_not_a_measurement"
    assert len({c[0] for c in claims})==len(claims)
    for _,_,_,ids in claims:
        assert set(ids).issubset(all_sources)
    print(json.dumps({"sources_total":len(all_sources),"new_review_sources":len(added),"claims":len(claims),"template_json":"valid","rf_device_access":False}))

if __name__ == "__main__":
    main()
