param([string]$Suffix='local',[switch]$Native,[switch]$Corrected)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_board_next_raw_20261016_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use a fresh suffix'}
New-Item -ItemType Directory -Path $out|Out-Null
$sources=@(Get-Content "$PSScriptRoot/integration/sources.json" -Raw|ConvertFrom-Json)
$sources+="$PSScriptRoot/integration/tb_raw_pipeline.sv"
Get-FileHash -LiteralPath $sources|Format-List|Out-File "$out/source_hashes.txt"
New-Item -ItemType Directory -Path "$out/source_snapshot"|Out-Null
$compiled=@()
foreach($source in $sources){
 $target=Join-Path "$out/source_snapshot" ([IO.Path]::GetFileName($source))
 if(Test-Path -LiteralPath $target){throw "Duplicate source filename: $source"}
 Copy-Item -LiteralPath $source -Destination $target
 $compiled+=$target
}
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work|Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv @compiled|Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'compile failed'}
 $generics=@();if($Native){$generics+='-gNATIVE=1'}
 if($Corrected){$generics+='-gCORRECTED=1';$generics+='-gFRAMES=2'}
 & D:/softwares/modelsim/win64/vsim.exe -c @generics -do 'onfinish stop; run -all; quit -f' work.tb_raw_pipeline|Out-File simulation.log
 if((Select-String compile.log,simulation.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS RAW_PIPELINE' -Quiet)){throw 'integration failed'}
 Get-Content simulation.log|Select-String 'PASS|PUBLICATION|Errors:'
}finally{Pop-Location}
