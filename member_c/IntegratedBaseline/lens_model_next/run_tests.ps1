param([string]$Suffix='local',[string]$Bench='tb_q30_alu',[int]$DisableTerm=0,[switch]$Composed)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/lens_rtl_20261017_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use fresh suffix'}
New-Item -ItemType Directory -Path "$out/source_snapshot" | Out-Null
$files=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.v)
$files+=Get-Item -LiteralPath 'D:/FPGA/output/c_stream_board_v4s_20261016/vendor/b/rtl/bilinear_interp.v'
$files+=Get-Item -LiteralPath "$PSScriptRoot/$Bench.sv"
foreach($p in $files){Copy-Item -LiteralPath $p.FullName -Destination "$out/source_snapshot/$($p.Name)"}
if($Bench -eq 'tb_lens_map'){
 New-Item -ItemType Directory -Path "$out/fixtures" | Out-Null
 foreach($n in @('vectors.hex','composed_vectors.hex','expected_pixels.hex','manifest.json')){Copy-Item -LiteralPath "D:/FPGA/output/lens_vectors_20261017/$n" -Destination "$out/fixtures/$n"}
 $benchCopy="$out/source_snapshot/$Bench.sv"
 $code=[IO.File]::ReadAllText($benchCopy).Replace('D:/FPGA/output/lens_vectors_20261017',"$out/fixtures")
 [IO.File]::WriteAllText($benchCopy,$code)
}
Get-FileHash -LiteralPath $files.FullName | Format-List | Out-File "$out/source_hashes.txt"
$hashes=@{};Get-ChildItem -LiteralPath "$out/source_snapshot" -File | ForEach-Object{$hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()}
$hashes | ConvertTo-Json | Out-File -Encoding utf8 "$out/compiled_hashes.json"
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv @($files|ForEach-Object{"$out/source_snapshot/$($_.Name)"}) | Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'Compile failed'}
 $generic=@();if($DisableTerm -gt 0){$generic+="-gDISABLE_TERM=$DisableTerm"}
 if($Composed){$generic+='-gCOMPOSED=1'}
 & D:/softwares/modelsim/win64/vsim.exe -c @generic -do 'onfinish stop;run -all;quit -f' "work.$Bench" | Out-File simulation.log
 if($LASTEXITCODE -ne 0 -or (Select-String compile.log,simulation.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS ' -Quiet)){throw 'RTL regression failed'}
 Get-Content simulation.log | Select-String 'PASS |Errors:'
}finally{Pop-Location}
