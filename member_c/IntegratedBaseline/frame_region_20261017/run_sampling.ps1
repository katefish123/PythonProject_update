param([string]$Suffix='red',[string]$Mutant='')
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/region_sample_20261017_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use a fresh suffix'}
New-Item -ItemType Directory -Path "$out/source_snapshot"|Out-Null
$base=Split-Path -Parent $PSScriptRoot
$files=@("$PSScriptRoot/tb_region_sample.sv","$PSScriptRoot/source_marker_clean.v")
if(Test-Path "$PSScriptRoot/region_sample.v"){$files+="$PSScriptRoot/region_sample.v"}
$files+=@("$base/lens_throughput_20261017/q30_alu_fast.v","$base/lens_throughput_20261017/generated/lens_map_fast.v","$base/lens_throughput_20261017/generated/lens_composed_map_fast.v","$base/a_sync_20261013/hires_candidate/vendor/b/rtl/bilinear_interp.v")
foreach($file in $files){Copy-Item -LiteralPath $file -Destination "$out/source_snapshot/"}
foreach($name in @('vectors.hex','composed_vectors.hex','expected_pixels.hex','manifest.json')){Copy-Item -LiteralPath "D:/FPGA/output/lens_vectors_20261017/$name" -Destination "$out/$name"}
if($Mutant){python -B "$PSScriptRoot/mutate_sampling.py" $Mutant "$out/source_snapshot";if($LASTEXITCODE -ne 0){throw 'Invalid mutant'}}
$hashes=@{};Get-ChildItem "$out/source_snapshot" -File|ForEach-Object{$hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()}
$hashes|ConvertTo-Json|Out-File -Encoding utf8 "$out/compiled_hashes.json"
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work|Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv @((Get-ChildItem "$out/source_snapshot" -File).FullName)|Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'Compile failed'}
 & D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop;run -all;quit -f' work.tb_region_sample|Out-File simulation.log
 if($LASTEXITCODE -ne 0 -or (Select-String compile.log,simulation.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS REGION_SAMPLE' -Quiet)){throw 'Sampling test failed'}
 Get-Content simulation.log|Select-String 'PASS |Errors:'
}finally{Pop-Location}
