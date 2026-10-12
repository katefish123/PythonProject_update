param(
    [ValidateSet('compile', 'report_timing', 'gen_bit_stream')]
    [string]$Run = 'gen_bit_stream'
)

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'HDMI_IN_DDR3_YCbCr.pds'
$pdsShell = Get-ChildItem 'C:\Pango' -Recurse -Filter pds_shell.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $pdsShell) {
    $pdsShell = (Get-Command pds_shell.exe -ErrorAction Stop).Source
}

& $pdsShell -project $project -run $Run
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($Run -eq 'report_timing') {
    $report = Join-Path $PSScriptRoot 'report_timing\HDMI_IN_DDR3_ROI_top.rtr'
    if (-not (Select-String -LiteralPath $report -SimpleMatch 'Design Summary : All Constraints Met.' -Quiet)) {
        throw "Timing constraints were not met. See $report"
    }
}

if ($Run -eq 'gen_bit_stream') {
    $bitstream = Join-Path $PSScriptRoot 'generate_bitstream\HDMI_IN_DDR3_ROI_top.sbit'
    if (-not (Test-Path -LiteralPath $bitstream)) {
        throw "PDS did not create $bitstream"
    }
    Get-Item -LiteralPath $bitstream | Select-Object FullName, Length, LastWriteTime
}
