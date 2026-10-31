"""Export a validated profile to signed Verilog constants and metadata JSON."""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
from brect.calibration import load_calibration


def export(calibration, output_prefix):
    profile = load_calibration(calibration)
    hardware = profile.to_hardware()
    prefix = Path(output_prefix)
    verilog_path, json_path = Path(str(prefix) + ".vh"), Path(str(prefix) + ".hardware.json")
    verilog = ["// Generated from validated camera calibration; signed 32-bit constants.",
               "// Trial/deployment status is retained in the companion .hardware.json.",
               "// This export does not authorize physical optical deployment.",
               "`ifndef BRECT_LENS_PROFILE_VH", "`define BRECT_LENS_PROFILE_VH"]
    for key, value in hardware.items():
        verilog.append(f"`define LENS_{key} 32'sh{value & 0xffffffff:08x} // {value}")
    verilog.extend(["`endif", ""])
    document = {"source_profile_name": Path(calibration).name,
                "image_size": {"width": profile.width, "height": profile.height},
                "parameters": hardware, "calibration_metadata": profile.metadata,
                "constant_format": {"intrinsics": "signed32 Q16", "reciprocal_focal": "signed32 Q30",
                                    "distortion": "signed32 Q26", "rounding": "nearest, ties away from zero"},
                "deployment_note": "Compile-time export preserves provisional status; no runtime transport or board validation is implied."}
    prefix.parent.mkdir(parents=True, exist_ok=True)
    verilog_path.write_text("\n".join(verilog), encoding="utf-8")
    json_path.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return verilog_path, json_path


def main(argv=None):
    parser = argparse.ArgumentParser(description="Export k1/k2/p1/p2 profile to .vh and .hardware.json")
    parser.add_argument("--calibration", required=True)
    parser.add_argument("--output-prefix", required=True, help="Output path prefix, without .vh/.hardware.json")
    args = parser.parse_args(argv)
    try:
        paths = export(args.calibration, args.output_prefix)
    except (OSError, ValueError, TypeError) as error:
        parser.exit(2, f"export_calibration: {error}\n")
    for path in paths:
        print(path)


if __name__ == "__main__":
    main()
