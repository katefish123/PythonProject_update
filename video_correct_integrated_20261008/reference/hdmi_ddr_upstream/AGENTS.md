# Repository Guidelines

## Project Structure & Module Organization
This repository is a Pango/Fabric Compiler FPGA design for HDMI input, DDR3 frame buffering, YCbCr/image processing, and HDMI output. Main RTL lives in `source/rtl/`, with the top module in `source/rtl/HDMI_IN_DDR3_YCbCr_top.v`. HDMI device control logic is in `source/hdmi/`, image conversion logic is in `source/img_process/`, and ROI/target-analysis modules are under `source/rtl/Target_Analysis_Top/`. Vendor IP and generated wrappers are kept in `ipcore/` and the `rd_fram_buf`/`wr_fram_buf` subtrees. Simulation assets and testbenches live in `sim_prj/img_ycbcr_sim_prj/sim/`. Constraint and project entry files are `HDMI_IN_DDR3_YCbCr_top.fdc`, `HDMI_IN_DDR3_YCbCr.pds`, and `impl.tcl`.

## Build, Test, and Development Commands
Use Pango Design Suite/Fabric Compiler 2022.2-SP6.4 or a compatible version. Open `HDMI_IN_DDR3_YCbCr.pds` in PDS for interactive work. For scripted implementation, run the flow in `impl.tcl`, which performs `compile`, `synthesize`, `dev_map`, `pnr`, `report_timing`, and `gen_bit_stream`. Review `run.log`, `pds.log`, `report_timing/`, and `generate_bitstream/` after each build.

## Coding Style & Naming Conventions
Use Verilog/SystemVerilog style already present in `source/`: 4-space indentation, aligned port lists, uppercase parameters such as `H_ACT`, and `snake_case` signals/modules. Use `_n` for active-low resets and `u_*` for instances, for example `u_RGB2YCbCr`. Keep clock-domain and reset behavior explicit when touching DDR, HDMI, or frame-buffer paths.

## Testing Guidelines
Place testbenches near the relevant simulation project or IP folder, using names like `*_tb.v` or `*_tb.sv`. Existing examples include `img_process_tb.sv`, `rd_fram_buf_tb.v`, and `wr_fram_buf_tb.v`. For image-processing changes, update or regenerate vectors in `sim_prj/img_ycbcr_sim_prj/sim/` and compare `img_process.txt` output. For top-level changes, run at least compile/synthesis and check timing reports.

## Commit & Pull Request Guidelines
History currently contains only `Init`; use short imperative commit subjects such as `Add ROI edge scoring` or `Fix HDMI reset sequencing`. Pull requests should describe the hardware path affected, list changed modules, mention any regenerated IP or constraints, and include simulation/build evidence with relevant log or timing summaries.
