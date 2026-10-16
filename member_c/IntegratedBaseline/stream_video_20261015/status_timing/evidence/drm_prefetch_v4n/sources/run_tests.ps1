param([string]$Suffix='final')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$out="D:/FPGA/output/c_status_timing_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
$original=Get-Content "$here/status_overlay_original.v" -Raw
[IO.File]::WriteAllText("$out/status_overlay_golden.v",$original.Replace('module status_overlay(','module status_overlay_original('))
$sources=@("$here/status_overlay.v","$here/tb_status_timing.sv","$out/status_overlay_golden.v")
Push-Location $out
try {
Get-FileHash -Path $sources | Format-List | Out-File source_hashes_before.txt
if(-not (Test-Path work)){& 'D:/softwares/modelsim/win64/vlib.exe' work}
& 'D:/softwares/modelsim/win64/vlog.exe' -sv @sources | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
& 'D:/softwares/modelsim/win64/vsim.exe' -c -do 'run -all; quit -code 0' work.tb_status_timing | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:' -Quiet) -or -not (Select-String simulation.log -Pattern 'PASS status timing fullVTC' -Quiet)){throw 'simulation failure'}
Get-FileHash -Path $sources | Format-List | Out-File source_hashes_after.txt
if((Get-Content source_hashes_before.txt -Raw) -ne (Get-Content source_hashes_after.txt -Raw)){throw 'source changed during run'}
python "$here/test_structure.py" | Tee-Object structure_green.log
if($LASTEXITCODE -ne 0){throw 'structural validation failure'}
python "$here/test_structure.py" --rtl "$here/status_overlay_original.v" 2>&1 | Tee-Object structure_old_red.log
if($LASTEXITCODE -eq 0 -or -not (Select-String structure_old_red.log -Pattern 'missing independent 160-bit ROM row register' -Quiet)){throw 'old RTL must fail row register structural check'}
'PASS original RTL intentionally rejected by structural ROM cut checker' | Tee-Object structure_negative_result.txt
}finally{Pop-Location}
