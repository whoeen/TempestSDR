"""Refresh vertical-line phase products from saved coherent arrays."""
import json
from pathlib import Path

import numpy as np

import coherent_hsv_resampling as analysis


def main():
    for device in analysis.DEVICES:
        folder = analysis.OUT / device.key
        with np.load(folder / "final_arrays.npz") as saved:
            coherent = saved["coherent"]
            amplitude = saved["amplitude"]
        metadata_path = folder / "metrics.json"
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        rows = analysis.column_phase_analysis(
            device,
            folder,
            coherent,
            amplitude,
            int(metadata["fractional_output_samples_per_raster_cell_k"]),
        )
        metadata["vertical_line_phase_peaks"] = rows
        metadata_path.write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(device.title, "refreshed")


if __name__ == "__main__":
    main()
