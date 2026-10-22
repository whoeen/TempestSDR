# MATLAB smartphone leakage research laboratory

## Status — 2026-10-22

This is the MATLAB migration of the existing three-device research workflow.
The original RIS captures remain unchanged. The cloud raw-data release remains
[mobile-mipi-raw-iq-2026-10-21](https://github.com/whoeen/TempestSDR/releases/tag/mobile-mipi-raw-iq-2026-10-21).

- Official MATLAB MCP v0.15.0 downloaded and release digests verified.
- Codex user configuration backed up before registering the server.
- MCP initialize and five tool schemas verified by real JSON-RPC communication.
- Core, signal processing, radar, wireless and selected testing/chart skills registered (37).
- MATLAB R2026b installation contains MATLAB and MATLAB Copilot according to local product metadata.
- MATLAB R2026b execution is verified through the official MCP. The licensed baseline passed 11/11 numerical tests and processed LG X2, iPhone 6s and Galaxy S4 LTE.
  See [measured baseline report](results/licensed_baseline_20261022/REPORT_KO.md). These are distinct from actual iPhone 6 captures.
- Portable Java 8 and existing TempestSDR JAR prepared; TempestSDR GUI was observed
  by process window title and Responding=true. Hardware capture has not been performed.
- Codex Document Control reported no connected document sessions. The MATLAB
  MCP connection is a separate integration; no document-control connection is claimed.

## Stitching research — 2026-10-22

O’Connell’s 155-page thesis has been read in full text, with 36 selected pages checked visually.
[Reading record and MATLAB equation audit](knowledge/stitching/README.md) ·
[LG X2 / iPhone 6 measurement plan](knowledge/stitching/MEASUREMENT_PLAN_KO.md) ·
[Capture metadata template](knowledge/stitching/capture_metadata.template.json).
New RF acquisition and measured mobile stitching have not yet been performed.

## Four research roles

| Role | Persistent ownership | Current work |
|---|---|---|
| MIPI DSI / D-PHY | knowledge/mipi_dphy | Protocol timing, packet/lane mapping, public A7 kernel configuration, local specification reading |
| Compromising emanations | knowledge/tempest | Original papers, corrected equations, HDMI/CSI/DSI transfer limits |
| RF signal processing | signal_processing + knowledge/signal_processing | Read-only IQ, diagnostics, time-frequency, phase, fractional alignment, averages, tests |
| SDR / RF chain | knowledge/rf_chain | Hardware inventory, receive-only measurement recipe, clock/gain/overflow controls |

Agents are separate working sessions, not permanently running models.
Their sources, claims, exact reading coverage, scripts and run notes persist on disk.
A source is not marked fully read when only an abstract, selected pages or OCR was checked.

## Start the interactive laboratory

From PowerShell:
```powershell
& .\tools\start_matlab_lab.ps1
```

Complete the MathWorks sign-in/licensing prompts in the MATLAB window.
The start script installs the downloaded official MCP Server Toolbox if missing,
runs shareMATLABSession, saves inventory, enables a diary, and opens labWorkbench.m.
If a desktop was already open without this script, run:
```matlab
run("C:/Users/leechanghoon/Documents/Codex/2026-09-21/snr-svd/tempestsdr-cloud/research/mobile_mipi_leakage/matlab_agentic_lab/startLab.m")
```
Codex may need a fresh session to load newly registered MCP tools/skills.
The official server is configured with session-mode auto to attach to the most
recently shared MATLAB session. Avoid parallel MATLAB execution from several
agents: one execution owner serializes calls; other roles review the files.

Setup follows [MathWorks MCP documentation](https://github.com/matlab/matlab-mcp-server)
and [Codex MCP configuration](https://developers.openai.com/codex/mcp).
The configured short log path avoids a verified Windows socket-path-length failure.
Tool timeout is 600 s, startup timeout 120 s, and WINDIR is forwarded.

## First execution after startup

```matlab
addpath(fullfile(pwd,"signal_processing"));
results = runtests("signal_processing/testMobileBaseline.m");
assert(all([results.Passed]),"Baseline tests failed.");
summary = runMobileBaseline();
```

Read signal_processing/README.md before running large experiments.
The bounded default covers LG X2 344.8 MHz, iPhone 6s 311 MHz, and Galaxy S4 LTE
111.9 MHz captures with explicit historical raster timing hypotheses.
Fs, receiver bandwidth, and RF center are separate metadata fields.
Phase/HSV images are relative RF phase displays, not recovered display RGB.
Parameters from older reconstruction work remain labelled prior fits, not new measurements.
The initial module compares nearest/fractional interpolation and multiple coherent controls;
it does not claim that RPCA or a target matched subspace has already identified DSI emission.

## Research database and notes

Source/claim/read-log JSONL files are the source of truth.
SQLite FTS is a rebuildable search index; full copyrighted PDFs and extracted
full text remain local caches excluded from Git.

```powershell
python tools/index_knowledge.py
python tools/index_knowledge.py --query 'DDR'
python tools/index_knowledge.py --query 'banding'
```

Each experiment must retain source identity, byte/sample range, endian, Fs,
gain/bandwidth when known, code revision, parameters, intermediate figures,
measured metrics, failure/skipped status, and the next hypothesis.
Raw captures use big-endian signed int16 interleaved I,Q (4 bytes/complex sample).
No quality claim is based only on signal power, rank, visual attractiveness or
coherence: stable clutter can improve all of those.

## TempestSDR baseline

```powershell
& .\tools\start_tempestsdr.ps1
```

The Windows raw-file plugin uses native endianness. Convert a bounded copy using
exportRisForTempest before loading big-endian RIS as int16.
The output sidecar records exactly which samples and conversion were used.
Keep complex raw IQ for the MATLAB coherent AM/PM analysis.

## Immediate research order

1. Complete MATLAB startup and execute numerical tests.
2. Run three-device baseline; inspect every intermediate stage and shared display scales.
3. Validate fh/fv candidates, packet/burst timing, and integer vs fractional drift on held-out frames.
4. Compare coherent/no-phase/global-phase/row-phase accumulation; retain mixture-phase caveats.
5. Use independent reference patterns/positions for clutter cancellation and target subspaces.
6. Test RPCA only after checking what low-rank and sparse assumptions mean for the chosen matrix.
7. Advance to A7(2018) or newer devices after repeatable measured image-content improvement.

Measurement hardware model, connection, antenna and LNA details are still requested.
No firmware, network MTU, radio gain, or transmission was changed.
