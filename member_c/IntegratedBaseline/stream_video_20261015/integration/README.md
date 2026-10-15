# Native DDR streaming integration evidence

This is datapath simulation evidence. It excludes simultaneous camera capture, HDMI scanout, DDR refresh and physical memory timing. It does not establish 60 newly captured corrected frames/s, timing closure or board image quality.

All final runs bind cache SHA256 7C3625555CFB85EF0C3C74EEFAAAC6DB406D7F6C0EB1E5ACFC8F52795C8BC6D3 and wrapper SHA256 41398A74A7D1D2E752362019B3EFDD3214D51C2E27417BAE52A54952E9557630. B sources remain unmodified. Each log directory records compiled RTL/TB hashes in source_hashes.txt. Current runner also compares source_hashes_after.txt to reject mid-run changes.

The native AXI model supports AW and W consumption on the same cycle, independent address/data stalls, delayed/gapped source reads and real engine responses. Source RGB is generated directly from each native word address, without a duplicated source RAM. Two result banks have actual 32-bit word RAM; every WREADY byte strobe is applied, every resulting RGB/padding word is compared, and all RAM words are read back before publication passes. Input source_base and frame_bank pins toggle immediately after start to test session immutability.

At processing clock54MHz and UI125MHz, three full 768x1080 stored frames (765x1080 active, one black left and two right) pass for each mode, using distinct native1920x1080 source patterns11/29/43 and alternating source/result banks0/1/0. Solver modes compare every output against the independent integer homography/perspective/interpolation fixture, never DUT q outputs. Fixed identity is a separate source-crop throughput test.

| Full run | Start-to-publication | Processing cycles | Source64word commands/frame | Native result beats/frame |
|---|---:|---:|---:|---:|
| Fixed identity |15.362273–15.362292ms|829576–829577|12960|103680|
| Nontrivial solver bilinear |15.379606–15.379680ms|830512–830516|10324|103680|
| Nontrivial solver nearest |15.376810–15.376829ms|830361–830362|10300|103680|

The nontrivial full corners96 are 28a0464e206e5283f224e3c0; reduced corners are 02200405d00606702a019027. Fixtures live under ../fixtures/generated/{fullhd,reduced}/variant{0,1,2}. Full storage829440 words includes826200 corrected pixels and3240 black padding pixels.

Reduced native tests use SRC128x48, stored32x48 and ACTIVE29. Identity, solver bilinear and solver nearest each pass three complete pattern/bank generations, an abort after64native words with no publication, full retirement of that prefix, and a fourth complete post-abort frame checked against the new generation. All runs also assert that coincident start+abort cannot accept a frame. The abort test deliberately lets old cache requests drain before changing the source pattern; a caller must retain source ownership until queued old requests retire. Native camera writes invalidate the engine's address-only source cache; its cache tag does not include the tile request generation.

Final output directories under D:/FPGA/output:

- c_stream_native_integration_20261015_stable_full_identity
- c_stream_native_integration_20261015_stable_full_solver_bilinear
- c_stream_native_integration_20261015_stable_full_solver_nearest
- c_stream_native_integration_20261015_stable_reduced_identity_abort
- c_stream_native_integration_20261015_stable_reduced_solver_bilinear_abort
- c_stream_native_integration_20261015_stable_reduced_solver_nearest_abort

Each has compile.log and simulation.log with Errors0 Warnings0. Script controls: -Full, -Solver, -Nearest, -AbortTest and -GoldenRoot pointing at the fullhd or reduced fixtures directory. A unique -Suffix selects output directory. Current runner's source-drift check also passed in c_stream_native_integration_20261015_runner_validation.
