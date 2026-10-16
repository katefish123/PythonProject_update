param([string]$Suffix='local',[switch]$Red,[switch]$Native,[switch]$Late)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_board_next_display_20261016_$Suffix"
if(Test-Path -LiteralPath $out){throw "Use a fresh suffix: $out already exists"}
New-Item -ItemType Directory -Path $out | Out-Null
$frozen='D:/FPGA/output/c_stream_board_v4s_20261016'
$timing="$frozen/vendor/c_current/01_design_code/video_timing_vtc.v"
$rtl=if($Red){"$frozen/rtl/stream/ddr_result_display_block64.v"}else{"$here/ddr_result_display_raw_corrected.v"}
$files=@($rtl,$timing,"$here/tb_raw_corrected.sv")
$before=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
$before|Format-List|Out-File "$out/source_hashes.txt"
Push-Location $out
try {
 & D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
 $defines=@(if($Red){'+define+RED_BASELINE'})
 & D:/softwares/modelsim/win64/vlog.exe -sv @defines @files | Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'compile failed'}
 $generics=@();if($Native){$generics+='-gNATIVE=1'};if($Late){$generics+='-gLATE=1'}
 & D:/softwares/modelsim/win64/vsim.exe -c @generics -do 'onfinish stop; run -all; quit -f' work.tb_raw_corrected | Out-File simulation.log
 $errorFound=Select-String simulation.log,compile.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet
 if($Red){if(-not(Select-String simulation.log -Pattern 'RAW_MODE_PUBLICATION_REQUIRED' -Quiet)){throw 'RED did not detect absent mode publication'}}
 elseif($LASTEXITCODE -ne 0 -or $errorFound -or -not(Select-String simulation.log -Pattern 'PASS RAW_CORRECTED' -Quiet)){throw 'simulation failed'}
 $after=@(Get-FileHash -LiteralPath $files -Algorithm SHA256)
 $after|Format-List|Out-File source_hashes_after.txt
 if(Compare-Object $before.Hash $after.Hash){throw 'source changed during run'}
 Get-Content simulation.log|Select-String 'PASS|Fatal|Error|Warning'
} finally {Pop-Location}
