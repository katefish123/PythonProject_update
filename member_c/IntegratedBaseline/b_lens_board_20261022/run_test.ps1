param([string]$Suffix='red',[string]$Sources='D:/FPGA/output/c_board_next_v5c_20261016/sources',[switch]$Raw)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/b_lens_board_sim_20261022_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use new suffix'}
New-Item -ItemType Directory -Path "$out/source_snapshot"|Out-Null
$base=Split-Path -Parent $PSScriptRoot
$list=Get-Content "$base/board_next_20261016/integration/sources.json" -Raw|ConvertFrom-Json
foreach($p in $list){$file=Join-Path $Sources ([IO.Path]::GetFileName($p));Copy-Item -LiteralPath $file -Destination "$out/source_snapshot/"}
if(Test-Path "$Sources/lens_distort_coord.v"){Copy-Item "$Sources/lens_distort_coord.v","$Sources/lens_autocrop_instance.v" "$out/source_snapshot/"}
Copy-Item "$PSScriptRoot/tb_lens_board.sv" "$out/source_snapshot/"
$hashes=@{};Get-ChildItem "$out/source_snapshot" -File|ForEach-Object{$hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()}
$hashes|ConvertTo-Json|Out-File -Encoding utf8 "$out/compiled_hashes.json"
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work|Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv @((Get-ChildItem "$out/source_snapshot" -File).FullName)|Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'Compile failed'}
 $generics=@();if($Raw){$generics+='-gCORRECTED=0'}
 & D:/softwares/modelsim/win64/vsim.exe -c @generics -do 'onfinish stop;run -all;quit -f' work.tb_raw_pipeline|Out-File simulation.log
 if((Select-String compile.log,simulation.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS RAW_PIPELINE' -Quiet)){throw 'Board integration test failed'}
 Get-Content simulation.log|Select-String 'PASS|Errors:|PUBLICATION'
}finally{Pop-Location}
