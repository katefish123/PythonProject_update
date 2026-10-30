$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$bin = 'C:\modeltech64_2020.4\win64'
$out = Join-Path $root 'results\ddr_status_probe\simulation'
New-Item -ItemType Directory -Force -Path $out | Out-Null
function Invoke-Logged([string]$exe,[string[]]$arguments,[string]$name) {
    $log=Join-Path $out $name
    & (Join-Path $bin $exe) @arguments *> $log
    if($LASTEXITCODE -ne 0){throw "$exe failed ($LASTEXITCODE); see $log"}
}
$work=Join-Path $out 'work'
if(!(Test-Path $work)){Invoke-Logged 'vlib.exe' @($work) 'vlib.log'}
Invoke-Logged 'vmap.exe' @('ddr_status_video_work',$work) 'vmap.log'
Invoke-Logged 'vlog.exe' @('-sv','-work',$work,(Join-Path $PSScriptRoot 'ddr_status_video.v'),(Join-Path $PSScriptRoot 'tb_ddr_status_video.sv')) 'compile.log'
$do=Join-Path $out 'run_status.do'
@('onerror {quit -code 2 -force}','onbreak {resume}','onfinish stop','run -all',
 'set p [examine -value -radix binary -noshowbase sim:/tb_ddr_status_video/test_passed]',
 'if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -code 3 -force}',
 'quit -code 0 -force') | Set-Content -Encoding ascii $do
Invoke-Logged 'vsim.exe' @('-c','-voptargs=+acc','ddr_status_video_work.tb_ddr_status_video','-do',$do) 'simulation.log'
$text=Get-Content (Join-Path $out 'simulation.log') -Raw
if(!$text.Contains('DDR_STATUS_VIDEO_PASS')){throw "Missing status video pass marker; see $(Join-Path $out 'simulation.log')"}
$text -split "`r?`n" | Where-Object {$_ -match 'DDR_STATUS_VIDEO_PASS'}
