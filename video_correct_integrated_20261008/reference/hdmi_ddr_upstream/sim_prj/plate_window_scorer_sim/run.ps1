param()

$ErrorActionPreference = "Stop"

$SimRoot = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $SimRoot "..\..")).Path
$WorkDir = Join-Path $SimRoot "work"
$ResultsDir = Join-Path $SimRoot "results"
$CompileLog = Join-Path $ResultsDir "compile.log"
$SimLog = Join-Path $ResultsDir "sim.log"
$WaveFile = Join-Path $ResultsDir "plate_window_scorer.wlf"
$SummaryFile = Join-Path $ResultsDir "run_summary.txt"

$vlib = (Get-Command vlib -ErrorAction Stop).Source
$vlog = (Get-Command vlog -ErrorAction Stop).Source
$vsim = (Get-Command vsim -ErrorAction Stop).Source

if (Test-Path -LiteralPath $WorkDir) {
    Remove-Item -LiteralPath $WorkDir -Recurse -Force
}
if (Test-Path -LiteralPath $ResultsDir) {
    Remove-Item -LiteralPath $ResultsDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ResultsDir | Out-Null

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$toolVersion = (& $vsim -version 2>&1 | Out-String).Trim()

Push-Location $SimRoot
try {
    & $vlib $WorkDir *> $CompileLog
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath $CompileLog
        exit 2
    }

    & $vlog -sv -work $WorkDir `
        (Join-Path $RepoRoot "source\rtl\Target_Analysis_Top\Plate_Window_Scorer.v") `
        (Join-Path $SimRoot "tb\plate_window_scorer_tb.sv") *>> $CompileLog
    $compileExit = $LASTEXITCODE
    if ($compileExit -ne 0) {
        Get-Content -LiteralPath $CompileLog
        exit 2
    }

    $waveForModelSim = $WaveFile.Replace('\', '/')
    $doForModelSim = (Join-Path $SimRoot "run.do").Replace('\', '/')
    & $vsim -c -voptargs=+acc -wlf $waveForModelSim `
        -do "do $doForModelSim" work.plate_window_scorer_tb *> $SimLog
    $simExit = $LASTEXITCODE
}
finally {
    Pop-Location
}

$stopwatch.Stop()
$passMarker = Select-String -LiteralPath $SimLog -SimpleMatch "A02R1_RESULT PASS" -Quiet
$failMarker = Select-String -LiteralPath $SimLog -SimpleMatch "A02R1_RESULT FAIL" -Quiet

$summary = @(
    "tool=$toolVersion"
    "command=powershell -ExecutionPolicy Bypass -File .\sim_prj\plate_window_scorer_sim\run.ps1"
    "simulator_exit_code=$simExit"
    "pass_marker=$passMarker"
    "fail_marker=$failMarker"
    "elapsed_seconds=$([Math]::Round($stopwatch.Elapsed.TotalSeconds, 3))"
    "waveform=$WaveFile"
    "log=$SimLog"
)
$summary | Set-Content -LiteralPath $SummaryFile -Encoding ASCII

Get-Content -LiteralPath $SimLog
$summary | ForEach-Object { Write-Host $_ }

if (($simExit -ne 0) -or (-not $passMarker) -or $failMarker) {
    exit 1
}

exit 0
