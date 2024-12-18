# 言栖 启动/停止/重启脚本（Windows PowerShell）
# 用法: .\yanqi.ps1 {start|stop|restart|status} [backend|frontend|all]

param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "restart", "status", "")]
    [string]$Command = "",

    [Parameter(Position = 1)]
    [ValidateSet("backend", "frontend", "all")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackendDir = Join-Path $ProjectDir "back"
$FrontendDir = Join-Path $ProjectDir "front"
$LogDir = Join-Path $ProjectDir "log"
$VenvPython = Join-Path $BackendDir "venv\Scripts\python.exe"
$BackendPidFile = Join-Path $env:TEMP "yanqi_backend.pid"
$FrontendPidFile = Join-Path $env:TEMP "yanqi_frontend.pid"

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[ERR] $msg" -ForegroundColor Red }

function Get-PidOnPort([int]$Port) {
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($conn) { return $conn.OwningProcess }
    } catch {}
    return $null
}

function Test-PidRunning([int]$ProcessId) {
    try {
        $null = Get-Process -Id $ProcessId -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Read-PidFile([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $raw = (Get-Content $Path -Raw).Trim()
    if ($raw -match '^\d+$') { return [int]$raw }
    return $null
}

function Test-BackendRunning {
    $pidVal = Read-PidFile $BackendPidFile
    if ($pidVal -and (Test-PidRunning $pidVal)) { return $true }
    return $null -ne (Get-PidOnPort 8001)
}

function Test-FrontendRunning {
    $pidVal = Read-PidFile $FrontendPidFile
    if ($pidVal -and (Test-PidRunning $pidVal)) { return $true }
    return $null -ne (Get-PidOnPort 5173)
}

function Start-Backend {
    Write-Info "启动后端服务..."
    if (Test-BackendRunning) {
        Write-Warn "后端服务已在运行 (端口: 8001)"
        return
    }
    if (-not (Test-Path $VenvPython)) {
        Write-Err "未找到 Python 虚拟环境: $VenvPython"
        Write-Err "请先执行: cd back; python -m venv venv; .\venv\Scripts\activate; pip install -r requirements.txt"
        exit 1
    }

    & $VenvPython -c "import fastapi" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "检测到依赖未安装，正在安装..."
        & $VenvPython -m pip install -r (Join-Path $BackendDir "requirements.txt") -q
    }

    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
    $outLog = Join-Path $LogDir "backend.log"
    $errLog = Join-Path $LogDir "backend.err.log"

    $proc = Start-Process -FilePath $VenvPython `
        # 不用 --reload：Windows 下 reloader 可能改用系统 Python，导致 MCP 只部分加载
        -ArgumentList "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001" `
        -WorkingDirectory $BackendDir `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog `
        -WindowStyle Hidden `
        -PassThru

    Set-Content -Path $BackendPidFile -Value $proc.Id -Encoding ascii
    # MCP（npx）冷启动较慢，多等一会再报成功
    Start-Sleep -Seconds 8

    if (Test-PidRunning $proc.Id) {
        Write-Ok "后端服务已启动 (PID: $($proc.Id))"
        Write-Info "API 文档: http://localhost:8001/docs"
        Write-Info "MCP 工具仍在后台加载时，工具列表可能稍后才齐全"
    } else {
        Write-Err "后端服务启动失败，请检查日志: $outLog / $errLog"
        Remove-Item $BackendPidFile -ErrorAction SilentlyContinue
        exit 1
    }
}

function Stop-Backend {
    Write-Info "停止后端服务..."
    $pidVal = Read-PidFile $BackendPidFile
    if ($pidVal -and (Test-PidRunning $pidVal)) {
        Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
        # 再按端口清理残留子进程
        Start-Sleep -Seconds 1
        $portPid = Get-PidOnPort 8001
        if ($portPid) { Stop-Process -Id $portPid -Force -ErrorAction SilentlyContinue }
        Write-Ok "后端服务已停止 (PID: $pidVal)"
        Remove-Item $BackendPidFile -ErrorAction SilentlyContinue
        return
    }
    $portPid = Get-PidOnPort 8001
    if ($portPid) {
        Stop-Process -Id $portPid -Force -ErrorAction SilentlyContinue
        Write-Ok "后端服务已停止 (端口进程 PID: $portPid)"
    } else {
        Write-Warn "未发现运行中的后端进程"
    }
    Remove-Item $BackendPidFile -ErrorAction SilentlyContinue
}

function Start-Frontend {
    Write-Info "启动前端服务..."
    if (Test-FrontendRunning) {
        Write-Warn "前端服务已在运行 (端口: 5173)"
        return
    }
    $nodeModules = Join-Path $FrontendDir "node_modules"
    if (-not (Test-Path $nodeModules)) {
        Write-Info "检测到 node_modules 不存在，正在安装依赖..."
        Push-Location $FrontendDir
        try { npm install } finally { Pop-Location }
    }

    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
    $outLog = Join-Path $LogDir "frontend.log"
    $errLog = Join-Path $LogDir "frontend.err.log"

    $npmCmd = (Get-Command npm -ErrorAction Stop).Source
    $proc = Start-Process -FilePath $npmCmd `
        -ArgumentList "run", "dev", "--", "--host" `
        -WorkingDirectory $FrontendDir `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog `
        -WindowStyle Hidden `
        -PassThru

    Set-Content -Path $FrontendPidFile -Value $proc.Id -Encoding ascii
    Start-Sleep -Seconds 3

    if (Test-PidRunning $proc.Id) {
        Write-Ok "前端服务已启动 (PID: $($proc.Id))"
        Write-Info "前端地址: http://localhost:5173"
    } else {
        Write-Err "前端服务启动失败，请检查日志: $outLog / $errLog"
        Remove-Item $FrontendPidFile -ErrorAction SilentlyContinue
        exit 1
    }
}

function Stop-Frontend {
    Write-Info "停止前端服务..."
    $pidVal = Read-PidFile $FrontendPidFile
    if ($pidVal -and (Test-PidRunning $pidVal)) {
        Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $portPid = Get-PidOnPort 5173
        if ($portPid) { Stop-Process -Id $portPid -Force -ErrorAction SilentlyContinue }
        Write-Ok "前端服务已停止 (PID: $pidVal)"
        Remove-Item $FrontendPidFile -ErrorAction SilentlyContinue
        return
    }
    $portPid = Get-PidOnPort 5173
    if ($portPid) {
        Stop-Process -Id $portPid -Force -ErrorAction SilentlyContinue
        Write-Ok "前端服务已停止 (端口进程 PID: $portPid)"
    } else {
        Write-Warn "未发现运行中的前端进程"
    }
    Remove-Item $FrontendPidFile -ErrorAction SilentlyContinue
}

function Show-BackendStatus {
    $pidVal = Read-PidFile $BackendPidFile
    if ($pidVal -and (Test-PidRunning $pidVal)) {
        Write-Host "  后端: " -NoNewline
        Write-Host "运行中" -ForegroundColor Green -NoNewline
        Write-Host " (PID: $pidVal)  端口: 8001"
        return
    }
    $portPid = Get-PidOnPort 8001
    if ($portPid) {
        Write-Host "  后端: " -NoNewline
        Write-Host "运行中" -ForegroundColor Green -NoNewline
        Write-Host " (PID: $portPid, 非脚本管理)  端口: 8001"
        return
    }
    Write-Host "  后端: " -NoNewline
    Write-Host "未运行" -ForegroundColor Red
}

function Show-FrontendStatus {
    $pidVal = Read-PidFile $FrontendPidFile
    if ($pidVal -and (Test-PidRunning $pidVal)) {
        Write-Host "  前端: " -NoNewline
        Write-Host "运行中" -ForegroundColor Green -NoNewline
        Write-Host " (PID: $pidVal)  端口: 5173"
        return
    }
    $portPid = Get-PidOnPort 5173
    if ($portPid) {
        Write-Host "  前端: " -NoNewline
        Write-Host "运行中" -ForegroundColor Green -NoNewline
        Write-Host " (PID: $portPid, 非脚本管理)  端口: 5173"
        return
    }
    Write-Host "  前端: " -NoNewline
    Write-Host "未运行" -ForegroundColor Red
}

function Show-BackendHealth {
    if (-not (Test-BackendRunning)) {
        Write-Host "  API 健康: " -NoNewline
        Write-Host "未运行" -ForegroundColor Red
        return
    }
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:8001/api/health" -UseBasicParsing -TimeoutSec 2
        if ($resp.StatusCode -eq 200) {
            Write-Host "  API 健康: " -NoNewline
            Write-Host "OK" -ForegroundColor Green
            return
        }
    } catch {}
    Write-Host "  API 健康: " -NoNewline
    Write-Host "进程在运行但 API 未响应" -ForegroundColor Yellow
}

function Show-Usage {
    Write-Host @"
用法: .\yanqi.ps1 {start|stop|restart|status} [backend|frontend|all]

  命令:
    start    启动服务
    stop     停止服务
    restart  重启服务
    status   查看服务状态

  目标 (可选, 默认: all):
    backend  仅操作后端
    frontend 仅操作前端
    all      操作前后端 (默认)

  示例:
    .\yanqi.ps1 start
    .\yanqi.ps1 start backend
    .\yanqi.ps1 stop frontend
    .\yanqi.ps1 status
"@
}

if (-not $Command) {
    Show-Usage
    exit 1
}

switch ($Command) {
    "start" {
        Write-Host ""
        Write-Host "=============================="
        Write-Host "  言栖 启动"
        Write-Host "=============================="
        switch ($Target) {
            "backend"  { Start-Backend }
            "frontend" { Start-Frontend }
            "all" {
                Start-Backend
                Start-Frontend
                Write-Host ""
                Write-Host "=============================="
                Write-Host "  言栖 服务已全部启动" -ForegroundColor Green
                Write-Host "  后端:  http://localhost:8001"
                Write-Host "  前端:  http://localhost:5173"
                Write-Host "  API:   http://localhost:8001/docs"
                Write-Host "=============================="
            }
        }
    }
    "stop" {
        Write-Host ""
        Write-Host "=============================="
        Write-Host "  言栖 停止"
        Write-Host "=============================="
        switch ($Target) {
            "backend"  { Stop-Backend }
            "frontend" { Stop-Frontend }
            "all" {
                Stop-Frontend
                Stop-Backend
                Write-Ok "言栖 所有服务已停止"
            }
        }
    }
    "restart" {
        Write-Host ""
        Write-Host "=============================="
        Write-Host "  言栖 重启 ($Target)"
        Write-Host "=============================="
        & $PSCommandPath stop $Target
        Start-Sleep -Seconds 1
        & $PSCommandPath start $Target
    }
    "status" {
        Write-Host ""
        Write-Host "=============================="
        Write-Host "  言栖 服务状态"
        Write-Host "=============================="
        if ($Target -eq "all" -or $Target -eq "backend") { Show-BackendStatus }
        if ($Target -eq "all" -or $Target -eq "frontend") { Show-FrontendStatus }
        Write-Host ""
        if ($Target -eq "all" -or $Target -eq "backend") { Show-BackendHealth }
        Write-Host "=============================="
    }
}
