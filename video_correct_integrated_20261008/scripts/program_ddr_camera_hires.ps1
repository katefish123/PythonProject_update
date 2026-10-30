$ErrorActionPreference = 'Stop'
$integrationRoot = Split-Path -Parent $PSScriptRoot
$releaseRoot = Join-Path $integrationRoot 'release\ddr_camera_hires_20261011'
$qualification = Get-Content -LiteralPath (Join-Path $releaseRoot 'build_qualification.json') -Raw | ConvertFrom-Json
if (-not $qualification.simulations_passed -or -not $qualification.timing_passed) { throw 'DDR camera release is not qualified' }
foreach ($file in $qualification.files.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $releaseRoot $file.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.Value) { throw "Release checksum mismatch: $($file.Name)" }
}
$hardwareRoot = Join-Path $integrationRoot 'results\hardware_20261009'
$taskStamp = [DateTime]::UtcNow.AddHours(8).ToString('yyyyMMdd_HHmmss')
$programLog = Join-Path $hardwareRoot "program_ddr_camera_hires_$taskStamp.log"
$pdsBin = 'C:\pango\PDS_2022.2-SP6.4\bin'
$listener = Get-NetTCPConnection -LocalPort 65420 -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
    Start-Process -FilePath (Join-Path $pdsBin 'cdt_js.exe') -ArgumentList @('-port','65420','-work_dir',$hardwareRoot) -WorkingDirectory $hardwareRoot -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 2
}
& (Join-Path $pdsBin 'cdt_cfg_shell.exe') -file (Join-Path $integrationRoot 'pds\program_ddr_camera_hires.tcl') *> $programLog
$programExit = $LASTEXITCODE
$programText = Get-Content -LiteralPath $programLog -Raw
if ($programExit -ne 0 -or $programText -notmatch 'COMMAND\[Program\] execute successfully' -or $programText -notmatch 'COMMAND\[Verify\] execute successfully' -or $programText -match 'execute fail|exec failed|Fail to compare|\*\* Error') { throw "DDR Program/Verify failed. Log: $programLog" }
[ordered]@{utc=[DateTime]::UtcNow.ToString('o');bitstream_sha256=$qualification.files.'video_correct_ddr_top.sbit';program_verify_passed=$true;flash_modified=$false;log=$programLog;actual_camera_correction_accepted=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $hardwareRoot "ddr_camera_hires_program_$taskStamp.json") -Encoding utf8
Write-Output "Program and Verify passed. Log: $programLog"
