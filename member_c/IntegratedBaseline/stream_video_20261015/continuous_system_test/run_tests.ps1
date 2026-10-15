param([string]$Suffix='reduced3',[int]$FullHD=0,[int]$Frames=3,[int]$Stress=0,[int]$BadFrame=2)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_continuous_system_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
$sources=Get-Content -Raw "$here/sources.json" | ConvertFrom-Json
$body=@('onerror {quit -f -code 1}',"transcript file {$out/transcript.log}",'if {![file exists work]} {vlib work}',"vmap work work",('vlog -sv -work work '+(($sources | ForEach-Object {"{$_}"}) -join ' ')),"vsim -c -voptargs=+acc=rnp+/tb_continuous_stream_system -wlf {$out/run.wlf} -gFULLHD=$FullHD -gSTRESS=$Stress -gBAD_FRAME=$BadFrame -gFRAMES=$Frames -gINLINE=1 -gOVERLAP=1 -gPREFETCH=1 -gLATE_CAPTURE=0 work.tb_continuous_stream_system",'onfinish stop','run -all','set pass_bit [examine -value -radix binary -noshowbase sim:/tb_continuous_stream_system/test_passed]','if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}','puts "VERIFIED_PASS_BIT=1"','quit -f -code 0')
$body | Set-Content "$out/case.do"
$fixture=if($FullHD){'fullhd'}else{'reduced'}
$bound=@($sources)+@(Get-ChildItem "$here/../system_test/fixtures/$fixture" -Filter '*.hex' | ForEach-Object FullName)
$hashes=@(Get-FileHash -LiteralPath $bound -Algorithm SHA256)
$hashes | Format-List | Out-File "$out/source_hashes.txt"
Push-Location $out
try {
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do "$out/case.do" | Tee-Object console.log
if($LASTEXITCODE -ne 0 -or -not(Select-String console.log -Pattern 'VERIFIED_PASS_BIT=1' -Quiet) -or (Select-String console.log -Pattern '\*\* (Error|Warning|Fatal):' -Quiet)){throw 'continuous system simulation failure'}
$after=@(Get-FileHash -LiteralPath $bound -Algorithm SHA256)
$after | Format-List | Out-File source_hashes_after.txt
if(Compare-Object $hashes.Hash $after.Hash){throw 'snapshot drift during continuous system test'}
}finally{Pop-Location}
