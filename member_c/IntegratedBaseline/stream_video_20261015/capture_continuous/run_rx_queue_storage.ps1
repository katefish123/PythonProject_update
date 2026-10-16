param([string]$Suffix='green',[string]$RxSource='')
$ErrorActionPreference='Stop';$here=$PSScriptRoot
$out="D:/FPGA/output/c_rx_queue_storage_20261016_$Suffix"
New-Item -ItemType Directory -Force "$out/source_snapshot" | Out-Null
$rxFile=if($RxSource){$RxSource}else{"$here/continuous_capture_rx.v"}
$files=@($rxFile,"$here/continuous_capture_rx_queue_reference.sv","$here/tb_rx_queue_storage.sv")
$before=@(Get-FileHash -LiteralPath $files -Algorithm SHA256);$before | Format-List | Out-File "$out/source_hashes.txt"
foreach($f in $files){Copy-Item -LiteralPath $f -Destination "$out/source_snapshot"}
Push-Location $out
try{
& D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
& D:/softwares/modelsim/win64/vlog.exe -sv source_snapshot/continuous_capture_rx.v source_snapshot/continuous_capture_rx_queue_reference.sv source_snapshot/tb_rx_queue_storage.sv | Out-File compile.log
if($LASTEXITCODE -ne 0){throw 'compile failed'}
& D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop; run -all; quit -f' work.tb_rx_queue_storage | Out-File simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log,compile.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS RX_QUEUE_STORAGE_EQUIVALENCE' -Quiet)){throw 'RX queue storage test failed'}
$after=@(Get-FileHash -LiteralPath $files -Algorithm SHA256);$after | Format-List | Out-File source_hashes_after.txt
if(Compare-Object $before.Hash $after.Hash){throw 'source drift'}
}finally{Pop-Location}
'PASS RX_QUEUE_STORAGE_UNIT'
