# LiteLLM proxy start karta hai -> http://127.0.0.1:4000
# Robust: litellm detached process ki tarah chalta hai (ye window band hone par bhi).
# Usage: powershell -ExecutionPolicy Bypass -File start-proxy.ps1

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $root "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

# --- .env load karein (keys config.yaml mein os.environ/ se aati hain) ---
$envFile = Join-Path $root ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $i = $line.IndexOf("=")
            $k = $line.Substring(0, $i).Trim()
            $v = $line.Substring($i + 1).Trim()
            if ($k) { Set-Item -Path "env:$k" -Value $v }
        }
    }
} else {
    Write-Host ".env nahi mila - .env.example copy karke apni API key daalein" -ForegroundColor Yellow
}

$existing = Get-NetTCPConnection -LocalPort 4000 -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Proxy pehle se port 4000 par chal raha hai (PID $($existing.OwningProcess))." -ForegroundColor Yellow
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:4000/health/liveliness" -TimeoutSec 5
        Write-Host "Health OK: $r" -ForegroundColor Green
    } catch { Write-Host "Health check fail - port 4000 koi aur process use kar raha hai." -ForegroundColor Red }
    exit 0
}

$litellm = (Get-Command litellm -ErrorAction SilentlyContinue).Source
if (-not $litellm) {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts\litellm.exe",
        "$env:APPDATA\Python\Python312\Scripts\litellm.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $litellm = $c; break } }
}
if (-not $litellm) {
    Write-Host "litellm nahi mila. Pehle:  pip install litellm pypdf" -ForegroundColor Red
    exit 1
}

$out = Join-Path $logDir "proxy.out.log"
$err = Join-Path $logDir "proxy.err.log"

Write-Host "LiteLLM proxy start ho raha hai..." -ForegroundColor Green
Start-Process -FilePath $litellm `
    -ArgumentList "--config", (Join-Path $root "config.yaml"), "--port", "4000", "--host", "127.0.0.1" `
    -WorkingDirectory $root `
    -RedirectStandardOutput $out `
    -RedirectStandardError $err `
    -WindowStyle Hidden

# Health check: uvicorn boot hone mein 10-20s leta hai -> retry loop
$alive = $false
foreach ($try in 1..30) {
    Start-Sleep -Seconds 2
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:4000/health/liveliness" -TimeoutSec 5
        $alive = $true
        break
    } catch { }
}
if ($alive) {
    Write-Host "Proxy chal raha hai: $r  (boot $($try * 2)s)" -ForegroundColor Green
} else {
    Write-Host "Proxy start hua lekin health check fail - logs dekhein:" -ForegroundColor Red
    Write-Host "$out / $err"
}
