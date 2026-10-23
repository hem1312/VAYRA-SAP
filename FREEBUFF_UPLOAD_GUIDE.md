# Freebuff upload and Windows run guide

## Upload

Upload the entire `sap-diagnostic-agent` folder, or upload `sap-diagnostic-agent.zip` if Freebuff accepts ZIP archives. Keep the `frontend` and `backend` folders at the project root.

## PowerShell commands

Open PowerShell and move into the extracted project folder:

```powershell
cd "C:\path\to\sap-diagnostic-agent"
```

If PowerShell blocks local scripts, allow scripts for the current terminal only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Run the one-time setup:

```powershell
.\setup.ps1
```

Start the application:

```powershell
.\run.ps1
```

Then open:

```text
http://localhost:3000
```

The FastAPI backend runs at:

```text
http://localhost:8000
```

Health check:

```powershell
Invoke-RestMethod http://localhost:8000/health
```

## Manual alternative

Backend terminal:

```powershell
cd "C:\path\to\sap-diagnostic-agent\backend"
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload --port 8000
```

Frontend terminal:

```powershell
cd "C:\path\to\sap-diagnostic-agent\frontend"
npm run dev
```

## Requirements

- Python 3.11 or newer
- Node.js 20 or newer
- npm
- PowerShell 5.1 or PowerShell 7+

## Environment variables

For the local demo, the backend uses the deterministic provider and does not require an API key. To configure a real provider, copy `backend/.env.example` to `backend/.env` and set values there. Never commit real credentials or paste them into frontend code.
