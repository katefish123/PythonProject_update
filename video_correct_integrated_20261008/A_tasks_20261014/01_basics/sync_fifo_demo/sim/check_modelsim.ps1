param([string]$ModelSimBin='C:\modeltech64_2020.4\win64')
$ErrorActionPreference='Stop'
foreach ($test in @(
    @{Folder='basic'; Top='tb_fifo_basic'; Marker='PASS: basic FIFO simulation'},
    @{Folder='boundary'; Top='tb_sync_fifo'; Marker='PASS: 1124 checks'}
)) {
    Push-Location (Join-Path $PSScriptRoot $test.Folder)
    try {
        if (!(Test-Path work)) {
            & "$ModelSimBin\vlib.exe" work
            if ($LASTEXITCODE) {throw 'vlib failed'}
        }
        & "$ModelSimBin\vlog.exe" -work work ../../rtl/sync_fifo.v "$($test.Top).v" -l compile_check.log
        if ($LASTEXITCODE) {throw 'vlog failed'}
        & "$ModelSimBin\vsim.exe" -c -onfinish stop "work.$($test.Top)" -do 'run -all; quit -force' -l modelsim_check.log
        if ($LASTEXITCODE) {throw 'vsim failed'}
        if (Select-String -Path modelsim_check.log -SimpleMatch 'FAIL' -Quiet) {throw 'Test reported FAIL'}
        if (!(Select-String -Path modelsim_check.log -SimpleMatch $test.Marker -Quiet)) {throw 'PASS marker absent'}
    } finally {Pop-Location}
}
