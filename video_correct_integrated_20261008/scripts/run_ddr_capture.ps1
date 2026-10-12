$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bin = 'C:\modeltech64_2020.4\win64'
$out = Join-Path $root 'results\ddr_capture_tests'
New-Item -ItemType Directory -Force -Path $out | Out-Null
function Invoke-Logged([string]$exe, [string[]]$arguments, [string]$logName) {
    $log = Join-Path $out $logName
    & (Join-Path $bin $exe) @arguments *> $log
    if ($LASTEXITCODE -ne 0) { throw "$exe failed ($LASTEXITCODE); see $log" }
}
$work = Join-Path $out 'work'
if (!(Test-Path $work)) { Invoke-Logged 'vlib.exe' @($work) 'vlib.log' }
Invoke-Logged 'vmap.exe' @('ddr_capture_work',$work) 'vmap.log'
Invoke-Logged 'vlog.exe' @('-work',$work,
  (Join-Path $root 'rtl\memory\async_packet_fifo.v'),
  (Join-Path $root 'rtl\video\ddr_snapshot_capture.v'),
  (Join-Path $root 'rtl\memory\ddr_capture_writer.v')) 'compile_rtl.log'
Invoke-Logged 'vlog.exe' @('-sv','-work',$work,(Join-Path $root 'sim\tb_ddr_capture.sv')) 'compile_test.log'
$do = Join-Path $out 'run_ddr_capture.do'
@('onerror {quit -code 2 -force}','onbreak {resume}','onfinish stop','run -all',
  'set p [examine -value -radix binary -noshowbase sim:/tb_ddr_capture/test_passed]',
  'if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -code 3 -force}',
  'quit -code 0 -force') | Set-Content -Encoding ascii $do
Invoke-Logged 'vsim.exe' @('-c','-voptargs=+acc','ddr_capture_work.tb_ddr_capture','-do',$do) 'simulation.log'
$logText = Get-Content (Join-Path $out 'simulation.log') -Raw
if (!$logText.Contains('DDR_CAPTURE_PASS')) { throw "Missing DDR test results; see $(Join-Path $out 'simulation.log')" }
$logText -split "`r?`n" | Where-Object { $_ -match 'DDR_(GOOD|REJECT|CAPTURE)_PASS' }
