$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Backend = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"
$Python = Join-Path $Backend ".venv\Scripts\python.exe"
$AppUrl = "http://localhost:3000"

# Phase 6B security: the API authenticates every non-health request with a
# bearer token. Generate one on first start and persist it in backend/.env so
# operator sessions (browser) and the backend agree on the secret.
$EnvFile = Join-Path $Backend ".env"
$ApiToken = $null
if (Test-Path $EnvFile) {
    $Match = Select-String -Path $EnvFile -Pattern '^VAYRA_API_TOKEN=(.+)$' -ErrorAction SilentlyContinue
    if ($Match) { $ApiToken = $Match.Matches[0].Groups[1].Value.Trim() }
}
if (-not $ApiToken) {
    $Bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($Bytes)
    $ApiToken = [Convert]::ToBase64String($Bytes).Replace('+','_').Replace('/','-').TrimEnd('=')
    if (Test-Path $EnvFile) { Add-Content -Path $EnvFile -Value "`nVAYRA_API_TOKEN=$ApiToken" -NoNewline:$false }
    else { Set-Content -Path $EnvFile -Value "VAYRA_API_TOKEN=$ApiToken" }
    Write-Host "Generated a new API token and wrote it to backend/.env" -ForegroundColor Yellow
}

function Test-PortListening([int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync("127.0.0.1", $Port)
        if (-not $task.Wait(500)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

if (-not (Test-Path $Python)) {
    throw "Backend environment not found. Run .\setup.ps1 first."
}

if (Test-PortListening 8000) {
    Write-Host "Backend already running on http://localhost:8000 - skipping start." -ForegroundColor DarkCyan
} else {
    Write-Host "Starting FastAPI backend on http://localhost:8000 ..." -ForegroundColor Cyan
    $BackendCommand = "Set-Location '$Backend'; & '$Python' -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000"
    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $BackendCommand
}

if (Test-PortListening 3000) {
    Write-Host "Frontend already running on $AppUrl - skipping start." -ForegroundColor DarkCyan
} else {
    Write-Host "Starting Next.js frontend on $AppUrl ..." -ForegroundColor Cyan
    $FrontendCommand = "Set-Location '$Frontend'; npm run dev"
    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $FrontendCommand
}

Write-Host "Waiting for the frontend to become ready ..." -ForegroundColor Cyan
$TimeoutSeconds = 90
$Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    Start-Sleep -Seconds 2
    if ((Get-Date) -gt $Deadline) {
        throw "Frontend did not answer on $AppUrl within $TimeoutSeconds seconds. Check the frontend window for errors."
    }
} while (-not (Test-PortListening 3000))

Write-Host "Opening $AppUrl in your default browser ..." -ForegroundColor Cyan
Start-Process $AppUrl

# Discover the LAN address so phones/tablets can reach the app.
$LanIp = $null
try {
    $LanIp = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp,Manual |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        Select-Object -First 1).IPAddress
} catch { }

Write-Host ""
Write-Host "SAP Diagnostic Agent is live:" -ForegroundColor Green
Write-Host "  Console:    $AppUrl" -ForegroundColor Green
Write-Host "  API token:  $ApiToken" -ForegroundColor Yellow
if ($LanIp) {
    Write-Host "  LAN:        http://$LanIp`:3000  (phone/tablet on the same Wi-Fi)" -ForegroundColor Green
    Write-Host "  API (LAN):  http://$LanIp`:8000/docs" -ForegroundColor Green
}
Write-Host "  API:        http://localhost:8000  (docs at /docs)" -ForegroundColor Green
Write-Host "Close the two service windows to stop the app."
