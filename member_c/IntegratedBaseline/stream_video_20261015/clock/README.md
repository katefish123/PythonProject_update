# Native vendor PLL54 verification

This test compiles the actual installed PDS simulation primitive:
D:/softwares/PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation/GTP_GPLL.v.
There is no PLL stub or hand-written clock multiplier.

video_pll_clock_test.v is a local copy of the baseline generated video PLL wrapper.
Changes are limited to module name, adding output clkout54 and connecting the
previously open native CLKOUTF pin. All generated parameters remain unchanged:
input27MHz, STATIC_RATIOI1, STATIC_RATIOM2, STATIC_RATIOF13.75,
STATIC_RATIO0=5.0 and INTERNAL_FB=CLKOUTF.
Original vendor wrapper and primitive files were not modified.

Run run_tests.ps1 -Suffix <unique>. Logs and source SHA256 records are written to
D:/FPGA/output/c_vendor_pll54_20261015_<unique>.
The bench drives27MHz, waits for native LOCK, waits another64 input periods,
then measures4096 complete rising-edge periods independently on both outputs.
With1fs simulation resolution, fresh green_native54 run measured:

- LOCK asserted462.962975000ns.
- CLKOUT0 mean period6.734006667ns, frequency148.500001483MHz.
- CLKOUTF mean period18.518519123ns, frequency53.999998236MHz.
- CLKOUTF min/max periods18.518518000/18.518520000ns.
- Compile and simulation: zero errors, zero warnings.

The proposed18.518519ns processing-clock constraint matches this native model.
This verifies functional model frequency/binding, not device clock routing, PDS
static timing closure, physical jitter or board measurement.

Before the valid hookup, a deliberate test copy connected clkout54 to pixel
CLKOUT0. The same bench failed the54MHz assertion with measured148.500001483MHz
(red_wrong_binding log). The valid copy then passed both output measurements.
