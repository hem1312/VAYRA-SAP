# Requires administrator. Opens inbound TCP 3000 (Next.js UI) and 8000 (FastAPI)
# so phones/tablets on the same LAN can reach the app.
# Run with:  powershell -ExecutionPolicy Bypass -File .\firewall.ps1   (from an elevated prompt)

$ErrorActionPreference = "Stop"

$Rules = @(
    @{ Name = "SAP Diagnostic Agent - Web UI (TCP 3000)"; Port = 3000 },
    @{ Name = "SAP Diagnostic Agent - API (TCP 8000)";    Port = 8000 }
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Run this script from an elevated (Administrator) PowerShell prompt."
}

foreach ($rule in $Rules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Rule already exists: $($rule.Name)" -ForegroundColor DarkCyan
        continue
    }
    New-NetFirewallRule -DisplayName $rule.Name `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort $rule.Port `
        -Profile Private, Domain | Out-Null
    Write-Host "Added inbound rule: $($rule.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "LAN devices can now reach the UI on port 3000 and the API on port 8000." -ForegroundColor Green
