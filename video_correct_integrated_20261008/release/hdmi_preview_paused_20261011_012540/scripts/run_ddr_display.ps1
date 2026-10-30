$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$bin = 'C:\modeltech64_2020.4\win64'
$out = Join-Path $taskRoot 'results\ddr_display'
New-Item -ItemType Directory -Force -Path $out | Out-Null
function Invoke-Logged([string]$exe, [string[]]$arguments, [string]$name) {
    & (Join-Path $bin $exe) @arguments *> (Join-Path $out $name)
    if ($LASTEXITCODE -ne 0) { throw "$exe failed; see $out\$name" }
}
$work = Join-Path $out 'work'
if (!(Test-Path $work)) { Invoke-Logged 'vlib.exe' @($work) 'vlib.log' }
Invoke-Logged 'vmap.exe' @('ddr_display_tests',$work) 'vmap.log'
Invoke-Logged 'vlog.exe' @('-sv','-work',$work,(Join-Path $taskRoot 'vendor\c_current\01_design_code\video_timing_vtc.v'),(Join-Path $taskRoot 'rtl\video\ddr_result_display.v'),(Join-Path $taskRoot 'sim\tb_ddr_display.sv')) 'compile.log'
$do = Join-Path $out 'run.do'
@('onerror {quit -code 2 -force}','onbreak {resume}','onfinish stop','run -all',
  'set p [examine -value -radix binary -noshowbase sim:/tb_ddr_display/test_passed]',
  'if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -code 3 -force}',
  'quit -code 0 -force') | Set-Content -Encoding ascii $do
Invoke-Logged 'vsim.exe' @('-c','-voptargs=+acc','ddr_display_tests.tb_ddr_display','-do',$do) 'simulation.log'
$log = Get-Content (Join-Path $out 'simulation.log') -Raw
if (!$log.Contains('DDR_DISPLAY_PASS')) { throw 'DDR display pass marker missing' }
$log -split "`r?`n" | Where-Object { $_ -match 'DDR_DISPLAY_PASS' }
