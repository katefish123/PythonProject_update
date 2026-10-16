param([string]$Suffix='candidate',[string]$Top='tb_quad_pipeline',[switch]$PipelineChecks,[switch]$DefaultLines)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_quad_cache_v4r_20261016_$Suffix"
New-Item -ItemType Directory -Force "$out/source_snapshot" | Out-Null
$compiled=@()
foreach($source in @("$PSScriptRoot/ddr_quad_tile_cache.v","$PSScriptRoot/$Top.sv")){
 $target=Join-Path "$out/source_snapshot" ([IO.Path]::GetFileName($source));Copy-Item -LiteralPath $source -Destination $target;$compiled+=$target
}
Get-FileHash $compiled | Format-List | Out-File "$out/source_hashes.txt"
$defines=@();if($PipelineChecks){$defines+='+define+PIPELINE_CHECKS'};if($DefaultLines){$defines+='+define+DEFAULT_LINES'}
Push-Location $out
try{
& D:/softwares/modelsim/win64/vlib.exe work
& D:/softwares/modelsim/win64/vlog.exe -sv @defines @compiled | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
& D:/softwares/modelsim/win64/vsim.exe -c -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' "work.$Top" | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS watchdog' -Quiet)){throw 'simulation failure'}
}finally{Pop-Location}
