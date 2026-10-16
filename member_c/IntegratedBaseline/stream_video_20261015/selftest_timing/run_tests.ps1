param([string]$Suffix='green',[string]$Source="$PSScriptRoot/ddr_self_test.v",[switch]$ExpectPipelineFailure)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_selftest_timing_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
$sources=@($Source,"$PSScriptRoot/tb_selftest_pipeline.sv")
$before=@(Get-FileHash -LiteralPath $sources)
Push-Location $out
try {
 if(-not(Test-Path work)){& D:/softwares/modelsim/win64/vlib.exe work}
 & D:/softwares/modelsim/win64/vlog.exe -sv @sources | Tee-Object compile.log
 if($LASTEXITCODE -ne 0){throw 'compile failure'}
 & D:/softwares/modelsim/win64/vsim.exe -c -do 'run -all; quit -code 0' work.tb_selftest_pipeline | Tee-Object simulation.log
 if($ExpectPipelineFailure){
  if(-not(Select-String simulation.log -Pattern 'Fatal: RESPONSE_COMPARE_NOT_PIPELINED' -Quiet)){throw 'expected old-path failure absent'}
 }else{
  if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* (Error|Warning|Fatal):' -Quiet) -or -not(Select-String simulation.log -Pattern 'SELFTEST_PIPELINE_PASS cases=516' -Quiet)){throw 'simulation failure'}
 }
 $after=@(Get-FileHash -LiteralPath $sources)
 if(Compare-Object $before.Hash $after.Hash){throw 'test source drift'}
 $after | Format-List | Out-File source_hashes.txt
}finally{Pop-Location}
