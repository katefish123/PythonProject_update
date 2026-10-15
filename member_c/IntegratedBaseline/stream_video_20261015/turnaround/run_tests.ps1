param([string]$Suffix='final')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_turnaround_regression_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
$rtl=@("$here/ddr_word_engine_result_burst.v","$here/ddr_arbiter3_turnaround.v")
$benches=@('tb_turnaround_engine','tb_turnaround_arbiter','tb_ddr_word_engine','tb_ddr_read_ahead','tb_source_prefetch','tb_capture_burst_protocol','tb_engine_block')
$files=@($rtl)+@($benches | ForEach-Object {if($_ -like 'tb_turnaround_*'){"$here/$_.sv"}else{"$here/../result_burst/$_.sv"}})
$hashes=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
$hashes | Format-List | Out-File "$out/source_hashes.txt"
Push-Location $out
try {
& D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
foreach($top in $benches){
 $tb=if($top -like 'tb_turnaround_*'){"$here/$top.sv"}else{"$here/../result_burst/$top.sv"}
 & D:/softwares/modelsim/win64/vlog.exe -sv @rtl $tb | Out-File "$top.compile.log"
 if($LASTEXITCODE -ne 0){throw "compile $top"}
 & D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop; run -all; quit -f' "work.$top" | Out-File "$top.log"
 if($LASTEXITCODE -ne 0 -or (Select-String "$top.log","$top.compile.log" -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String "$top.log" -Pattern 'PASS' -Quiet)){throw "test $top"}
}
$after=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
$after | Format-List | Out-File source_hashes_after.txt
if(Compare-Object $hashes.Hash $after.Hash){throw 'source drift'}
}finally{Pop-Location}
'TURNAROUND_UNITS_PASS cases=7'
