param([string]$Suffix='red',[switch]$Native,[switch]$Sampler,[string]$Mutant='')
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/frame_publish_20261018_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use fresh suffix'}
New-Item -ItemType Directory -Path "$out/source_snapshot"|Out-Null
$base=Split-Path -Parent $PSScriptRoot
$files=@("$PSScriptRoot/tb_publish.sv","$base/stream_video_20261015/result_burst/ddr_result_writer_burst64.v")
if(Test-Path "$PSScriptRoot/corrected_frame_guard.v"){$files+="$PSScriptRoot/corrected_frame_guard.v"}
if($Sampler){$files+=@("$base/frame_region_20261017/region_sample.v","$base/frame_region_20261017/source_marker_clean.v","$base/lens_throughput_20261017/q30_alu_fast.v","$base/lens_throughput_20261017/generated/lens_map_fast.v","$base/lens_throughput_20261017/generated/lens_composed_map_fast.v","$base/a_sync_20261013/hires_candidate/vendor/b/rtl/bilinear_interp.v")}
foreach($f in $files){Copy-Item -LiteralPath $f -Destination "$out/source_snapshot/"}
if($Mutant){python -B "$PSScriptRoot/mutate_for_test.py" $Mutant "$out/source_snapshot";if($LASTEXITCODE -ne 0){throw 'Invalid mutant'}}
$hashes=@{};Get-ChildItem "$out/source_snapshot" -File|ForEach-Object{$hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()}
$hashes|ConvertTo-Json|Out-File -Encoding utf8 "$out/compiled_hashes.json"
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work|Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv @((Get-ChildItem "$out/source_snapshot" -File).FullName)|Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'Compile failed'}
 $generics=@();if($Native){$generics+='-gNATIVE=1'};if($Sampler){$generics+='-gWITH_SAMPLER=1'}
 & D:/softwares/modelsim/win64/vsim.exe -c @generics -do 'onfinish stop;run -all;quit -f' work.tb_publish|Out-File simulation.log
 if($LASTEXITCODE -ne 0 -or (Select-String compile.log,simulation.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS FRAME_PUBLISH' -Quiet)){throw 'Frame publication test failed'}
 Get-Content simulation.log|Select-String 'PASS |Errors:'
}finally{Pop-Location}
