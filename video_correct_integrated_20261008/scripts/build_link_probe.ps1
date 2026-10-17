param([string]$OutputName = 'hdmi_link_probe')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pythonExe = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$pdsExe = 'C:\pango\PDS_2022.2-SP6.4\bin\pds_shell.exe'
$outputDir = Join-Path $root (Join-Path 'results' $OutputName)
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

& $pythonExe (Join-Path $PSScriptRoot 'prepare_link_probe.py') *> (Join-Path $outputDir 'prepare.log')
if ($LASTEXITCODE -ne 0) { throw "Probe preparation failed; see $(Join-Path $outputDir 'prepare.log')" }
$flow = Join-Path $outputDir 'build_hdmi_link_probe.tcl'
& $pdsExe -file $flow -work_dir $outputDir -project_name hdmi_link_probe *> (Join-Path $outputDir 'build.log')
$pdsExit = $LASTEXITCODE
if ($pdsExit -ne 0) { throw "PDS probe build failed with exit code $pdsExit; see $(Join-Path $outputDir 'build.log')" }

$timingReports = @(Get-ChildItem -Path $outputDir -Recurse -File | Where-Object {
    $_.Name -match 'timing_summary.*\.(txt|rpt|log)$'
})
$constraintReport = $timingReports | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw) -match '(?i)All Constraints Met'
} | Select-Object -First 1
if (!$constraintReport) {
    throw "PDS completed, but no timing summary reported 'All Constraints Met'; inspect $outputDir"
}
$bitstream = Get-ChildItem -Path $outputDir -Recurse -File | Where-Object {
    $_.Extension -match '^\.(bit|fs|bin|sbit)$'
} | Select-Object -First 1
if (!$bitstream) { throw "PDS completed without a recognizable bitstream in $outputDir" }
$mask = Join-Path $bitstream.DirectoryName ($bitstream.BaseName + '.smsk')
if (!(Test-Path -LiteralPath $mask -PathType Leaf)) {
    throw "Matching Pango mask file was not found beside $($bitstream.FullName)"
}
$bitHash = (Get-FileHash -LiteralPath $bitstream.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$maskHash = (Get-FileHash -LiteralPath $mask -Algorithm SHA256).Hash.ToLowerInvariant()

@(
    "Build result: PASS",
    "PDS exit code: $pdsExit",
    "Timing: $($constraintReport.FullName)",
    "Bitstream: $($bitstream.FullName)",
    "Bitstream SHA256: $bitHash",
    "Matching mask: $mask",
    "Mask SHA256: $maskHash",
    "PDS log: $(Join-Path $outputDir 'build.log')"
) | Set-Content -LiteralPath (Join-Path $outputDir 'result.txt') -Encoding utf8
Get-Content -LiteralPath (Join-Path $outputDir 'result.txt')
