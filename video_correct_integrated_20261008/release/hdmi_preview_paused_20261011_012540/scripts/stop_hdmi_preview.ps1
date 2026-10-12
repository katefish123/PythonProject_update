$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$statePath = Join-Path $projectRoot 'results\hardware_20261009\live_preview_processes.json'
$pythonPath = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$previewScript = Join-Path $PSScriptRoot 'hdmi_preview.py'

function Get-ProcessInfo([int]$ProcessId) {
    Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    Write-Output '没有本脚本记录的进程需要停止。'
    exit 0
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ($state.projectRoot -ine $projectRoot) { throw 'PID 记录的工程路径不匹配；未停止任何进程。' }

$captureInfo = Get-ProcessInfo ([int]$state.capturePid)
if ($captureInfo) {
    $isOwnedCapture = ($captureInfo.ExecutablePath -ieq [string]$state.ffmpegPath -and
        $captureInfo.CommandLine.Contains('video=VC-002Pro ') -and
        $captureInfo.CommandLine.Contains((Join-Path $projectRoot 'results\hardware_20261009\live_latest.jpg')) -and
        ($captureInfo.CommandLine.Contains('fps=2') -or
         $captureInfo.CommandLine.Contains('noise=amount=0:drop=mod(n')))
    if (-not $isOwnedCapture) { throw "采集 PID $($state.capturePid) 的路径或命令行不匹配；未停止任何进程。" }
    Stop-Process -Id ([int]$state.capturePid)
    Write-Output "已停止本脚本启动的 HDMI 采集（PID $($state.capturePid)）。"
}

if ($state.serverPid) {
    $serverInfo = Get-ProcessInfo ([int]$state.serverPid)
    if ($serverInfo) {
        $isOwnedServer = ($serverInfo.ExecutablePath -ieq $pythonPath -and
            $serverInfo.CommandLine.Contains($previewScript))
        if (-not $isOwnedServer) { throw "预览服务 PID $($state.serverPid) 的路径或命令行不匹配；未停止该进程。" }
        Stop-Process -Id ([int]$state.serverPid)
        Write-Output "已停止本脚本启动的本机预览服务（PID $($state.serverPid)）。"
    }
}

Remove-Item -LiteralPath $statePath -Force
Write-Output '本脚本启动的进程已清理。'
