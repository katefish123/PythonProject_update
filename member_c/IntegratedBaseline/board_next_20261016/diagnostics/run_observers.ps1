param([string]$Suffix='local')
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_board_next_observers_20261016_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use a fresh suffix'}
New-Item -ItemType Directory -Path "$out/source_snapshot"|Out-Null
$names=@('snapshot_cdc.v','native_service_monitor.v','tb_snapshot_cdc.sv','tb_native_service.sv')
$compiled=@();foreach($n in $names){$target="$out/source_snapshot/$n";Copy-Item -LiteralPath "$PSScriptRoot/$n" -Destination $target;$compiled+=$target}
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work|Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv @compiled|Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'observer compile failed'}
 foreach($top in @('tb_snapshot_cdc','tb_native_service')){
 & D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop;run -all;quit -f' "work.$top"|Out-File "$top.log"
 if((Select-String "$top.log",compile.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String "$top.log" -Pattern 'PASS ' -Quiet)){throw "observer failed $top"}
 Get-Content "$top.log"|Select-String 'PASS|Errors:'
 }
}finally{Pop-Location}
