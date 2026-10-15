param([string]$Suffix='reduced',[switch]$Full,[switch]$Solver,[switch]$Nearest,[switch]$AbortTest)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$root=Split-Path $here
$base='D:/FPGA/output/c_black_burst_merge_v3_20261015'
$out="D:/FPGA/output/c_stream_burst_path_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
$files=@("$base/vendor/b/rtl/unsigned_div_seq.v","$base/vendor/b/rtl/signed_div_seq.v","$base/vendor/b/rtl/scaled_div_pipe.v","$base/vendor/b/rtl/homography_solver.v","$base/vendor/b/rtl/perspective_coord.v","$base/vendor/b/rtl/bilinear_interp.v","$base/vendor/b/rtl/perspective_core.v","$base/rtl/algo/c_corner_rectifier.v","$base/rtl/memory/ddr_arbiter3.v","$base/rtl/memory/async_packet_fifo.v")
foreach($dir in @('processor','bridge','cache')){$files+=@(Get-ChildItem "$root/$dir" -Filter '*.v' | ForEach-Object FullName)}
$files+=@("$here/ddr_result_writer_burst64.v","$here/ddr_word_engine_result_burst.v","$here/c_stream_burst_correction_path.v","$here/tb_stream_burst_path.sv")
$hashes=@($files|ForEach-Object {Get-FileHash -LiteralPath $_ -Algorithm SHA256})
$hashes | Format-List | Out-File "$out/source_hashes.txt"
Push-Location $out
try {
 if(-not(Test-Path work)){& 'D:/softwares/modelsim/win64/vlib.exe' work | Out-File library.log}
 $defines=@();if($Full){$defines+='+define+FULL'};if($Solver){$defines+='+define+SOLVER'}
 & 'D:/softwares/modelsim/win64/vlog.exe' -sv @defines @files | Tee-Object compile.log
 if($LASTEXITCODE -ne 0){throw 'compile failure'}
 $args2=@();if($Full){$args2+="+GOLDEN_ROOT=$root/fixtures/generated/fullhd"}else{$args2+="+GOLDEN_ROOT=$root/fixtures/generated/reduced"};if($Nearest){$args2+='+NEAREST'};if($AbortTest){$args2+='+ABORT_TEST'}
 'onerror {quit -code 1}','onfinish stop','run -all','quit -code 0' | Set-Content run.do
 & 'D:/softwares/modelsim/win64/vsim.exe' -c -do run.do work.tb_stream_burst_path @args2 | Tee-Object simulation.log
 if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS stream native integration complete' -Quiet)){throw 'simulation failure'}
 $after=@($files|ForEach-Object {Get-FileHash -LiteralPath $_ -Algorithm SHA256})
 $after | Format-List | Out-File source_hashes_after.txt
 if(Compare-Object $hashes.Hash $after.Hash){throw 'source drift during simulation'}
}finally{Pop-Location}

