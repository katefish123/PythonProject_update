param([string]$Suffix='green')
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/c_preview_row_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try{
& D:/softwares/modelsim/win64/vlib.exe work
$base='D:/FPGA/output/c_black_burst_merge_v3_20261015'
$files=@("$base/diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_result_display.v","$base/rtl/video/result_display.v","$base/rtl/common/reset_sync.v","$PSScriptRoot/rx_preview_stream.v","$PSScriptRoot/tb_preview_raster.sv")
$files+="$base/vendor/c_current/01_design_code/video_timing_vtc.v"
& D:/softwares/modelsim/win64/vlog.exe -sv @files | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failed'}
& D:/softwares/modelsim/win64/vsim.exe -c -do 'run -all;quit -code 0' work.tb_preview_raster | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or -not(Select-String simulation.log -Pattern 'PASS preview' -Quiet) -or (Select-String simulation.log,compile.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet)){throw 'verification failed'}
Get-FileHash $files | Format-List | Out-File source_hashes.txt
}finally{Pop-Location}
