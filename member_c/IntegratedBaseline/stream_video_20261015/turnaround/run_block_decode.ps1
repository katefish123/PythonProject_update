param([string]$Suffix='green',[switch]$SkipStructure)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_engine_block_decode_20261016_$Suffix"
New-Item -ItemType Directory -Force "$out/source_snapshot" | Out-Null
$files=@("$here/ddr_word_engine_result_burst.v","$here/tb_block_region_decode.sv","$here/check_block_decode.py","$here/../result_burst/tb_result_burst_protocol.sv")
$before=@(Get-FileHash -LiteralPath $files -Algorithm SHA256);$before | Format-List | Out-File "$out/source_hashes.txt"
foreach($f in $files){Copy-Item -LiteralPath $f -Destination "$out/source_snapshot"}
Push-Location $out
try {
if(-not $SkipStructure){python source_snapshot/check_block_decode.py source_snapshot/ddr_word_engine_result_burst.v | Out-File structure.log;if($LASTEXITCODE -ne 0){throw 'constant block decode required'}}
& D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
foreach($top in @('tb_block_region_decode','tb_result_burst_protocol')){
& D:/softwares/modelsim/win64/vlog.exe -sv source_snapshot/ddr_word_engine_result_burst.v "source_snapshot/$top.sv" | Out-File "$top.compile.log"
if($LASTEXITCODE -ne 0){throw "compile $top"}
& D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop; run -all; quit -f' "work.$top" | Out-File "$top.log"
if($LASTEXITCODE -ne 0 -or (Select-String "$top.log","$top.compile.log" -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String "$top.log" -Pattern 'PASS' -Quiet)){throw "test $top"}
}
$after=@(Get-FileHash -LiteralPath $files -Algorithm SHA256);$after | Format-List | Out-File source_hashes_after.txt
if(Compare-Object $before.Hash $after.Hash){throw 'source drift'}
}finally{Pop-Location}
'PASS BLOCK_REGION_NATIVE_UNITS cases=2'
