# Espressif MIPI DSI guide: full Korean translation

Open `full_translation_ko.html` in a browser. The ten figures, CSS and JavaScript are embedded; network access is not required to read the translation. External citations and supporting relative files remain links.

`full_translation_ko.md` and `assets/` provide an editable version. Original source errors are retained in the translation and corrected in separate annotations.

## Coverage and checks

- All 29 source heading nodes, ten figures, four C examples, eight Common Issues and footer reviewed.
- Four C examples preserve noncomment executable tokens; comments translated.
- MATLAB verifies six header ECC vectors and two payload CRC vectors plus arithmetic. No phone IQ processing or ESP32 build was performed for this document.
- Desktop/mobile layout, image loading, internal TOC and image zoom verified.

## Build

`node build_translation.mjs <absolute-path-to-marked/lib/marked.esm.js>`

If the optional path is omitted, the script imports the installed `marked` package. Source parts are `introduction_ko.md`, `part1_physical_ko.md`, `part2_packets_ko.md`, `part3_driver_ko.md`, and `research_explanation_ko.md`.

See `provenance.json`, `source_coverage.json` and `LICENSE-ESPRESSIF-APACHE-2.0.txt` for provenance, coverage and upstream license. The full original webpage cache and full capture are not Git-tracked. Figure crop coordinates are recorded in `assets/crop_manifest.json`.
