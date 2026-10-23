$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $Root "backend\.venv\Scripts\python.exe"
$App = Join-Path $Root "desktop\app.py"

if (-not (Test-Path $Python)) {
    throw "Backend environment not found. Run .\setup.ps1 first."
}

Start-Process -FilePath $Python -ArgumentList "`"$App`"" -WorkingDirectory $Root -WindowStyle Hidden
