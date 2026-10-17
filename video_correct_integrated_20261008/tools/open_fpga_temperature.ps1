param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$integrationRoot = Split-Path -Parent $PSScriptRoot
$temperatureWorkDir = Join-Path $integrationRoot 'results\hardware_20261009\thermal_adc_watch'
$pdsBin = 'C:\pango\PDS_2022.2-SP6.4\bin'
$debuggerExe = Join-Path $pdsBin 'cdt_dbg.exe'
$serverExe = Join-Path $pdsBin 'cdt_js.exe'
foreach ($requiredPath in @($temperatureWorkDir, $debuggerExe, $serverExe)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required temperature tool path missing: $requiredPath" }
}
# CheckOnly validates local files and syntax without starting software or accessing JTAG.
if ($CheckOnly) { Write-Output 'TEMPERATURE_TOOL_CHECK_PASS'; return }
# Opening this helper starts the server and debugger. Device scan and ADC monitoring remain manual.
# No configuration shell, Program, Verify, CRAM download, or Flash operation is invoked.
$temperatureListener = Get-NetTCPConnection -LocalPort 65420 -State Listen -ErrorAction SilentlyContinue
if (-not $temperatureListener) {
    Start-Process -FilePath $serverExe -ArgumentList @('-port', '65420', '-work_dir', $temperatureWorkDir) -WorkingDirectory $temperatureWorkDir -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 2
    if (-not (Get-NetTCPConnection -LocalPort 65420 -State Listen -ErrorAction SilentlyContinue)) {
        throw 'Temperature JTAG server failed to start on port 65420'
    }
}
Start-Process -FilePath $debuggerExe -WorkingDirectory $temperatureWorkDir | Out-Null
Write-Output 'Temperature tool opened. Connect to 127.0.0.1:65420, scan PG2L100H, and open ADC Console.'
