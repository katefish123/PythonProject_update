$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$simBin = Split-Path (Get-Command vsim.exe -ErrorAction Stop).Source -Parent
$vlib = Join-Path $simBin 'vlib.exe'
$vmap = Join-Path $simBin 'vmap.exe'
$vlog = Join-Path $simBin 'vlog.exe'
$vsim = Join-Path $simBin 'vsim.exe'
$py = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$out = Join-Path $env:TEMP "ddr_full_frame_$PID"
$archive = Join-Path $root 'results\ddr_fixture'
New-Item -ItemType Directory -Force -Path $out,$archive | Out-Null
& $py (Join-Path $root 'scripts\make_ddr_fixture.py') *> (Join-Path $archive 'fixture_generation.log')
if ($LASTEXITCODE -ne 0) { throw 'Fixture generation failed; see results/ddr_fixture/fixture_generation.log' }
Copy-Item -LiteralPath (Join-Path $root 'modelsim.ini') -Destination (Join-Path $out 'modelsim.ini')
function Invoke-Logged([string]$exe,[string[]]$arguments,[string]$logName) {
    $log=Join-Path $out $logName
    & $exe @arguments *> $log
    if ($LASTEXITCODE -ne 0) { throw "$exe failed ($LASTEXITCODE); see $log" }
}
$lib='ddr_full_frame'
$work=Join-Path $out 'work'
Invoke-Logged $vlib @($work) 'vlib.log'
Push-Location $root
try {
    Invoke-Logged $vmap @($lib,$work) 'vmap.log'
    $rtl=@(
      (Join-Path $root 'rtl\algo\marker_detector.v'),
      (Join-Path $root 'vendor\b\rtl\unsigned_div_seq.v'),
      (Join-Path $root 'vendor\b\rtl\signed_div_seq.v'),
      (Join-Path $root 'vendor\b\rtl\scaled_div_pipe.v'),
      (Join-Path $root 'vendor\b\rtl\perspective_coord.v'),
      (Join-Path $root 'vendor\b\rtl\homography_solver.v'),
      (Join-Path $root 'vendor\b\rtl\perspective_core.v'),
      (Join-Path $root 'vendor\b\rtl\bilinear_interp.v'),
      (Join-Path $root 'vendor\b\rtl\b_rectifier.v'),
      (Join-Path $root 'rtl\top\frame_processor.v'),
      (Join-Path $root 'rtl\memory\ddr_pixel_cache.v'),
      (Join-Path $root 'rtl\memory\ddr_result_writer.v'),
      (Join-Path $root 'sim\tb_ddr_full_frame.sv')
    )
    Invoke-Logged $vlog (@('-sv','-work',$lib)+$rtl) 'compile.log'
    Copy-Item -LiteralPath (Join-Path $out 'compile.log') -Destination (Join-Path $archive 'compile.log') -Force
    $do=Join-Path $out 'tb_ddr_full_frame.do'
    @('onerror {quit -code 1 -f}','onfinish stop','run -all','quit -code 0 -f') | Set-Content -Encoding ascii $do
    $log=Join-Path $out 'tb_ddr_full_frame.log'
    & $vsim -c -voptargs=+acc "$lib.tb_ddr_full_frame" -do $do *> $log
    if ($LASTEXITCODE -ne 0) { throw "ModelSim failed; see $log" }
    $text=Get-Content $log -Raw
    if (!$text.Contains('DDR_FULL_FRAME_PASS') -or $text -match 'Fatal:|TEST_FAIL|Error:|Errors: [1-9]') { throw "Full-frame regression did not pass; see $log" }
    Copy-Item -LiteralPath $log -Destination (Join-Path $archive 'tb_ddr_full_frame.log') -Force
    'Full-frame DDR fixture simulation passed.' | Set-Content -Encoding ascii (Join-Path $archive 'summary.txt')
    $text -split "`r?`n" | Where-Object { $_ -match 'DDR_FULL_FRAME_(PASS|ADDR|CYCLES)' }
} finally { Pop-Location }
Write-Output "Logs: $out"
