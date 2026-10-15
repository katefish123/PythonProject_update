param([string]$Suffix='reduced',[switch]$Full,[switch]$Solver,[string]$Golden='',[string]$GoldenRoot='',[switch]$Nearest,[switch]$AbortTest,[string]$Baseline='D:/FPGA/output/c_black_burst_merge_v3_20261015')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$root=Split-Path $here
$base=$Baseline
$out="D:/FPGA/output/c_stream_native_integration_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
if(-not(Test-Path work)){& 'D:/softwares/modelsim/win64/vlib.exe' work}
$files=@("$base/vendor/b/rtl/unsigned_div_seq.v","$base/vendor/b/rtl/signed_div_seq.v","$base/vendor/b/rtl/scaled_div_pipe.v","$base/vendor/b/rtl/homography_solver.v","$base/vendor/b/rtl/perspective_coord.v","$base/vendor/b/rtl/bilinear_interp.v","$base/vendor/b/rtl/perspective_core.v","$base/rtl/algo/c_corner_rectifier.v","$base/rtl/memory/ddr_arbiter3.v","$base/rtl/memory/async_packet_fifo.v")
foreach($dir in @('processor','bridge','cache','writer','engine')){$files+=@(Get-ChildItem "$root/$dir" -Filter '*.v' | ForEach-Object FullName)}
$files+="$here/c_stream_correction_path.v";$files+="$here/tb_stream_path.sv"
$files | ForEach-Object {Get-FileHash $_ -Algorithm SHA256} | Format-List | Out-File source_hashes.txt
$defines=@();if($Full){$defines+='+define+FULL'};if($Solver){$defines+='+define+SOLVER'}
& 'D:/softwares/modelsim/win64/vlog.exe' -sv @defines @files | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
$plusargs=@();if($Golden){$plusargs+="+GOLDEN=$Golden"};if($GoldenRoot){$plusargs+="+GOLDEN_ROOT=$GoldenRoot"};if($Nearest){$plusargs+="+NEAREST"};if($AbortTest){$plusargs+="+ABORT_TEST"}
@'
onbreak {quit -code 1}
onerror {quit -code 1}
run -all
quit -code 0
'@ | Set-Content run.do
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do run.do work.tb_stream_path @plusargs | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String -Path simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not(Select-String -Path simulation.log -Pattern 'PASS stream native integration complete' -Quiet)){throw 'simulation failure'}
$files | ForEach-Object {Get-FileHash $_ -Algorithm SHA256} | Format-List | Out-File source_hashes_after.txt
if(Compare-Object (Get-Content source_hashes.txt) (Get-Content source_hashes_after.txt)){throw 'source changed during simulation'}
} finally {Pop-Location}



