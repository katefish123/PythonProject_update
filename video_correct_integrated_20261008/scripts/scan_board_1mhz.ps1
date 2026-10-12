$ErrorActionPreference = 'Stop'
$integrationRoot = Split-Path -Parent $PSScriptRoot
$hardwareRoot = Join-Path $integrationRoot 'results\hardware_20261009'
$taskStamp = [DateTime]::UtcNow.AddHours(8).ToString('yyyyMMdd_HHmmss')
$scanLog = Join-Path $hardwareRoot "scan_board_1mhz_$taskStamp.log"
$pdsBin = 'C:\pango\PDS_2022.2-SP6.4\bin'
$listener = Get-NetTCPConnection -LocalPort 65420 -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
    Start-Process -FilePath (Join-Path $pdsBin 'cdt_js.exe') -ArgumentList @('-port','65420','-work_dir',$hardwareRoot) -WorkingDirectory $hardwareRoot -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 2
}
& (Join-Path $pdsBin 'cdt_cfg_shell.exe') -file (Join-Path $integrationRoot 'pds\scan_board_1mhz.tcl') *> $scanLog
$scanExit = $LASTEXITCODE
$scanText = Get-Content -LiteralPath $scanLog -Raw
Write-Output "Read-only scan log: $scanLog"
if ($scanExit -ne 0 -or $scanText -match 'execute fail|exec failed|\*\* Error') {
    throw 'Read-only JTAG scan failed; inspect the saved log'
}
Write-Output $scanText
