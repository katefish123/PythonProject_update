param([string]$Suffix='green')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_frame_telemetry_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
& 'D:/softwares/modelsim/win64/vlib.exe' work
$sources=@("$here/frame_telemetry_overlay.v","$here/tb_frame_telemetry.sv")
& 'D:/softwares/modelsim/win64/vlog.exe' -sv @sources | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do 'run -all; quit -code 0' work.tb_frame_telemetry | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not (Select-String simulation.log -Pattern 'PASS frame telemetry' -Quiet)){throw 'simulation failure'}
Get-FileHash -Path $sources | Format-List | Out-File source_hashes.txt
} finally {Pop-Location}
