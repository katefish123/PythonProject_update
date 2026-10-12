$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bin = 'C:\modeltech64_2020.4\win64'
$out = Join-Path $root 'results\ddr_core_e2e'
New-Item -ItemType Directory -Force -Path $out | Out-Null
function Invoke-Logged([string]$exe, [string[]]$arguments, [string]$logName) {
    $log = Join-Path $out $logName
    & (Join-Path $bin $exe) @arguments *> $log
    if ($LASTEXITCODE -ne 0) { throw "$exe failed ($LASTEXITCODE); see $log" }
}
$work = Join-Path $out 'work'
if (!(Test-Path $work)) { Invoke-Logged 'vlib.exe' @($work) 'vlib.log' }
Invoke-Logged 'vmap.exe' @('video_correct_ddr_core_work',$work) 'vmap.log'
$rtl = @(Get-ChildItem (Join-Path $root 'vendor\b\rtl') -Filter '*.v' | ForEach-Object FullName)
$rtl += Join-Path $root 'vendor\c\01_design_code\video_timing_vtc.v'
$rtl += @(Get-ChildItem (Join-Path $root 'rtl\video') -Filter '*.v' | ForEach-Object FullName)
$rtl += @(Get-ChildItem (Join-Path $root 'rtl\memory') -Filter '*.v' | ForEach-Object FullName)
$rtl += @(Get-ChildItem (Join-Path $root 'rtl\top') -Filter '*.v' | ForEach-Object FullName)
Invoke-Logged 'vlog.exe' (@('-work',$work)+$rtl) 'compile_rtl.log'
Invoke-Logged 'vlog.exe' @('-sv','-work',$work,(Join-Path $root 'sim\tb_video_correct_ddr_core.sv')) 'compile_test.log'
$do = Join-Path $out 'run_ddr_core.do'
@('onerror {quit -code 2 -force}','onbreak {resume}','onfinish stop','run -all',
  'set p [examine -value -radix binary -noshowbase sim:/tb_video_correct_ddr_core/test_passed]',
  'if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -code 3 -force}',
  'quit -code 0 -force') | Set-Content -Encoding ascii $do
Invoke-Logged 'vsim.exe' @('-c','-voptargs=+acc','video_correct_ddr_core_work.tb_video_correct_ddr_core','-do',$do) 'simulation.log'
$logText = Get-Content (Join-Path $out 'simulation.log') -Raw
if (!$logText.Contains('DDR_CORE_PASS')) { throw "Missing test result; see $(Join-Path $out 'simulation.log')" }
$logText -split "`r?`n" | Where-Object { $_ -match 'PASS|BIST_' }
