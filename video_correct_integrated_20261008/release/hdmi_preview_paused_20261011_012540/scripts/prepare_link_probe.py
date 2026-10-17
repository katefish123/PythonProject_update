"""Prepare an isolated Pango build for the DDR-independent HDMI link probe."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results" / "hdmi_link_probe"
TOP = "hdmi_link_probe_top"


def main() -> None:
    base = (ROOT / "constr" / "board_bram.fdc").read_text(encoding="utf-8-sig")
    valid_ports = {
        "sys_clk_27m", "rst_n", "hd_rx_pclk", "hd_rx_vs", "hd_rx_hs", "hd_rx_de",
        "hd_rx_data[0]", "hd_rx_data[1]", "hd_rx_data[2]", "hd_rx_data[3]",
        "hd_rx_data[4]", "hd_rx_data[5]", "hd_rx_data[6]", "hd_rx_data[7]",
        "hd_rx_data[8]", "hd_rx_data[9]", "hd_rx_data[10]", "hd_rx_data[11]",
        "hd_rx_data[12]", "hd_rx_data[13]", "hd_rx_data[14]", "hd_rx_data[15]",
        "hd_rx_data[16]", "hd_rx_data[17]", "hd_rx_data[18]", "hd_rx_data[19]",
        "hd_rx_data[20]", "hd_rx_data[21]", "hd_rx_data[22]", "hd_rx_data[23]",
        "hd_tx_pclk", "hd_tx_vs", "hd_tx_hs", "hd_tx_de",
        *{f"hd_tx_data[{i}]" for i in range(24)}, "hd_reset_n", "hd_scl", "hd_sda",
        *{f"led[{i}]" for i in range(8)},
    }

    kept: list[str] = []
    for line in base.splitlines():
        if line.startswith("define_attribute {p:"):
            match = re.match(r"define_attribute \{p:(.+?)\} ", line)
            if match and match.group(1) in valid_ports:
                kept.append(line)
            continue
        if line.startswith("set_false_path -from [get_ports {hd_sda}"):
            kept.append(line)
            continue
        if line.startswith("set_false_path -from [get_ports"):
            kept.append("set_false_path -from [get_ports {rst_n}]")
            continue
        if line.startswith("set_false_path -to [get_ports"):
            kept.append("set_false_path -to [get_ports {led[*] hd_reset_n hd_scl hd_sda}]")
            continue
        kept.append(line)

    constraint = OUT / "hdmi_link_probe.fdc"
    OUT.mkdir(parents=True, exist_ok=True)
    constraint.write_text("\n".join(kept) + "\n", encoding="utf-8")
    decoder = """HDMI link probe status-bar decoder

The bottom 40 active picture lines are split into four 10-line bands. Each
band has 15 cells across the 1920-pixel width; each cell is 128 pixels wide.
Read cells left-to-right, then bands top-to-bottom. Green (00B000) means 1;
red (B00000) means 0. The stream is MSB-first for this 60-bit word:

  bit 59       initDone = rx_done && tx_done
  bit 58       ackError
  bit 57       rxclockSeen
  bit 56       deSeen
  bits 55:40   rxWidth: pixel count of the most recently completed DE line
  bits 39:24   rxHeight: HS rising-edge count since the latest VS rising edge
                or reset. If VS is absent, this keeps increasing (saturating
                at 65535), so zero is not used to imply no clock/DE.
  bits 23:0    sampleRGB: latest RGB sample captured while DE was high

rxWidth, rxHeight, and sampleRGB are captured in the RX pixel-clock domain and
synchronized to the 148.5 MHz display domain. Status bits cross from their
respective controller/clock domains. rxclockSeen and deSeen are sticky until reset.
The 60 cells are grouped as bits 59:45, 44:30, 29:15, and 14:0.

LEDs are ordered [7:0]: rxclockSeen, ackError, deSeen, tx_done, rx_done,
configPLL lock, videoPLL lock, 27 MHz heartbeat.
"""
    (OUT / "debug_decoder.txt").write_text(decoder, encoding="utf-8")

    # Assert exact pin-attribute coverage for each live port, with no key pins.
    constrained = {
        match.group(1)
        for line in kept
        if (match := re.match(r"define_attribute \{p:(.+?)\} \{PAP_IO_DIRECTION\}", line))
    }
    missing = valid_ports - constrained
    if missing:
        raise RuntimeError(f"Missing board pin constraints: {sorted(missing)}")
    if any("key1_pattern_n" in line or "key2_nearest_n" in line for line in kept):
        raise RuntimeError("Unused key ports unexpectedly survived FDC filtering")

    sources = [
        ROOT / "rtl/top/hdmi_link_probe_top.v",
        ROOT / "rtl/common/reset_sync.v",
        ROOT / "rtl/hdmi/hdmi_config.v",
        ROOT / "rtl/hdmi/ms7200_ctl.v",
        ROOT / "rtl/hdmi/ms7210_ctl.v",
        ROOT / "rtl/hdmi/iic_dri.v",
        ROOT / "vendor/c_current/01_design_code/video_timing_vtc.v",
        ROOT / "vendor/c_current/01_design_code/ip/video_pll_27m_148m5/video_pll_27m_148m5.v",
        ROOT / "vendor/c_current/01_design_code/ip/config_pll_27m_10m/config_pll_27m_10m.v",
    ]
    for source in sources:
        if not source.is_file():
            raise FileNotFoundError(source)

    flow = ["set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676"]
    flow.extend(f"add_design {{{source.as_posix()}}}" for source in sources)
    flow.extend([
        f"add_constraint -logic -fdc {{{constraint.as_posix()}}}",
        f"compile -top_module {TOP}",
        "synthesize -ads",
        "dev_map",
        "pnr",
        "report_timing",
        "gen_bit_stream",
    ])
    (OUT / "build_hdmi_link_probe.tcl").write_text("\n".join(flow) + "\n", encoding="utf-8")
    print(f"Prepared isolated probe build with {len(sources)} HDL sources and {len(constrained)} constrained pins.")
    print(f"Generated FDC: {constraint}")
    print(f"Generated PDS flow: {OUT / 'build_hdmi_link_probe.tcl'}")


if __name__ == "__main__":
    main()
