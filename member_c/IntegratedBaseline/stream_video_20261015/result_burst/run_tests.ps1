param([string]$Suffix='final',[switch]$SkipFull)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_result_burst_unit_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
$files=@(Get-ChildItem $here -File | Where-Object Extension -in @('.v','.sv','.ps1','.md'))
$hashes=@($files | ForEach-Object {Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256})
$hashes | Format-List | Out-File "$out/source_hashes.txt"
Push-Location $out
try {
if(-not(Test-Path work)){& 'D:/softwares/modelsim/win64/vlib.exe' work | Out-File library.log}
$rtl=@("$here/ddr_result_writer_burst64.v","$here/ddr_word_engine_result_burst.v")
$benches=@('tb_burst_count','tb_writer_burst','tb_result_burst_protocol','tb_ddr_word_engine','tb_ddr_read_ahead','tb_source_prefetch','tb_capture_burst_protocol','tb_engine_block')
if(-not $SkipFull){$benches+='tb_result_burst_native'}
foreach($top in $benches){
 & 'D:/softwares/modelsim/win64/vlog.exe' -sv @rtl "$here/$top.sv" | Tee-Object "$top.compile.log"
 if($LASTEXITCODE -ne 0){throw "compile $top"}
 @'
onerror {quit -code 1}
onfinish stop
run -all
quit -code 0
'@ | Set-Content run.do
 & 'D:/softwares/modelsim/win64/vsim.exe' -c -do run.do "work.$top" | Tee-Object "$top.log"
 if($LASTEXITCODE -ne 0 -or (Select-String "$top.log" -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not (Select-String "$top.log" -Pattern 'PASS' -Quiet)){throw "simulation $top"}
}
$after=@($files | ForEach-Object {Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256})
$after | Format-List | Out-File source_hashes_after.txt
if(Compare-Object ($hashes.Hash) ($after.Hash)){throw 'source drift during verification'}
}finally{Pop-Location}
