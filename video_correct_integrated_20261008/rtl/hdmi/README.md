# HDMI MS72xx configuration sources

`hdmi_config.v` is the board-facing wrapper. It supports either controller
ordering, waits for the current I2C transaction to finish before handing off
the shared bus, and drives SDA low or releases it. `ack_error` keeps the raw
sticky NACK history. `startup_retry_seen` records recoverable pre-probe NACKs;
`config_error` is the fatal sticky gate used by the board tops. The only
recoverable case is a NACK during the pre-probe 0x0003 scratch transaction.
After a successful 0x0003 read returns 0x5A with no NACK in that transaction,
all later NACKs are fatal, including the later 0x0003=0xC3 initialization
write. A missing device therefore keeps `ack_error` high and `rx_done` or
`tx_done` low without reporting a false initialization success.

The wrapper holds its controllers and I2C driver in reset for
`POST_RESET_SETTLE_CYCLES` after external reset is released. Its default is
`CLK_FRE/100`, which is 100,000 cfg-clock cycles (10 ms at 10 MHz). Both board
tops use TX-first initialization so the HDMI transmitter can start its
fallback output before the receiver is available. Processing readiness still
requires `rx_done && tx_done && !config_error`; the DDR/BIST gate is unchanged.

`ms7200_ctl.v` is derived locally from the separately obtained RX reference at
`reference/hdmi_ddr_upstream/source/hdmi/ms7200_ctl.v` (source SHA-256
`67874f14e07601f1a7f50e967d0e4400e03c1fdd4f394d1f9cf0106638a215f7`). The
source's license was not verified. The derivation applied the three checked-in
`vendor/c_current/tools/prepare_local_*.py` transformations: the initialized
input detection fix, RGB-only EDID bytes (`0D83=C0`, `0DFF=D8`), and a read-only
`0x1281` pixel-format probe. Original comments and attribution are retained.
Do not represent this RX source as original team work or publish it without
resolving its license.

`ms7210_ctl.v` and `iic_dri.v` originate from the upstream project and commit
recorded in `MS7210_SOURCE.md`; the license text is included. `iic_dri.v`
retains sticky `ack_error` and adds a one-cycle `nack_pulse`, START-latched
device/address/direction/owner fields, and a transaction-level NACK flag that
clears at the next START. These let the wrapper classify a whole scratch read
without confusing it with the controller's next live command fields.

Run `scripts/run_hdmi_config_tests.ps1` to test both handoff orders, normal
initialization, a recoverable bootstrap NACK followed by a successful scratch
probe, a fatal post-probe NACK on the 0x0003=0xC3 write, reset/reinitialization,
and missing-device behavior. Initialization outputs mean the respective
controller reached its completion state; they do not prove physical HDMI
display lock.
