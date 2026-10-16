param([string]$Suffix='writer_timing')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_capture_writer_20261016_$Suffix"
New-Item -ItemType Directory -Force "$out/source_snapshot" | Out-Null
$files=@("$here/continuous_capture_writer.v","$here/tb_capture_writer_timing.sv")
$before=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
$before | Format-List | Out-File "$out/source_hashes.txt"
foreach($f in $files){Copy-Item -LiteralPath $f -Destination "$out/source_snapshot"}
Push-Location $out
try {
& D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
& D:/softwares/modelsim/win64/vlog.exe -sv source_snapshot/continuous_capture_writer.v source_snapshot/tb_capture_writer_timing.sv | Out-File compile.log
if($LASTEXITCODE -ne 0){throw 'compile failed'}
& D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop; run -all; quit -f' work.tb_capture_writer_timing | Out-File simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log,compile.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS CAPTURE_WRITER_TIMING' -Quiet)){throw 'writer timing test failed'}
$after=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
$after | Format-List | Out-File source_hashes_after.txt
if(Compare-Object $before.Hash $after.Hash){throw 'source drift'}
} finally {Pop-Location}
'PASS CAPTURE_WRITER_UNIT'
