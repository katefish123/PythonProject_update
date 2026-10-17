param([string]$Suffix='local',[string]$Bench='tb_source_marker_clean',[switch]$Native,[string]$Mutant='')
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/frame_region_20261017_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use fresh suffix'}
New-Item -ItemType Directory -Path "$out/source_snapshot" | Out-Null
$files=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.v);$files+=Get-Item -LiteralPath "$PSScriptRoot/$Bench.sv"
foreach($p in $files){Copy-Item -LiteralPath $p.FullName -Destination "$out/source_snapshot/$($p.Name)"}
if($Mutant){python -B "$PSScriptRoot/mutate_for_test.py" $Mutant "$out/source_snapshot";if($LASTEXITCODE -ne 0){throw 'Invalid mutant'}}
$hashes=@{};Get-ChildItem -LiteralPath "$out/source_snapshot" -File | ForEach-Object{$hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()}
$hashes|ConvertTo-Json|Out-File -Encoding utf8 "$out/compiled_hashes.json"
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work|Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv @((Get-ChildItem -LiteralPath "$out/source_snapshot" -File).FullName)|Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'Compile failed'}
 $generic=@();if($Native){$generic+='-gNATIVE=1'}
 & D:/softwares/modelsim/win64/vsim.exe -c @generic -do 'onfinish stop;run -all;quit -f' "work.$Bench"|Out-File simulation.log
 if($LASTEXITCODE -ne 0 -or (Select-String compile.log,simulation.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS ' -Quiet)){throw 'Region test failed'}
 Get-Content simulation.log|Select-String 'PASS |Errors:'
}finally{Pop-Location}
