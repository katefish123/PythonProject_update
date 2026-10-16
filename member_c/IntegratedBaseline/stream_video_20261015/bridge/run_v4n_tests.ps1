param([string]$Suffix='candidate',[string]$Top='tb_quad_bridge_1920')
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_quad_bridge_v4n_20261016_$Suffix"
New-Item -ItemType Directory -Force "$out/source_snapshot" | Out-Null
$sources=@('D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/memory/async_packet_fifo.v',"$PSScriptRoot/async_packet_stream.v","$PSScriptRoot/quad_packet_bridge.v","$PSScriptRoot/$Top.sv")
$compiled=@()
foreach($source in $sources){$target=Join-Path "$out/source_snapshot" ([IO.Path]::GetFileName($source));Copy-Item -LiteralPath $source -Destination $target;$compiled+=$target}
Get-FileHash $compiled | Format-List | Out-File "$out/source_hashes.txt"
Push-Location $out
try{
& 'D:/softwares/modelsim/win64/vlib.exe' work
& 'D:/softwares/modelsim/win64/vlog.exe' -sv @compiled | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do 'run -all; quit -code 0' "work.$Top" | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS ' -Quiet)){throw 'simulation failure'}
}finally{Pop-Location}
