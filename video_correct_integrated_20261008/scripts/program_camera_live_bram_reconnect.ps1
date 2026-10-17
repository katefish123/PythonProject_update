$ErrorActionPreference = 'Stop'
$integrationRoot = Split-Path -Parent $PSScriptRoot
$releaseRoot = Join-Path $integrationRoot 'release\camera_live_bram_reconnect_20261010'
$qualification = Get-Content -LiteralPath (Join-Path $releaseRoot 'build_qualification.json') -Raw | ConvertFrom-Json
if (-not $qualification.simulations_passed -or -not $qualification.timing_passed) {
    throw 'Raw-camera preview release is not qualified'
}
foreach ($item in $qualification.files.PSObject.Properties) {
    $actual = (Get-FileHash -LiteralPath (Join-Path $releaseRoot $item.Name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $item.Value) { throw "Release checksum mismatch: $($item.Name)" }
}
$hardwareRoot = Join-Path $integrationRoot 'results\hardware_20261009'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$programLog = Join-Path $hardwareRoot "program_camera_live_bram_reconnect_$stamp.log"
$pdsBin = 'C:\pango\PDS_2022.2-SP6.4\bin'
$listener = Get-NetTCPConnection -LocalPort 65420 -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
    Start-Process -FilePath (Join-Path $pdsBin 'cdt_js.exe') -ArgumentList @('-port','65420','-work_dir',$hardwareRoot) -WorkingDirectory $hardwareRoot -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 2
}
& (Join-Path $pdsBin 'cdt_cfg_shell.exe') -file (Join-Path $integrationRoot 'pds\program_camera_live_bram_reconnect.tcl') *> $programLog
$programExit = $LASTEXITCODE
$content = Get-Content -LiteralPath $programLog -Raw
if ($programExit -ne 0 -or $content -notmatch 'COMMAND\[Program\] execute successfully' -or
    $content -notmatch 'COMMAND\[Verify\] execute successfully' -or
    $content -match 'execute fail|exec failed|Fail to compare|\*\* Error') {
    Write-Output "Programming did not pass. Log: $programLog"
    throw 'Raw-camera preview Program/Verify failed; inspect the saved log'
}
[ordered]@{utc=[DateTime]::UtcNow.ToString('o');bitstream_sha256=$qualification.files.'camera_live_bram_top.sbit';
    program_verify_passed=$true;flash_modified=$false;log=$programLog;actual_camera_display_accepted=$false} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $hardwareRoot "camera_live_bram_reconnect_program_$stamp.json") -Encoding utf8
Write-Output "Program and Verify passed. Log: $programLog"
