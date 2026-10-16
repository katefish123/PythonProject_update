param([string]$Suffix='frozen')
$ErrorActionPreference='Stop';$here=$PSScriptRoot
$out="D:/FPGA/output/c_fault_diagnostics_20261016_$Suffix"
New-Item -ItemType Directory -Force "$out/source_snapshot" | Out-Null
$files=@("$here/fault_diagnostics_stream.v","$here/tb_fault_diagnostics.sv","$here/tb_legacy_fault_red.sv")
$before=@(Get-FileHash -LiteralPath $files -Algorithm SHA256);$before | Format-List | Out-File "$out/source_hashes.txt"
foreach($f in $files){Copy-Item -LiteralPath $f -Destination "$out/source_snapshot"}
Push-Location $out
try{
& D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
& D:/softwares/modelsim/win64/vlog.exe -sv source_snapshot/fault_diagnostics_stream.v source_snapshot/tb_fault_diagnostics.sv | Out-File compile.log
if($LASTEXITCODE -ne 0){throw 'compile failed'}
foreach($tickWidth in @(48,8)){
& D:/softwares/modelsim/win64/vsim.exe -c "-gTB=$tickWidth" -do 'onfinish stop;run -all;quit -f' work.tb_fault_diagnostics | Out-File "tick$tickWidth.log"
if($LASTEXITCODE -ne 0 -or (Select-String "tick$tickWidth.log",compile.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String "tick$tickWidth.log" -Pattern 'PASS FAULT_DIAGNOSTICS' -Quiet)){throw "diagnostic test TB$tickWidth failed"}
}
$after=@(Get-FileHash -LiteralPath $files -Algorithm SHA256);$after | Format-List | Out-File source_hashes_after.txt
if(Compare-Object $before.Hash $after.Hash){throw 'source drift'}
}finally{Pop-Location}
'PASS FAULT_DIAGNOSTICS_UNITS cases=2'
