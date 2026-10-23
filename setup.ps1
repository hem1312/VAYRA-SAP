$ErrorActionPreference = "Stop"

Write-Host "=== SAP Diagnostic Agent setup ===" -ForegroundColor Cyan

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Backend = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python was not found. Install Python 3.11+ and ensure it is on PATH."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js was not found. Install Node.js 20+ and ensure it is on PATH."
}

if (-not (Test-Path (Join-Path $Backend ".venv"))) {
    Write-Host "Creating Python virtual environment..." -ForegroundColor Yellow
    python -m venv (Join-Path $Backend ".venv")
}

$Pip = Join-Path $Backend ".venv\Scripts\pip.exe"
$Python = Join-Path $Backend ".venv\Scripts\python.exe"
Write-Host "Installing backend dependencies..." -ForegroundColor Yellow
& $Pip install -r (Join-Path $Backend "requirements.txt")

if (-not (Test-Path (Join-Path $Backend ".env"))) {
    Copy-Item (Join-Path $Backend ".env.example") (Join-Path $Backend ".env")
    Write-Host "Created backend/.env from backend/.env.example" -ForegroundColor Green
}

Write-Host "Installing frontend dependencies..." -ForegroundColor Yellow
Push-Location $Frontend
npm install
Pop-Location

Write-Host "Running validation..." -ForegroundColor Yellow
& $Python -m compileall -q (Join-Path $Backend "app")
Push-Location $Frontend
npm run typecheck
npm run build
Pop-Location

Write-Host "Setup complete." -ForegroundColor Green
Write-Host "Run .\run.ps1 to start the backend and frontend." -ForegroundColor Cyan
