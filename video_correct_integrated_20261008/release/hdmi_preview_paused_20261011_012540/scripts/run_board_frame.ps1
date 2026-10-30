$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bin = 'C:\modeltech64_2020.4\win64'
$out = Join-Path $root 'results\board_fixture\simulation'
New-Item -ItemType Directory -Force -Path $out | Out-Null
function Invoke-Logged([string]$exe, [string[]]$arguments, [string]$logName) {
    $log = Join-Path $out $logName
    & (Join-Path $bin $exe) @arguments *> $log
    if ($LASTEXITCODE -ne 0) { throw "$exe failed ($LASTEXITCODE); see $log" }
}
$work = Join-Path $out 'work'
if (!(Test-Path $work)) { Invoke-Logged 'vlib.exe' @($work) 'vlib.log' }
Invoke-Logged 'vmap.exe' @('board_fixture_work',$work) 'vmap.log'
# Use the production ADS-compatible marker detector in rtl/algo, never vendor/b's duplicate.
$rtl = @(Get-ChildItem (Join-Path $root 'vendor\b\rtl') -Filter '*.v' |
    Where-Object { $_.Name -ne 'marker_detector.v' } | ForEach-Object FullName)
$rtl += Join-Path $root 'rtl\algo\marker_detector.v'
$rtl += Join-Path $root 'rtl\top\frame_processor.v'
Invoke-Logged 'vlog.exe' (@('-work',$work)+$rtl) 'compile_rtl.log'
Invoke-Logged 'vlog.exe' @('-sv','-work',$work,(Join-Path $root 'sim\tb_board_frame.sv')) 'compile_test.log'
$do = Join-Path $out 'run_board_frame.do'
@('onerror {quit -code 2 -force}','onbreak {resume}','onfinish stop','run -all',
  'set p [examine -value -radix binary -noshowbase sim:/tb_board_frame/test_passed]',
  'if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -code 3 -force}',
  'quit -code 0 -force') | Set-Content -Encoding ascii $do
Invoke-Logged 'vsim.exe' @('-c','-voptargs=+acc','board_fixture_work.tb_board_frame','-do',$do) 'simulation.log'
$logText = Get-Content (Join-Path $out 'simulation.log') -Raw
if (!$logText.Contains('BOARD_FRAME_PASS') -or !$logText.Contains('THEORETICAL_27MHZ_ALGORITHM_SECONDS')) {
    throw "Missing board test results; see $(Join-Path $out 'simulation.log')"
}
$logText -split "`r?`n" | Where-Object { $_ -match 'BOARD_FRAME_PASS|BOARD_COUNTS|THEORETICAL_27MHZ' }
