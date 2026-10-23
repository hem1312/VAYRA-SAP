$ErrorActionPreference = "SilentlyContinue"

$Ports = 3000, 8000
$Stopped = $false

foreach ($Port in $Ports) {
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen 2>$null
    foreach ($conn in $conns) {
        $procId = $conn.OwningProcess
        $name = (Get-Process -Id $procId).ProcessName
        Stop-Process -Id $procId -Force
        Write-Host "Stopped $name (PID $procId) on port $Port" -ForegroundColor Yellow
        $Stopped = $true
    }
}

if (-not $Stopped) {
    Write-Host "Nothing running on ports 3000 / 8000." -ForegroundColor DarkCyan
} else {
    Write-Host "All services stopped." -ForegroundColor Green
}
