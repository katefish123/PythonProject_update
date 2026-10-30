$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$simBin = Split-Path (Get-Command vsim.exe -ErrorAction Stop).Source -Parent
$vlib = Join-Path $simBin 'vlib.exe'
$vmap = Join-Path $simBin 'vmap.exe'
$vlog = Join-Path $simBin 'vlog.exe'
$vsim = Join-Path $simBin 'vsim.exe'
$out = Join-Path $env:TEMP "ddr_memory_tests_$PID"
$archive = Join-Path $root 'results\ddr_memory'
New-Item -ItemType Directory -Force -Path $out | Out-Null
New-Item -ItemType Directory -Force -Path $archive | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'modelsim.ini') -Destination (Join-Path $out 'modelsim.ini')

function Invoke-Logged([string]$exe, [string[]]$arguments, [string]$logName) {
    $log = Join-Path $out $logName
    & $exe @arguments *> $log
    if ($LASTEXITCODE -ne 0) { throw "$exe failed ($LASTEXITCODE); see $log" }
}

$library = 'ddr_memory_tests'
$work = Join-Path $out 'work'
Invoke-Logged $vlib @($work) 'vlib.log'
Push-Location $out
try {
    Invoke-Logged $vmap @($library, $work) 'vmap.log'
    $rtl = @(
        (Join-Path $root 'rtl\memory\ddr_word_engine.v'),
        (Join-Path $root 'rtl\memory\ddr_pixel_cache.v'),
        (Join-Path $root 'rtl\memory\ddr_command_bridge.v'),
        (Join-Path $root 'rtl\memory\ddr_arbiter3.v'),
        (Join-Path $root 'rtl\memory\ddr_result_writer.v'),
        (Join-Path $root 'rtl\memory\ddr_self_test.v')
    )
    $tests = @(
        (Join-Path $root 'sim\tb_ddr_word_engine.sv'),
        (Join-Path $root 'sim\tb_ddr_pixel_cache.sv'),
        (Join-Path $root 'sim\tb_ddr_helpers.sv')
    )
    Invoke-Logged $vlog (@('-sv', '-work', $library) + $rtl + $tests) 'compile.log'
    Copy-Item -LiteralPath (Join-Path $out 'compile.log') -Destination (Join-Path $archive 'compile.log') -Force

    $cases = @(
        @{ Name = 'tb_ddr_word_engine'; Marker = 'DDR_WORD_ENGINE_PASS' },
        @{ Name = 'tb_ddr_pixel_cache'; Marker = 'DDR_PIXEL_CACHE_PASS' },
        @{ Name = 'tb_ddr_helpers'; Marker = 'DDR_HELPERS_PASS' }
    )
    foreach ($case in $cases) {
        $test = $case.Name
        $do = Join-Path $out "$test.do"
        @('onerror {quit -code 1 -f}', 'onfinish stop', 'run -all', 'quit -code 0 -f') |
            Set-Content -Encoding ascii $do
        $log = Join-Path $out "$test.log"
        & $vsim -c -voptargs=+acc "$library.$test" -do $do *> $log
        if ($LASTEXITCODE -ne 0) { throw "ModelSim failed for $test; see $log" }
        $text = Get-Content $log -Raw
        if (!$text.Contains($case.Marker)) { throw "Missing pass marker for $test; see $log" }
        if ($text -match 'Fatal:|TEST_FAIL|Error:|Errors: [1-9]') { throw "Simulation reported an error for $test; see $log" }
        Copy-Item -LiteralPath $log -Destination (Join-Path $archive "$test.log") -Force
        $text -split "`r?`n" | Where-Object { $_ -match 'DDR_.*_PASS' }
    }
    'All DDR memory regression testbenches passed.' | Set-Content -Encoding ascii (Join-Path $archive 'summary.txt')
} finally {
    Pop-Location
}
Write-Output "Logs: $out"
