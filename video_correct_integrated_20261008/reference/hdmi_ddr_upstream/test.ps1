$ErrorActionPreference = 'Stop'
$iverilog = (Get-Command iverilog -ErrorAction Stop).Source
$vvp = (Get-Command vvp -ErrorAction Stop).Source
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("hdmi-roi-tests-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tempRoot | Out-Null

function Invoke-IcarusTest {
    param(
        [string]$Name,
        [string]$Top,
        [string[]]$Sources,
        [string]$PassMarker,
        [switch]$AllowMissingModules
    )

    $output = Join-Path $tempRoot "$Name.vvp"
    $arguments = @('-g2012', '-Wall')
    if ($AllowMissingModules) { $arguments += '-i' }
    $arguments += @('-s', $Top, '-o', $output)
    $arguments += $Sources

    & $iverilog @arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name compile failed" }
    $simOutput = (& $vvp $output 2>&1 | Out-String)
    Write-Host $simOutput.TrimEnd()
    if ($LASTEXITCODE -ne 0 -or $simOutput -notmatch [regex]::Escape($PassMarker)) {
        throw "$Name simulation failed"
    }
}

Push-Location $PSScriptRoot
try {
    Invoke-IcarusTest -Name rgb2ycbcr -Top rgb2ycbcr_tb `
        -Sources @('source/img_process/RGB2YCbCr.v', 'sim_prj/rgb2ycbcr_tb.sv') `
        -PassMarker 'RGB2YCBCR_PASS'

    Invoke-IcarusTest -Name frame_write -Top frame_buffer_control_tb `
        -Sources @('source/rtl/wr_buf.v', 'sim_prj/frame_buffer_control_tb.sv') `
        -PassMarker 'FRAME_BUFFER_CONTROL_PASS'

    Invoke-IcarusTest -Name frame_read -Top read_bank_control_tb `
        -Sources @('source/rtl/rd_buf.v', 'sim_prj/frame_buffer_control_tb.sv') `
        -PassMarker 'READ_BANK_CONTROL_PASS'

    Invoke-IcarusTest -Name scorer -Top plate_window_scorer_tb `
        -Sources @('source/rtl/Target_Analysis_Top/Plate_Window_Scorer.v', 'sim_prj/plate_window_scorer_sim/tb/plate_window_scorer_tb.sv') `
        -PassMarker 'A02R1_RESULT PASS'

    Invoke-IcarusTest -Name hdmi_top -Top hdmi_roi_top_tb `
        -Sources @('source/rtl/HDMI_IN_DDR3_ROI_top/HDMI_IN_DDR3_ROI_top.v', 'sim_prj/hdmi_roi_top_tb.sv') `
        -PassMarker 'HDMI_ROI_TOP_PASS' -AllowMissingModules

    Write-Host 'ALL_TESTS_PASS'
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
