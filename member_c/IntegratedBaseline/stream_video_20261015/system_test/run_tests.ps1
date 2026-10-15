param([string]$Suffix='reduced',[int]$FullHD=0,[int]$Frames=3,[int]$LateCapture=95,[int]$Stress=0,[int]$Prefetch=1)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_stream_system_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
$sources=Get-Content -Raw "$here/sources.json" | ConvertFrom-Json
$body=@("onerror {quit -f -code 1}","transcript file {$out/transcript.log}","vlib work","vmap work work",("vlog -sv -work work "+(($sources | ForEach-Object {"{$_}"}) -join ' ')),"vsim -c -voptargs=+acc=rnp+/tb_stream_system -wlf {$out/run.wlf} -gFULLHD=$FullHD -gSTRESS=$Stress -gFRAMES=$Frames -gINLINE=1 -gOVERLAP=1 -gPREFETCH=$Prefetch -gLATE_CAPTURE=$LateCapture work.tb_stream_system",'onfinish stop','run -all','set pass_bit [examine -value -radix binary -noshowbase sim:/tb_stream_system/test_passed]','if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}','puts "VERIFIED_PASS_BIT=1"','quit -f -code 0')
$body | Set-Content "$out/case.do"
$bound=@($sources)+@(Get-ChildItem "$here/fixtures" -Recurse -Filter '*.hex' | ForEach-Object FullName)
Get-FileHash -Path $bound | Format-List | Out-File "$out/source_hashes.txt"
Push-Location $out
try{
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do "$out/case.do" | Tee-Object console.log
if($LASTEXITCODE -ne 0 -or -not (Select-String console.log -Pattern 'VERIFIED_PASS_BIT=1' -Quiet) -or (Select-String console.log -Pattern '\*\* (Error|Warning|Fatal):' -Quiet)){throw 'system simulation failure'}
Get-FileHash -Path $bound | Format-List | Out-File "$out/source_hashes_after.txt"
if(Compare-Object (Get-Content "$out/source_hashes.txt") (Get-Content "$out/source_hashes_after.txt")){throw 'inputs changed during system test'}
}finally{Pop-Location}
