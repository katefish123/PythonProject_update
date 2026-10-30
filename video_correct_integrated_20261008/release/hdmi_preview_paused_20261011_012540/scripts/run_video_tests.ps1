$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bin = 'C:\modeltech64_2020.4\win64'
$out = Join-Path $root 'results\video_tests'
New-Item -ItemType Directory -Force -Path $out | Out-Null
function Invoke-Logged([string]$exe, [string[]]$arguments, [string]$logName) {
    $log = Join-Path $out $logName
    & (Join-Path $bin $exe) @arguments *> $log
    if ($LASTEXITCODE -ne 0) { throw "$exe failed ($LASTEXITCODE); see $log" }
}
foreach ($name in @('snapshot','display')) {
    $work = Join-Path $out "work_$name"
    if (!(Test-Path $work)) { Invoke-Logged 'vlib.exe' @($work) "vlib_$name.log" }
    Invoke-Logged 'vmap.exe' @("video_$name",$work) "vmap_$name.log"
}
Invoke-Logged 'vlog.exe' @('-work',(Join-Path $out 'work_snapshot'),(Join-Path $root 'rtl\video\snapshot_capture.v'),(Join-Path $root 'sim\tb_snapshot_capture.sv')) 'compile_snapshot.log'
Invoke-Logged 'vlog.exe' @('-work',(Join-Path $out 'work_display'),(Join-Path $root 'vendor\c\01_design_code\video_timing_vtc.v'),(Join-Path $root 'rtl\video\result_display.v'),(Join-Path $root 'sim\tb_result_display.sv')) 'compile_display.log'
foreach ($name in @('snapshot','display')) {
    if ($name -eq 'snapshot') { $tb = 'tb_snapshot_capture'; $marker = 'SNAPSHOT_SHORT_FRAME_REJECT_PASS' }
    else { $tb = 'tb_result_display'; $marker = 'RESULT_DISPLAY_FRAME_ATOMIC_PASS' }
    $do = Join-Path $out "run_$name.do"
    @("onerror {quit -code 2 -force}","onbreak {resume}","onfinish stop","run -all","set p [examine -value -radix binary -noshowbase sim:/$tb/passed]",'if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -code 3 -force}','quit -code 0 -force') | Set-Content -Encoding ascii $do
    Invoke-Logged 'vsim.exe' @('-c','-voptargs=+acc',"video_$name.$tb",'-do',$do) "simulation_$name.log"
    $logText = Get-Content (Join-Path $out "simulation_$name.log") -Raw
    if (!$logText.Contains($marker)) { throw "Missing pass marker for $name; see $(Join-Path $out "simulation_$name.log")" }
    $logText -split "`r?`n" | Where-Object { $_ -match 'PASS' }
}
