param([string]$Suffix='green',[string]$Top='tb_packet_stream')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_quad_bridge_unit_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try{
& 'D:/softwares/modelsim/win64/vlib.exe' work
$sources=@('D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/memory/async_packet_fifo.v',"$here/async_packet_stream.v")
if($Top -eq 'tb_quad_bridge'){$sources+= "$here/quad_packet_bridge.v"}
$sources+="$here/$Top.sv"
& 'D:/softwares/modelsim/win64/vlog.exe' -sv @sources | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do 'run -all; quit -code 0' "work.$Top" | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not (Select-String simulation.log -Pattern 'PASS ' -Quiet)){throw 'simulation failure'}
Get-FileHash -Path $sources | Format-List | Out-File source_hashes.txt
}finally{Pop-Location}

