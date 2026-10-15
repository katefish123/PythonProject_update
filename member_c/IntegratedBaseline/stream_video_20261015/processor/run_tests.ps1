param([string]$Suffix='green',[switch]$Solver,[string]$ProcessorSource='')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
if(-not $ProcessorSource){$ProcessorSource=Join-Path $here 'frame_processor_stream.v'}
$base='D:/FPGA/output/c_black_burst_merge_v3_20261015'
$out="D:/FPGA/output/c_stream_processor_unit_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
& 'D:/softwares/modelsim/win64/vlib.exe' work
$define= if($Solver){'+define+SOLVER'}else{'+define+IDENTITY'}
& 'D:/softwares/modelsim/win64/vlog.exe' -sv $define "$base/vendor/b/rtl/unsigned_div_seq.v" "$base/vendor/b/rtl/signed_div_seq.v" "$base/vendor/b/rtl/scaled_div_pipe.v" "$base/vendor/b/rtl/homography_solver.v" "$base/vendor/b/rtl/perspective_coord.v" "$base/vendor/b/rtl/bilinear_interp.v" "$base/vendor/b/rtl/perspective_core.v" "$base/rtl/algo/c_corner_rectifier.v" "$ProcessorSource" "$here/tb_stream.sv" | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' work.tb_stream | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String -Path simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not (Select-String -Path simulation.log -Pattern 'PASS streaming' -Quiet)){throw 'simulation failure'}
Get-FileHash "$ProcessorSource","$here/tb_stream.sv" | Format-List | Out-File source_hashes.txt
}finally{Pop-Location}


