param([string]$Suffix='local',[switch]$Red)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_manager_raw_20261016_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use a fresh suffix'}
New-Item -ItemType Directory -Path $out|Out-Null
$rtl=if($Red){'D:/FPGA/output/c_stream_board_v4s_20261016/rtl/stream/continuous_capture_manager.v'}else{"$PSScriptRoot/manager_raw.v"}
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work|Out-File library.log
 $defs=@();if($Red){$defs+='+define+RED_BASELINE'}
 & D:/softwares/modelsim/win64/vlog.exe -sv @defs $rtl "$PSScriptRoot/tb_manager_raw.sv"|Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'compile failed'}
 & D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop; run -all; quit -f' work.tb_manager_raw|Out-File simulation.log
 if($Red){if(-not(Select-String simulation.log -Pattern 'RAW_MUST_PUBLISH_WITHOUT_GEOMETRY' -Quiet)){throw 'Missing intended red failure'}}
 elseif((Select-String simulation.log,compile.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS MANAGER_RAW' -Quiet)){throw 'simulation failed'}
 Get-Content simulation.log|Select-String 'PASS|Fatal|Error|Warning'
}finally{Pop-Location}
