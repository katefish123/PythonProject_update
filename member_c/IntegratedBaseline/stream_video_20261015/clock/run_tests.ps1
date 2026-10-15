param([string]$Suffix='green')
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$native='D:/softwares/PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation/GTP_GPLL.v'
$out="D:/FPGA/output/c_vendor_pll54_20261015_$Suffix"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try{
& 'D:/softwares/modelsim/win64/vlib.exe' work
& 'D:/softwares/modelsim/win64/vlog.exe' -sv $native "$here/video_pll_clock_test.v" "$here/tb_vendor_pll.sv" | Tee-Object compile.log
if($LASTEXITCODE -ne 0){throw 'compile failure'}
& 'D:/softwares/modelsim/win64/vsim.exe' -c -t 1fs -do 'run -all; quit -code 0' work.tb_vendor_pll | Tee-Object simulation.log
if($LASTEXITCODE -ne 0 -or (Select-String simulation.log -Pattern '\*\* Fatal:|\*\* Error:|GTP_GPLL error:' -Quiet) -or -not (Select-String simulation.log -Pattern 'PASS native GTP_GPLL' -Quiet)){throw 'simulation failure'}
Get-FileHash $native,"$here/video_pll_clock_test.v","$here/tb_vendor_pll.sv" | Format-List | Out-File source_hashes.txt
}finally{Pop-Location}
