param([string]$Suffix='green')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_preview_write_20261016_$Suffix"
New-Item -ItemType Directory -Force "$out/source_snapshot" | Out-Null
$files=@("$here/rx_preview_stream.v","$here/tb_preview_write_pipeline.sv")
$before=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
$before | Format-List | Out-File "$out/source_hashes.txt"
foreach($f in $files){Copy-Item -LiteralPath $f -Destination "$out/source_snapshot"}
Push-Location $out
try {
& D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
& D:/softwares/modelsim/win64/vlog.exe -sv source_snapshot/rx_preview_stream.v source_snapshot/tb_preview_write_pipeline.sv | Out-File compile.log
if($LASTEXITCODE -ne 0){throw 'compile failed'}
foreach($d in @(1,2,8)){
& D:/softwares/modelsim/win64/vsim.exe -c "-gD=$d" -do 'onfinish stop; run -all; quit -f' work.tb_preview_write_pipeline | Out-File "D$d.log"
if($LASTEXITCODE -ne 0 -or (Select-String "D$d.log",compile.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String "D$d.log" -Pattern 'PASS PREVIEW_WRITE_PIPELINE' -Quiet)){throw "preview pipeline D$d failed"}
}
$after=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
$after | Format-List | Out-File source_hashes_after.txt
if(Compare-Object $before.Hash $after.Hash){throw 'source drift'}
} finally {Pop-Location}
'PASS PREVIEW_WRITE_PIPELINE_UNITS cases=3'
