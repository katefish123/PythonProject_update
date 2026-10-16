param([string]$Suffix='local',[switch]$ExpectGuardRed)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_board_next_control_20261016_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use a fresh suffix'}
New-Item -ItemType Directory -Path $out|Out-Null
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work|Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv "$PSScriptRoot/c_frame_mode_controller.v" "$PSScriptRoot/board_recovery_reset.v" "$PSScriptRoot/tb_frame_modes.sv" "$PSScriptRoot/tb_board_recovery.sv"|Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'compile failed'}
 foreach($top in @('tb_frame_modes','tb_board_recovery')){
 & D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop; run -all; quit -f' "work.$top"|Out-File "$top.log"
 if($ExpectGuardRed -and $top -eq 'tb_frame_modes'){
 if(-not(Select-String "$top.log" -Pattern 'LOCKED_RAW_BANK_LAUNCHED_CORRECTION' -Quiet)){throw 'missing intended guard failure'}
 }elseif((Select-String "$top.log",compile.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String "$top.log" -Pattern 'PASS ' -Quiet)){throw "failed $top"}
 Get-Content "$top.log"|Select-String 'PASS|Fatal|Errors:'
 }
}finally{Pop-Location}
