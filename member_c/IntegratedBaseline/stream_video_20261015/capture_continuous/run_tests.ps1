param([string]$Suffix='legacy_red',[string]$Top='tb_legacy_boundary',[int]$Native=0,[int]$Frames=6)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_continuous_capture_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
$sources=@('D:/FPGA/output/c_stream_board_v1_20261015/rtl/video/ddr_snapshot_capture.v')
if($Top -ne 'tb_legacy_boundary'){
 $sources=@('D:/FPGA/output/c_stream_board_v1_20261015/rtl/memory/async_packet_fifo.v',"$here/../bridge/async_packet_stream.v",'D:/FPGA/output/c_stream_board_v1_20261015/vendor/b/rtl/unsigned_div_seq.v','D:/FPGA/output/c_stream_board_v1_20261015/rtl/algo/marker_detector.v')
 $sources+=Get-ChildItem "$here/*.v" | ForEach-Object {$_.FullName}
}
$sources+="$here/$Top.sv"
$snapshot=Join-Path $out 'source_snapshot'
New-Item -ItemType Directory -Force $snapshot | Out-Null
$compiledSources=@()
foreach($source in $sources){
 $target=Join-Path $snapshot ([System.IO.Path]::GetFileName($source))
 Copy-Item -LiteralPath $source -Destination $target
 $compiledSources+=$target
}
Get-FileHash -Path $compiledSources | Format-List | Out-File "$out/source_hashes.txt"
Push-Location $out
try{
& 'D:/softwares/modelsim/win64/vlib.exe' work
& 'D:/softwares/modelsim/win64/vlog.exe' -sv @compiledSources | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
$generics=@("-gNATIVE=$Native")
if($Top -eq 'tb_continuous_source'){$generics+="-gFRAMES=$Frames"}
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do 'run -all; quit -code 0' @generics "work.$Top" | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS ' -Quiet)){throw 'simulation failure'}
}finally{Pop-Location}
