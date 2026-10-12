"""Prepare a separate TX-first HDMI link probe with first-NACK telemetry."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results" / "hdmi_link_i2c_probe"
TOP = "hdmi_link_i2c_probe_top"

PORTS = {
    "sys_clk_27m", "rst_n", "hd_rx_pclk", "hd_rx_vs", "hd_rx_hs", "hd_rx_de",
    *{f"hd_rx_data[{i}]" for i in range(24)}, "hd_tx_pclk", "hd_tx_vs", "hd_tx_hs", "hd_tx_de",
    *{f"hd_tx_data[{i}]" for i in range(24)}, "hd_reset_n", "hd_scl", "hd_sda",
    *{f"led[{i}]" for i in range(8)},
}


def main() -> None:
    base = (ROOT / "constr" / "board_bram.fdc").read_text(encoding="utf-8-sig")
    kept = []
    for line in base.splitlines():
        if line.startswith("define_attribute {p:"):
            match = re.match(r"define_attribute \{p:(.+?)\} ", line)
            if match and match.group(1) in PORTS:
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

    OUT.mkdir(parents=True, exist_ok=True)
    fdc = OUT / "hdmi_link_i2c_probe.fdc"
    fdc.write_text("\n".join(kept) + "\n", encoding="utf-8")
    constrained = {
        m.group(1) for line in kept
        if (m := re.match(r"define_attribute \{p:(.+?)\} \{PAP_IO_DIRECTION\}", line))
    }
    if constrained != PORTS:
        raise RuntimeError(f"Pin constraint mismatch; missing={sorted(PORTS-constrained)}, extra={sorted(constrained-PORTS)}")
    if any("key1_pattern_n" in line or "key2_nearest_n" in line for line in kept):
        raise RuntimeError("Unused key pins unexpectedly survived FDC filtering")

    sources = [
        ROOT / "rtl/top/hdmi_link_i2c_probe_top.v",
        ROOT / "rtl/common/reset_sync.v",
        ROOT / "rtl/hdmi/diag/hdmi_config_diag.v",
        ROOT / "rtl/hdmi/diag/iic_dri_diag.v",
        ROOT / "rtl/hdmi/ms7200_ctl.v",
        ROOT / "rtl/hdmi/ms7210_ctl.v",
        ROOT / "vendor/c_current/01_design_code/video_timing_vtc.v",
        ROOT / "vendor/c_current/01_design_code/ip/video_pll_27m_148m5/video_pll_27m_148m5.v",
        ROOT / "vendor/c_current/01_design_code/ip/config_pll_27m_10m/config_pll_27m_10m.v",
    ]
    for source in sources:
        if not source.is_file():
            raise FileNotFoundError(source)

    flow = ["set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676"]
    flow += [f"add_design {{{p.as_posix()}}}" for p in sources]
    flow += [
        f"add_constraint -logic -fdc {{{fdc.as_posix()}}}",
        f"compile -top_module {TOP}", "synthesize -ads", "dev_map", "pnr", "report_timing", "gen_bit_stream",
    ]
    (OUT / "build_hdmi_link_i2c_probe.tcl").write_text("\n".join(flow) + "\n", encoding="utf-8")

    decoder = """HDMI link I2C diagnostic status-bar decoder

The bottom 80 active lines hold an 8-row x 15-column grid. Each cell is 128
pixels wide and 10 lines tall. Read left-to-right, then top-to-bottom. Green
(00B000)=1; red (B00000)=0. The 120 displayed bits are MSB-first:

  119:21 status payload (99 bits, decoded below); 20:0 zero padding
   98 tx_done                97 rx_done
   96 sticky ack_error       95 first_nack_valid
   94:87 first_nack_device   (B2=TX/MS7210, 56=RX/MS7200; full 8-bit byte)
   86:71 first_nack_addr     (live controller address sampled at NACK; late
                              data-byte ACK may reflect the next command)
   70:68 first_nack_state    (I2C FSM state; 3=S_ACK)
   67:63 first_nack_byte     (1=device ID ACK, 2=low addr, 3=high addr, 4=data
                               for 16-bit register writes; read has repeated
                               START/device-read byte after address)
   62 first_nack_write       (1=write transaction, 0=read transaction)
   61 first_nack_owner_tx    (1=TX controller, 0=RX controller)
   60:59 sampled SDA         (00=low, 10=high, 11=X/Z)
  58 sampled SCL
  57 rxclockSeen             56 deSeen
  55:40 latest completed DE line width in pixels
  39:24 HS-pulse count since the last VS edge (total line count, not active
       image height; 1080p59.94 typically totals 1125; if VS is absent it keeps
       advancing and must not be interpreted as active height)
  23:0 latest RGB sample captured during DE

The entire word is frame-latched at the TX VS rising edge to keep all fields
static for each displayed frame. Decode by shifting the 120-bit raw word right
21 bits before extracting the 99-bit payload. The first NACK fields are sticky
until reset. `trans_byte` advances before its ACK slot, so the displayed ACK
index is one-based. ACK error also remains sticky. V2 adds START-latched
transaction context and ACK/NACK slot counts.
LED[7:0] = rxclockSeen, ackError, deSeen, tx_done, rx_done, cfgPLL lock,
videoPLL lock, 27 MHz heartbeat.
"""
    (OUT / "debug_decoder.txt").write_text(decoder, encoding="utf-8")
    print(f"Prepared isolated first-NACK build with {len(sources)} HDL sources and {len(constrained)} pins.")
    print(f"FDC: {fdc}")
    print(f"PDS flow: {OUT / 'build_hdmi_link_i2c_probe.tcl'}")


if __name__ == "__main__":
    main()
