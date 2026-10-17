$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$obsExe = Join-Path $taskRoot 'tools\obs-studio\portable\bin\64bit\obs64.exe'
if (!(Test-Path -LiteralPath $obsExe -PathType Leaf)) { throw 'OBS portable package is not prepared.' }
$statePath = Join-Path $taskRoot 'results\hardware_20261009\live_preview_processes.json'
if (Test-Path -LiteralPath $statePath) {
    $previewState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $captureInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($previewState.capturePid)" -ErrorAction SilentlyContinue
    if ($captureInfo -and $captureInfo.ExecutablePath -ieq $previewState.ffmpegPath -and
        $captureInfo.CommandLine.Contains((Join-Path $taskRoot 'results\hardware_20261009\live_latest.jpg'))) {
        Stop-Process -Id $captureInfo.ProcessId
    }
}
$runningObs = Get-CimInstance Win32_Process -Filter "Name = 'obs64.exe'" |
    Where-Object { $_.ExecutablePath -ieq $obsExe }
if (!$runningObs) {
    Start-Process -FilePath $obsExe -WorkingDirectory (Split-Path -Parent $obsExe) `
        -ArgumentList @('--portable','--profile','FPGA','--collection','FPGA') -WindowStyle Normal
}
Write-Output 'OBS FPGA capture viewer is ready. Actual capture format is shown in its device properties and log.'
