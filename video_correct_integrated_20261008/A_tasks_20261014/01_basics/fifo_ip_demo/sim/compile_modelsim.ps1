param([string]$ModelSimBin='C:\modeltech64_2020.4\win64')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    if (!(Test-Path work)) {
        & "$ModelSimBin\vlib.exe" work
        if ($LASTEXITCODE) {throw 'vlib failed'}
    }
    $ipRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../ipcore/fifo_sync_8x512'))
    $pangoLib = 'C:\pango\PDS_2022.2-SP6.4\arch\vendor\pango\verilog\simulation'
    & "$ModelSimBin\vlog.exe" -work work "+incdir+$ipRoot/rtl" `
        "$pangoLib/GTP_GRS.v" "$pangoLib/GTP_DRM18K_E1.v" `
        "$ipRoot/rtl/ipm2l_fifo_ctrl_v1_1_fifo_sync_8x512.v" `
        "$ipRoot/rtl/ipm2l_sdpram_v1_10_fifo_sync_8x512.v" `
        "$ipRoot/rtl/ipm2l_fifo_v1_10_fifo_sync_8x512.v" `
        "$ipRoot/fifo_sync_8x512.v" ../rtl/fifo_ip_top.v tb_fifo_ip_basic.v -l compile_basic.log
    if ($LASTEXITCODE) {throw 'vlog failed'}
} finally {Pop-Location}
