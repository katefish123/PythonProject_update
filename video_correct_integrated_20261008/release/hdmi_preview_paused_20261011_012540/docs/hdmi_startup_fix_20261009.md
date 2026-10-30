# HDMI startup NACK handling

The board wrappers now separate the raw I2C history from fatal configuration
failure. `iic_dri.ack_error` remains sticky for every sampled NACK. Its new
`nack_pulse` marks each NACK slot, while START-latched transaction fields and
`transaction_nack` preserve the device, address, direction, controller owner,
and whether any byte in that transaction NACKed.

`hdmi_config` waits `POST_RESET_SETTLE_CYCLES` before releasing either
configuration controller or the I2C master. The default is 100,000 cfg-clock
cycles (10 ms at 10 MHz). It records per-controller probe completion only
after a complete, NACK-free read of register 0x0003 returns 0x5A. A NACK on
register 0x0003 before that controller's verified read sets
`startup_retry_seen`, allowing the vendor CONECT retry loop to continue. Every
other NACK sets sticky `config_error`; in particular the later INIT write
0x0003=0xC3 remains fatal after probe completion.

The TX and BRAM board wrappers now initialize TX first so its fallback output
can run before RX becomes available. Video readiness still requires both
controller completion flags and no fatal configuration error. DDR/BIST
readiness and fault gates are unchanged. The raw sticky NACK remains available
for diagnostics and does not by itself suppress ready after a successful
startup retry.

The I2C driver's `trans_en`, `twr_en`, `twr_cnt`, and `busy` now reset with its
active reset. This clears any in-flight clocking or write-delay state during
the 10 ms settling interval, ensuring the bus stays idle and repeated resets
start from a clean transaction boundary.

Validation: `scripts/run_hdmi_config_tests.ps1` passed with both
`TX_FIRST=0` and `TX_FIRST=1`, covering normal initialization, recovery from a
bootstrap scratch NACK, a fatal post-probe NACK on 0x0003=0xC3, reset and
reinitialization, and missing-device behavior. The missing-device case keeps
raw `ack_error` high, both done flags low, and `config_error` low while the
controller continues its scratch retry. The strict SCL-rising-edge I2C model
also still passes the `B2 03 00 B3` read sequence test. Logs are in
`results/hdmi_startup_fix/`.

Before editing the main HDL, original HDMI drivers and both board tops were
copied to `reference/baselines/ddr_before_hdmi_startup_fix/rtl/`; the same
HDMI driver set was copied to `diagnostics/internal_fixture/baseline/rtl/hdmi/`.
No new synthesis module was added, so existing explicit source lists already
cover the modified `hdmi_config.v` and `iic_dri.v`.
