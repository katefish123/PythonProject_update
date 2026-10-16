param([string]$Suffix='red_black',[string]$Top='tb_color_expectation',[switch]$Candidate)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_color_geometry_20261016_$Suffix"
New-Item -ItemType Directory -Force "$out/source_snapshot" | Out-Null
$sources=@('D:/FPGA/output/c_stream_board_v4s_20261016/vendor/b/rtl/unsigned_div_seq.v','D:/FPGA/output/c_stream_board_v4s_20261016/rtl/memory/async_packet_fifo.v','D:/FPGA/output/c_stream_board_v4s_20261016/rtl/stream/async_packet_stream.v','D:/FPGA/output/c_stream_board_v4s_20261016/rtl/algo/marker_detector.v')
$sources+=@('D:/FPGA/output/c_stream_board_v4s_20261016/vendor/b/rtl/homography_solver.v','D:/FPGA/output/c_stream_board_v4s_20261016/vendor/b/rtl/signed_div_seq.v','D:/FPGA/output/c_stream_board_v4s_20261016/vendor/b/rtl/perspective_coord.v','D:/FPGA/output/c_stream_board_v4s_20261016/vendor/b/rtl/scaled_div_pipe.v')
$defines=@()
if($Candidate){$sources+=Get-ChildItem "$PSScriptRoot/*.v" | ForEach-Object FullName;$defines+='+define+DETECTOR_MODULE=color_marker_detector'}else{}
$sources+="$PSScriptRoot/$Top.sv";$compiled=@()
foreach($source in $sources){$target=Join-Path "$out/source_snapshot" ([IO.Path]::GetFileName($source));Copy-Item -LiteralPath $source -Destination $target;$compiled+=$target}
Get-FileHash $compiled | Format-List | Out-File "$out/source_hashes.txt"
Push-Location $out
try{
& D:/softwares/modelsim/win64/vlib.exe work
& D:/softwares/modelsim/win64/vlog.exe -sv @defines @compiled | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
& D:/softwares/modelsim/win64/vsim.exe -c -do 'run -all; quit -code 0' "work.$Top" | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS ' -Quiet)){throw 'simulation failure'}
}finally{Pop-Location}
