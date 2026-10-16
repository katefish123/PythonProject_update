param([string]$Suffix='green',[string]$Top='tb_frame_telemetry')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_frame_telemetry_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
if(-not (Test-Path work)){& 'D:/softwares/modelsim/win64/vlib.exe' work}
$sources=@("$here/frame_telemetry_overlay.v","$here/$Top.sv")
& 'D:/softwares/modelsim/win64/vlog.exe' -sv @sources | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do 'run -all; quit -code 0' "work.$Top" | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not (Select-String simulation.log -Pattern 'PASS ' -Quiet)){throw 'simulation failure'}
Get-FileHash -Path $sources | Format-List | Out-File source_hashes.txt
} finally {Pop-Location}
