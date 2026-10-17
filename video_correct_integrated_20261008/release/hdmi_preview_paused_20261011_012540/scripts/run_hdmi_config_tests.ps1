$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$vsim = 'C:\modeltech64_2020.4\win64\vsim.exe'
$out = Join-Path $root 'results\hdmi_startup_fix'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$originalTxFirst = $env:TX_FIRST
try {
    foreach ($order in @('0', '1')) {
        $env:TX_FIRST = $order
        if ($order -eq '1') { $logName = 'tx_first.log' } else { $logName = 'rx_first.log' }
        $log = Join-Path $out $logName
        & $vsim -c -do (Join-Path $root 'sim\run_hdmi_config.do') *> $log
        if ($LASTEXITCODE -ne 0) { throw "HDMI config simulation failed for TX_FIRST=$order; see $log" }
        $logText = Get-Content -LiteralPath $log -Raw
        foreach ($marker in @('TEST_PASS_CONFIG', 'TEST_PASS_BOOTSTRAP_NACK_RECOVERY', 'TEST_PASS_POSTPROBE_NACK_FATAL', 'TEST_PASS_NO_DEVICE')) {
            if (!$logText.Contains($marker)) { throw "Missing $marker for TX_FIRST=$order; see $log" }
        }
        "TX_FIRST=$order PASS: normal init, bootstrap-NACK retry, post-probe fatal NACK, missing-device readiness" 
    }
}
finally {
    if ($null -eq $originalTxFirst) { Remove-Item Env:TX_FIRST -ErrorAction SilentlyContinue }
    else { $env:TX_FIRST = $originalTxFirst }
}
