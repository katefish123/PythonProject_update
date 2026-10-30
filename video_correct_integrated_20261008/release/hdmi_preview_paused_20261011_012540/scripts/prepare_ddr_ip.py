#!/usr/bin/env python3
"""Prepare and generate the board-specific Pango Logos2 DDR3 controller IP.

This writes only into rtl/memory/ddr3_ip.  The supplied historical IDF is
used as a parameter template, then its device, package, width, geometry, and
every board-connected DDR pin are replaced before IP Generator is invoked.
"""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TEMPLATE = ROOT / "reference/hdmi_ddr_upstream/ipcore/ddr3_test/ddr3_test.idf"
DEFAULT_PDS = Path(r"C:\pango\PDS_2022.2-SP6.4")
DEFAULT_IP_LIBRARY = (
    DEFAULT_PDS
    / "ip/system_ip/ips2l_hmic_s/ips2l_hmic_eval/ips2l_hmic_s"
)
DEFAULT_GENERATOR = DEFAULT_PDS / "bin/ip_generate.exe"
OUTPUT_DIR = ROOT / "rtl/memory/ddr3_ip"
INSTANCE = "ddr3_ip"


# MES2L676-100HP board DDR3 pin map, taken from desktop_hardware_manual.pdf,
# printed pages 21-23 (PDF pages 25-27). Values are FPGA package ball names.
PIN_MAP = {
    **{f"PAD_A{i}": pin for i, pin in enumerate((
        "J1", "L3", "L2", "P3", "T2", "M1", "U1", "K1", "U2", "K2",
        "T3", "P1", "T4", "M2", "N1",
    ))},
    "PAD_BA0": "P4",
    "PAD_BA1": "R2",
    "PAD_BA2": "T5",
    "PAD_CAS": "T7",
    "PAD_CKN": "U5",
    "PAD_CK": "U6",
    "PAD_CKE": "R1",
    "PAD_CS": "N4",
    "PAD_ODT": "H2",
    "PAD_RAS": "P6",
    "PAD_RESET": "H1",
    "PAD_WE": "T8",
    **{f"PAD_DM{i}": pin for i, pin in enumerate(("K6", "F7", "D5", "E2"))},
    **{f"PAD_DQ{i}": pin for i, pin in enumerate((
        "G5", "J6", "F5", "L8", "G4", "K7", "F4", "J5",
        "H6", "F8", "H8", "D6", "G8", "E6", "H9", "G6",
        "C4", "D4", "A4", "E3", "C3", "F3", "B4", "D3",
        "F2", "D1", "G1", "A2", "E1", "A3", "G2", "C2",
    ))},
    **{f"PAD_DQS{i}": pin for i, pin in enumerate(("J4", "H7", "B5", "C1"))},
    **{f"PAD_DQSN{i}": pin for i, pin in enumerate(("H4", "G7", "A5", "B1"))},
}


PARAMS = {
    # Controller topology: two x16 devices in parallel, one 32-bit rank.
    "MEM_TYPE": "DDR3",
    "OPERATING_MODE": "Controller + PHY",
    "MEM_DQ_WIDTH": "32",
    "MEM_DM_WIDTH": "4",
    "MEM_DQS_WIDTH": "4",
    "MEM_ROW_WIDTH": "15",
    "MEM_COLUMN_WIDTH": "10",
    "MEM_BANK_WIDTH": "3",
    "MEM_ADDR_WIDTH": "15",
    "CTRL_ADDR_WIDTH": "28",
    "DDR3_MEM_ROW_WIDTH": "15",
    "DDR3_MEM_COLUMN_WIDTH": "10",
    "DDR3_MEM_BANK_WIDTH": "3",
    "DDR_MEM_PART": "MT41K256M16XX",
    "DDR3_DFT_MEM_PART": "MT41K256M16XX",
    "DDR3_BASE_MEM_PART": "MT41K256M16XX",
    "CUSTOMIZE_MEM": "false",
    # Board U7 supplies a 125 MHz differential reference; use 1000 MT/s,
    # below the board DRAM's 1066 MT/s limit. Pango UI derives PLL ratios.
    "CLKIN_FREQ": "125.000",
    "DESIRED_RATE": "1000.000",
    "DESIRED_DDR3_RATE": "1000.000",
    "ACTUAL_RATE": "1000.000",
    "DFI_CLK_PERIOD": "8000",
    "STATIC_RATIOI": "1",
    "STATIC_RATIOF": "16",
    "STATIC_RATIO0": "2",
    "DDR3_CL": "7",
    "DDR3_CL_VALUE": "6",
    "DDR3_CWL": "6",
    "DDR3_WR": "4",
    "DDR3_AL": "2",
    "GUI_DDR3_CWL_1066": "6",
    "GUI_DDR3_CL_1066": "7",
    "GUI_DDR3_CWL_800": "5",
    "GUI_DDR3_CL_800": "6",
    "GUI_DDR3_AL": "CL-2",
    "GUI_DDR3_TRFC": "300.000",
    "GUI_DDR3_TRAS": "37.500",
    "GUI_DDR3_TRP": "13.500",
    "GUI_DDR3_TRCD": "13.500",
    "GUI_DDR3_TWR": "15.000",
    "GUI_DDR3_TREFI": "7.800",
    "GUI_DDR3_TRTP": "7.500",
    "GUI_DDR3_TWTR": "7.500",
    "tREFI": "7800",
    "tRFC_MIN": "300000",
    "PHY_TMRD": "4",
    "PHY_TMOD": "12",
    "PHY_TXPR": "39",
    "PHY_TRP": "2",
    "PHY_TRFC": "38",
    "PHY_TRCD": "2",
    "DDRC_T_XP": "4",
    "DDRC_T_FAW": "26",
    "DDRC_T_RAS": "19",
    "DDRC_T_RCD": "7",
    "DDRC_TREFI": "3900",
    "DDRC_TRFC": "150",
    "DDRC_T_RC": "25",
    "DDRC_T_RP": "7",
    "DDRC_T_RRD": "5",
    "DDRC_T_RTP": "4",
    "DDRC_T_WR": "8",
    "DDRC_T_WTR": "4",
    # The IP's bank indices are ordered from the CA bank first, then DQ banks:
    # R5 is BANK0 (CA/PLL reference) and R4 is BANK1 (all four board DQ groups).
    # Keep DQ bank indices at 1 so their clock resources map to the R4 PHY.
    "BANK_CA": "R5",
    "BANK_PLL_REF": "R5",
    "BANK_NUM": "2",
    "BANK0": "R5",
    "BANK1": "R4",
    "BANK2": "L6",  # inactive for this two-bank configuration
    "BANK_DQG_0": "R4",
    "BANK_DQG_1": "R4",
    "BANK_DQG_2": "R4",
    "BANK_DQG_3": "R4",
    "DQ0_BANK_NUM": "1",
    "DQ1_BANK_NUM": "1",
    "DQ2_BANK_NUM": "1",
    "DQ3_BANK_NUM": "1",
    "DQ0_EN": "true",
    "DQ1_EN": "true",
    "DQ2_EN": "true",
    "DQ3_EN": "true",
    "DQ4_EN": "false",
    "DQ5_EN": "false",
    "DQ6_EN": "false",
    "DQ7_EN": "false",
    "DQ8_EN": "false",
    "DEVICE_100H_EN": "true",
    "CS_n_EN": "true",
    "CS_n_En": "true",
    "USER_PINS_CON_EN": "false",
}


def set_value(params: dict[str, ET.Element], name: str, value: str) -> None:
    if name not in params:
        raise ValueError(f"IDF template is missing parameter {name}")
    node = params[name].find("value")
    if node is None:
        node = ET.SubElement(params[name], "value")
    node.text = value


def build_idf(template: Path, idf_out: Path) -> None:
    tree = ET.parse(template)
    root = tree.getroot()
    header = root.find("header")
    if header is None:
        raise ValueError("Template has no IP header")
    header_values = {
        "instance": INSTANCE,
        "family": "Logos2",
        "device": "PG2L100H",
        "package": "FBG676",
        "speedgrade": "-6",
    }
    for key, value in header_values.items():
        node = header.find(key)
        if node is None:
            node = ET.SubElement(header, key)
        node.text = value

    params_node = root.find("param_list")
    if params_node is None:
        raise ValueError("Template has no parameter list")
    params = {p.findtext("name"): p for p in params_node.findall("param")}
    for name, value in PARAMS.items():
        set_value(params, name, value)
    for name, pin in PIN_MAP.items():
        set_value(params, name, pin)

    # Width-dependent flags from the template are explicit so no 200H-only
    # 72-bit lanes can accidentally become active in the generated 32-bit IP.
    for name in (
        "DQ4_EN", "DQ5_EN", "DQ6_EN", "DQ7_EN", "DQ8_EN",
        "A15_EN", "A15_DQS_EN", "DQ4_BANK_NUM", "DQ5_BANK_NUM",
        "DQ6_BANK_NUM", "DQ7_BANK_NUM", "DQ8_BANK_NUM",
    ):
        if name in params:
            set_value(params, name, "false" if name.endswith("_EN") else "0")

    # Preserve only board-valid active data/control pins in the generated
    # signal-width arrays. Unused PAD_DQ/DQS/DM fields remain inactive by width.
    ET.indent(tree, space="    ")
    idf_out.write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))


def validate_generated(idf_path: Path) -> None:
    root = ET.parse(idf_path).getroot()
    header = root.find("header")
    params_node = root.find("param_list")
    assert header is not None and params_node is not None
    values = {p.findtext("name"): p.findtext("value") for p in params_node.findall("param")}
    expected_header = {"family": "Logos2", "device": "PG2L100H", "package": "FBG676", "speedgrade": "-6"}
    for key, expected in expected_header.items():
        if header.findtext(key) != expected:
            raise ValueError(f"Target mismatch: {key}={header.findtext(key)!r}, expected {expected!r}")
    for name, expected in {**PARAMS, **PIN_MAP}.items():
        if values.get(name) != expected:
            raise ValueError(f"Parameter mismatch: {name}={values.get(name)!r}, expected {expected!r}")
    used_pins = [values[name] for name in PIN_MAP]
    if len(used_pins) != len(set(used_pins)):
        raise ValueError("The official board pin map contains duplicate package balls")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--ip-library", type=Path, default=DEFAULT_IP_LIBRARY)
    parser.add_argument("--generator", type=Path, default=DEFAULT_GENERATOR)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--prepare-only", action="store_true", help="write and validate the target IDF without running IP Generator")
    args = parser.parse_args()

    template = args.template.resolve(strict=True)
    library = args.ip_library.resolve(strict=True)
    generator = args.generator.resolve(strict=True)
    output_dir = args.output_dir.resolve()
    allowed_root = OUTPUT_DIR.resolve()
    if output_dir != allowed_root:
        parser.error(f"output-dir is fixed to the authorized path: {allowed_root}")
    if not (library / "index.xml").is_file():
        parser.error(f"IP library index not found under {library}")
    idf_path = output_dir / f"{INSTANCE}.idf"
    output_dir.mkdir(parents=True, exist_ok=True)

    build_idf(template, idf_path)
    validate_generated(idf_path)
    print(f"Template SHA256: {hashlib.sha256(template.read_bytes()).hexdigest()}")
    print(f"Prepared target IDF: {idf_path}")
    print("Target: Logos2 PG2L100H / -6 / FBG676; DDR3 32-bit; 125 MHz reference; 1000 MT/s")
    print("Geometry: row=15, bank=3, column=10; address width=28")
    print(f"Board-connected DDR pins: {len(PIN_MAP)} unique locations")

    if args.prepare_only:
        return 0

    command = [
        str(generator), "-i", str(idf_path), "-m", str(library),
        "-family", "Logos2", "-device", "PG2L100H", "-pack", "FBG676",
        "-speed", "-6", "-disable-syn", "-verbose",
    ]
    log_path = output_dir / "ip_generate.log"
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        result = subprocess.run(command, cwd=output_dir, stdout=log, stderr=subprocess.STDOUT, check=False)
    print(f"IP Generator exit code: {result.returncode}; log: {log_path}")
    if result.returncode != 0:
        print(log_path.read_text(encoding="utf-8", errors="replace"), file=sys.stderr)
        return result.returncode

    outputs = [p for p in output_dir.rglob("*") if p.is_file()]
    generated_wrappers = [p for p in outputs if p.name in {f"{INSTANCE}.v", f"{INSTANCE}_tmpl.v"}]
    if not generated_wrappers:
        print("IP Generator returned success but no instance wrapper/template was found", file=sys.stderr)
        return 2
    print("Generated files:")
    for path in generated_wrappers:
        print(f"  {path.relative_to(output_dir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
