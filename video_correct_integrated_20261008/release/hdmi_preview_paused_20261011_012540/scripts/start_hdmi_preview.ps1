$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$captureDir = Join-Path $projectRoot 'results\hardware_20261009'
$statePath = Join-Path $captureDir 'live_preview_processes.json'
$framePath = Join-Path $captureDir 'live_latest.jpg'
$pythonPath = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$binariesDir = Join-Path $projectRoot 'tools\python_packages\imageio_ffmpeg\binaries'
$previewScript = Join-Path $PSScriptRoot 'hdmi_preview.py'
$null = New-Item -ItemType Directory -Path $captureDir -Force

$hashBytes = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($projectRoot.ToLowerInvariant()))
$mutexName = 'Local\CodexHdmiPreview_' + ([BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16))
$mutex = [Threading.Mutex]::new($false, $mutexName)
$hasMutex = $false

function Get-ProcessInfo([int]$ProcessId) {
    Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
}

function Test-ExpectedCapture($ProcessInfo, [string]$FfmpegPath) {
    if (-not $ProcessInfo) { return $false }
    return ($ProcessInfo.ExecutablePath -ieq $FfmpegPath -and
        $ProcessInfo.CommandLine.Contains('video=VC-002Pro ') -and
        $ProcessInfo.CommandLine.Contains($framePath) -and
        ($ProcessInfo.CommandLine.Contains('fps=2') -or
         $ProcessInfo.CommandLine.Contains('noise=amount=0:drop=mod(n')))
}

function Test-ExpectedServer($ProcessInfo) {
    if (-not $ProcessInfo) { return $false }
    return ($ProcessInfo.ExecutablePath -ieq $pythonPath -and
        $ProcessInfo.CommandLine.Contains($previewScript))
}

try {
    $hasMutex = $mutex.WaitOne(0)
    if (-not $hasMutex) { throw '启动脚本正在运行，请稍后重试。' }

    $ffmpeg = Get-ChildItem -LiteralPath $binariesDir -Filter '*.exe' -File |
        Where-Object { $_.Name -like 'ffmpeg*' } | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $ffmpeg) { throw "未找到 FFmpeg：$binariesDir" }
    if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) { throw "未找到捆绑 Python：$pythonPath" }

    $previousState = $null
    $ownedCapture = $null
    $captureAlreadyRunning = $false
    if (Test-Path -LiteralPath $statePath) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.projectRoot -ine $projectRoot) { throw 'PID 记录的工程路径不匹配；为避免操作其他程序，已停止启动。' }
        $previousState = $state
        $ownedCapture = Get-ProcessInfo ([int]$state.capturePid)
        if (Test-ExpectedCapture $ownedCapture $state.ffmpegPath) {
            $captureAlreadyRunning = $true
            Write-Output "HDMI 采集已运行（PID $($state.capturePid)），将检查预览服务。"
        }
        if ($ownedCapture -and -not $captureAlreadyRunning) {
            throw 'PID 记录对应的进程已变化；为避免操作其他程序，未启动新采集。请先检查 live_preview_processes.json。'
        }
    }

    if (-not $captureAlreadyRunning) {
        $captureProcesses = Get-CimInstance Win32_Process | Where-Object {
            $_.Name -like 'ffmpeg*' -and $_.CommandLine -and
            $_.CommandLine.Contains('video=VC-002Pro ') -and $_.CommandLine.Contains('-f dshow')
        }
        if ($captureProcesses) {
            $ids = ($captureProcesses | ForEach-Object { $_.ProcessId }) -join ', '
            throw "检测到可能正在占用 VC-002Pro 的采集进程（PID $ids）；未重复打开采集卡。"
        }
    }

    $serverPid = $null
    $listener = Get-NetTCPConnection -LocalPort 8766 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($listener) {
        $listenerInfo = Get-ProcessInfo ([int]$listener.OwningProcess)
        if (-not (Test-ExpectedServer $listenerInfo)) {
            throw "本机端口 8766 已被其他程序占用（PID $($listener.OwningProcess)）；未启动采集。"
        }
        if ($previousState -and [int]$previousState.serverPid -eq [int]$listener.OwningProcess) {
            $serverPid = [int]$listener.OwningProcess
        }
        Write-Output "复用已运行的本机预览服务（PID $($listener.OwningProcess)）。"
    }

    if (-not $listener -and $previousState -and $previousState.serverPid) {
        $previousServer = Get-ProcessInfo ([int]$previousState.serverPid)
        if (Test-ExpectedServer $previousServer) {
            throw "之前记录的预览服务进程仍在运行（PID $($previousState.serverPid)），但端口 8766 未监听；为避免重复启动，已停止启动。"
        }
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $captureLog = Join-Path $captureDir "live_capture_$stamp.log"
    $captureStdout = Join-Path $captureDir "live_capture_$stamp.stdout.log"
    $quotedFrame = '"' + $framePath + '"'
    $ffmpegArguments = @(
        '-hide_banner', '-y', '-loglevel', 'info', '-nostats',
        '-rtbufsize', '128M', '-f', 'dshow', '-video_size', '1920x1080', '-framerate', '30', '-vcodec', 'mjpeg',
        '-i', '"video=VC-002Pro "', '-an', '-c:v', 'copy',
        '-bsf:v', '"noise=amount=0:drop=mod(n\,15)"',
        '-f', 'image2', '-atomic_writing', '1', '-update', '1', $quotedFrame
    ) -join ' '
    if (-not $captureAlreadyRunning) {
        $capture = Start-Process -FilePath $ffmpeg.FullName -ArgumentList $ffmpegArguments -WorkingDirectory $projectRoot `
            -WindowStyle Hidden -PassThru -RedirectStandardError $captureLog -RedirectStandardOutput $captureStdout
        Start-Sleep -Milliseconds 700
        $capture.Refresh()
        if ($capture.HasExited) { throw "FFmpeg 已退出，检查日志：$captureLog" }
        $capturePid = $capture.Id
    } else {
        $capturePid = [int]$previousState.capturePid
    }

    if (-not $listener) {
        $serverLog = Join-Path $captureDir "preview_server_$stamp.log"
        $serverErrorLog = Join-Path $captureDir "preview_server_$stamp.stderr.log"
        $server = Start-Process -FilePath $pythonPath -ArgumentList @('-u', ('"' + $previewScript + '"')) `
            -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $serverLog -RedirectStandardError $serverErrorLog
        $serverPid = $server.Id
        Start-Sleep -Milliseconds 500
        $server.Refresh()
        if ($server.HasExited) {
            if (-not $captureAlreadyRunning) { Stop-Process -Id $capture.Id -ErrorAction SilentlyContinue }
            throw "预览服务启动失败，检查日志：$serverLog"
        }
    }

    [ordered]@{
        projectRoot = $projectRoot
        capturePid = $capturePid
        ffmpegPath = if ($captureAlreadyRunning) { $previousState.ffmpegPath } else { $ffmpeg.FullName }
        serverPid = $serverPid
        pythonPath = $pythonPath
        previewScript = $previewScript
        startedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8

    if ($captureAlreadyRunning) {
        Write-Output "HDMI 采集继续运行（PID $capturePid）。"
    } else {
        Write-Output "HDMI 采集已隐藏启动（PID $capturePid），日志：$captureLog"
    }
    if ($serverPid) { Write-Output "本机预览服务已启动（PID $serverPid）。" }
    Write-Output '预览地址：http://127.0.0.1:8766/'
}
finally {
    if ($hasMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
