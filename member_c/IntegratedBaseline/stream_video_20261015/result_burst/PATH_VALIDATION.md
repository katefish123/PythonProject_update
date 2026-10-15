# Combined correction path with64word result bursts

c_stream_burst_correction_path is a separate copy of the root correction wrapper. It uses the current processor and v2 descriptor bridge/tile cache, unchanged B mathematics, ddr_result_writer_burst64 and ddr_word_engine_result_burst. Root production modules were not edited.

The wrapper retains the root interface and adds output cmd_result_block and output result_block_data[2047:0]. Selected writer grant qualifies cmd_result_block=cmd_valid&&w_valid&&w_blockflag. Source-block reads retain cmd_valid&&!w_valid. Result payload remains separate from capture payload. Retained arbiter ownership qualifies responses, and publication waits until every owned result block response crosses back to the processing domain.

Run run_path_tests.ps1 with -Full -Solver and optionally -Nearest; reduced cases omit -Full and may add -AbortTest. It captures hashes before compilation and after simulation, rejecting any source drift. The native AXI model supports independent AW/AR/W stalls, gapped source read beats and AW/W consumption on the same edge. Every accepted result command must produce aligned64word AWLEN7; every WREADY advances by8words and is checked against independent expected RGB/padding/strobes. Each complete result RAM is read back before publication passes. No source image RAM is duplicated: source RGB comes from each native word address and independent pattern seed.

Fresh verified runs:

| Run | Complete publications | Native stored pixels/frame | Result commands/frame | W beats/frame | Result ACKs/frame | Start-to-publication |
|---|---:|---:|---:|---:|---:|---:|
| Full solver bilinear |3|829440|12960|103680|12960|15.379792–15.379829ms|
| Full solver nearest |3|829440|12960|103680|12960|15.377051–15.377144ms|
| Reduced bilinear with abort |4|1536|24|192|24|about40.96us|
| Reduced nearest with abort |4|1536|24|192|24|about40.7us|

Full runs use native1920x1080 source, stored768x1080 output and active765x1080 corrected region with physical black padding1left/2right, three distinct source pattern seeds11/29/43 and source/result banks0/1/0. Nontrivial corners and every output word are checked against independently generated integer B-compatible bilinear/nearest fixtures. These tests execute the actual B homography/coordinate/interpolation pipeline; they do not feed golden pixels directly into the writer.

Native source64word read command counts are10324/frame for bilinear and10300/frame for nearest. Processing clock is nominal54MHz and UI125MHz. Input bank/base pins change immediately after accepted start to test immutable session ownership. Invalid geometry is rejected before any native traffic and a subsequent valid frame succeeds. Coincident start+abort cannot launch. Reduced abort cases retire the prior native prefix without publishing it, drain old generation requests, and publish an exact new generation afterward.

Logs and matching pre/post source manifests are under D:/FPGA/output/c_stream_burst_path_20261015_{full_bilinear,full_nearest,reduced_bilinear,reduced_nearest}. Bounded copies are in evidence/path_*; the expected initial single-beat wrapper failure is preserved in evidence/path_red_reduced (AWLEN0 versus required7). Compilation and simulation report Errors0 Warnings0 for all four passing cases.

Frozen wrapper SHA256:6774D5EEEEF28072FD2D4321F3CBD135F7BF52FF97E0D2CEEB151738BD7B9B59. Current v2 cache SHA256:754ED2E854AFA368E1287C0C0AA351BFA2D7B9B3287E267F576AA4A8D0EB30A2. Descriptor bridge SHA256:EC72E354E2DC36B23A7F6E1DA28DAEA48D5F6154A19F5CD88B13C9FA0FB7B466. Exact B/RTL/testbench bindings are preserved per run.

Limits: this combined correction test excludes live HDMI capture, scanout contention, DDR refresh/physical timing, routed timing closure and camera measurements. Its geometry-invalid case tests the correction API; it does not exercise raw marker detection. It establishes end-to-end correction/publishing correctness and simulated datapath capacity, not60newly captured frames/s or physical frame age. Root's continuous-capture/display/nativeDDR integration, frame-ID/age telemetry, implementation and board qualification remain separate gates.
