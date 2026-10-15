param([string]$Suffix='green',[switch]$Legacy,[switch]$DefaultLines)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_quad_tile_unit_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
 & D:/softwares/modelsim/win64/vlib.exe work
 if($Legacy){$rtl='D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/memory/ddr_pixel_cache.v';$tb="$PSScriptRoot/tb_legacy_serial.sv";$top='tb_legacy_serial'}
 else{$rtl="$PSScriptRoot/ddr_quad_tile_cache.v";$tb="$PSScriptRoot/tb_quad_tile.sv";$top='tb_quad_tile'}
 $defines=@();if($DefaultLines){$defines+= '+define+DEFAULT_LINES'}
 & D:/softwares/modelsim/win64/vlog.exe -sv @defines $rtl $tb | Tee-Object compile.log
 if($LASTEXITCODE -ne 0){throw 'compile failed'}
 & D:/softwares/modelsim/win64/vsim.exe -c -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' "work.$top" | Tee-Object simulation.log
 $rc=$LASTEXITCODE
 Get-FileHash $rtl,$tb | Format-List | Out-File source_hashes.txt
 if($Legacy){if(-not(Select-String simulation.log -Pattern 'LEGACY functional PASS' -Quiet) -or -not(Select-String simulation.log -Pattern '\*\* Fatal: THROUGHPUT_REQUIRED' -Quiet)){throw 'expected throughput failure absent'}}
 elseif($rc -ne 0 -or -not(Select-String simulation.log -Pattern 'PASS watchdog' -Quiet) -or (Select-String compile.log,simulation.log -Pattern '\*\* (Warning|Error|Fatal):' -Quiet)){throw 'cache verification failed'}
}finally{Pop-Location}
