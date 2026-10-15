param([string]$Suffix='final')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_cache_fill_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
$files=@("$here/ddr_quad_tile_cache.v","$here/ddr_result_display_block64.v","$here/tb_cache_fill.sv")
$hashes=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
$hashes | Format-List | Out-File "$out/source_hashes.txt"
Push-Location $out
try{
& D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
foreach($ways in @(8,64)){
 $defines=@();if($ways -eq 64){$defines+='+define+DEFAULT_LINES'}
 & D:/softwares/modelsim/win64/vlog.exe -sv @defines $files[0] $files[1] $files[2] | Out-File "$ways.compile.log"
 if($LASTEXITCODE -ne 0){throw ('compile exit '+$LASTEXITCODE+' ways '+$ways)}
 & D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop; run -all; quit -f' work.tb_cache_fill | Out-File "$ways.log"
 if($LASTEXITCODE -ne 0 -or (Select-String "$ways.compile.log","$ways.log" -Pattern '\*\* (Error|Warning|Fatal):' -Quiet) -or -not(Select-String "$ways.log" -Pattern 'PASS invalid address' -Quiet)){throw "cache ways=$ways"}
}
$after=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
$after | Format-List | Out-File source_hashes_after.txt
if(Compare-Object $hashes.Hash $after.Hash){throw 'source drift'}
}finally{Pop-Location}
'CACHE_FILL_UNITS_PASS ways=8,64'

