param([string]$Suffix='local')
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_board_recovery_integration_20261016_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use a fresh suffix'}
New-Item -ItemType Directory -Path "$out/source_snapshot"|Out-Null
$root=Split-Path $PSScriptRoot
$sources=@(Get-Content "$root/integration/sources.json" -Raw|ConvertFrom-Json)
$sources+=@("$PSScriptRoot/video_correct_ddr_top.v","$PSScriptRoot/status_overlay.v","$PSScriptRoot/test_stubs.sv","$PSScriptRoot/tb_board_recovery_integration.sv",
 "$root/diagnostics/fault_diagnostics_stream.v","$root/diagnostics/native_service_monitor.v","$root/diagnostics/debug_hex_overlay.v","$root/control/board_recovery_reset.v",
 'D:/FPGA/output/c_stream_board_v4s_20261016/vendor/c_current/01_design_code/hdmi_vs_recover.v')
$compiled=@();foreach($source in $sources){$target=Join-Path "$out/source_snapshot" ([IO.Path]::GetFileName($source));Copy-Item -LiteralPath $source -Destination $target;$compiled+=$target}
Get-FileHash -LiteralPath $compiled|Format-List|Out-File "$out/source_hashes.txt"
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work|Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv @compiled|Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'compile failed'}
 & D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop;run -all;quit -f' work.tb_board_recovery_integration|Out-File simulation.log
 if((Select-String compile.log,simulation.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS BOARD_RECOVERY_INTEGRATION' -Quiet)){throw 'board recovery integration failed'}
 Get-Content simulation.log|Select-String 'PASS|Errors:'
}finally{Pop-Location}
