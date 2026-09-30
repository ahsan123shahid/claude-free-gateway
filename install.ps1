<#
.SYNOPSIS
  Claude Desktop/CLI ko free models par lagane ka one-click installer.

.DESCRIPTION
  Ye script:
    1. litellm + pypdf install karti hai
    2. .env file banati hai (apni API key yahan daalein)
    3. Local proxy start karti hai (127.0.0.1:4000)
    4. Claude Code CLI settings ko proxy par point karti hai
    5. Claude Desktop ko "3p gateway" mode mein set karti hai
    6. Plugin marketplace (314 plugins) local bana deti hai

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1

.EXAMPLE
  # Sirf CLI + proxy, Desktop na chhuein:
  powershell -ExecutionPolicy Bypass -File install.ps1 -SkipDesktop
#>
param(
    [switch]$SkipDesktop,
    [switch]$SkipCli
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$backupDir = Join-Path $root "backup"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

function Say($msg, $color = "White") { Write-Host $msg -ForegroundColor $color }
function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }

# ---------------------------------------------------------------
Step "1/6" "Python packages check (litellm, pypdf)"
$py = $null
foreach ($c in @("python", "py -3", "python3")) {
    try { $v = Invoke-Expression "$c --version 2>&1"; if ("$v" -match "Python 3") { $py = $c; break } } catch {}
}
if (-not $py) {
    Say "Python 3 nahi mila. Pehle Python 3.10+ install karein: https://python.org" Red
    exit 1
}
Say "Python OK: $(& $py --version)" Green
& $py -m pip install --quiet --upgrade litellm pypdf
Say "litellm + pypdf installed" Green

# ---------------------------------------------------------------
Step "2/6" ".env (API keys)"
$envFile = Join-Path $root ".env"
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $root ".env.example") $envFile
    Say ".env ban gayi - ab API key daalni hai" Yellow
}
$envContent = Get-Content $envFile -Raw
if ($envContent -match "PASTE_YOUR_KEY_HERE" -or $envContent -notmatch "EXPERIENTIAL_API_KEY=.+") {
    $key = Read-Host "Experiential Labs API key daalein (xpl_...)"
    if ($key) {
        $envContent = $envContent -replace "(?m)^EXPERIENTIAL_API_KEY=.*$", "EXPERIENTIAL_API_KEY=$key"
        [System.IO.File]::WriteAllText($envFile, $envContent, (New-Object System.Text.UTF8Encoding($false)))
        Say "Key .env mein save ho gayi (ye file git mein nahi jati)" Green
    }
}
# is session mein bhi load
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $i = $line.IndexOf("=")
        Set-Item -Path "env:$($line.Substring(0,$i).Trim())" -Value $line.Substring($i+1).Trim()
    }
}

# ---------------------------------------------------------------
Step "3/6" "Local proxy start (127.0.0.1:4000)"
& (Join-Path $root "start-proxy.ps1")
$ok = $false
foreach ($i in 1..12) {
    try { Invoke-RestMethod -Uri "http://127.0.0.1:4000/health/liveliness" -TimeoutSec 5 | Out-Null; $ok = $true; break }
    catch { Start-Sleep -Seconds 3 }
}
if (-not $ok) {
    Say "Proxy health check fail - logs dekhein: logs\proxy.err.log" Red
} else {
    Say "Proxy UP" Green
}

# ---------------------------------------------------------------
if (-not $SkipCli) {
    Step "4/6" "Claude Code CLI -> proxy"
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    New-Item -ItemType Directory -Path (Split-Path $settingsPath) -Force | Out-Null
    if (Test-Path $settingsPath) {
        Copy-Item $settingsPath (Join-Path $backupDir "settings.json.bak") -Force
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } else {
        $settings = [pscustomobject]@{}
    }
    if (-not $settings.PSObject.Properties["env"]) {
        $settings | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $envMap = @{
        "ANTHROPIC_BASE_URL" = "http://127.0.0.1:4000"
        "ANTHROPIC_AUTH_TOKEN" = $(if ($env:GATEWAY_LOCAL_KEY) { $env:GATEWAY_LOCAL_KEY } else { "dummy-bypass-key" })
        "ANTHROPIC_API_KEY" = ""
        "ANTHROPIC_MODEL" = "claude-sonnet-4-5-20250929"
        "ANTHROPIC_DEFAULT_SONNET_MODEL" = "claude-sonnet-4-5-20250929"
        "ANTHROPIC_DEFAULT_OPUS_MODEL" = "claude-sonnet-4-5-20250929"
        "ANTHROPIC_DEFAULT_HAIKU_MODEL" = "claude-haiku-4-5-20251001"
        "CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT" = "1"
    }
    foreach ($k in $envMap.Keys) {
        $settings.env | Add-Member -NotePropertyName $k -NotePropertyValue $envMap[$k] -Force
    }
    $json = $settings | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Say "CLI settings update ho gaye (backup: backup\settings.json.bak)" Green
}

# ---------------------------------------------------------------
if (-not $SkipDesktop) {
    Step "5/6" "Claude Desktop -> 3p gateway mode"
    $ddir = Join-Path $env:LOCALAPPDATA "Claude-3p"
    New-Item -ItemType Directory -Path $ddir -Force | Out-Null

    # 5a. deploymentMode = 3p
    $dconf = Join-Path $ddir "claude_desktop_config.json"
    if (Test-Path $dconf) { Copy-Item $dconf (Join-Path $backupDir "claude_desktop_config.json.bak") -Force }
    $raw = if (Test-Path $dconf) { Get-Content $dconf -Raw } else { "{`n}`n" }
    if ($raw -match '"deploymentMode"\s*:\s*"[^"]*"') {
        $raw = $raw -replace '"deploymentMode"\s*:\s*"[^"]*"', '"deploymentMode": "3p"'
    } else {
        $brace = $raw.IndexOf("{")
        $raw = $raw.Substring(0, $brace + 1) + "`n  `"deploymentMode`": `"3p`"," + $raw.Substring($brace + 1)
    }
    [System.IO.File]::WriteAllText($dconf, $raw, (New-Object System.Text.UTF8Encoding($false)))
    Say "deploymentMode = 3p" Green

    # 5b. configLibrary gateway entry
    $cfgId = "c1a2b3c4-d5e6-4f70-8a9b-000000000001"
    $lib = Join-Path $ddir "configLibrary"
    New-Item -ItemType Directory -Path $lib -Force | Out-Null
    Copy-Item (Join-Path $root "desktop\gateway-config.json") (Join-Path $lib "$cfgId.json") -Force
    $metaPath = Join-Path $lib "_meta.json"
    if (Test-Path $metaPath) { Copy-Item $metaPath (Join-Path $backupDir "_meta.json.bak") -Force }
    $meta = [pscustomobject]@{
        appliedId = $cfgId
        entries   = @([pscustomobject]@{ id = $cfgId; name = "Gateway" })
    }
    [System.IO.File]::WriteAllText($metaPath, ($meta | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
    Say "Gateway config applied (127.0.0.1:4000)" Green

    # 5c. Plugin marketplace (agar app pehle chal chuka hai)
    $sessionsRoot = Join-Path $ddir "local-agent-mode-sessions"
    $orgDirs = @()
    if (Test-Path $sessionsRoot) {
        Get-ChildItem $sessionsRoot -Directory | ForEach-Object {
            Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object { $orgDirs += $_.FullName }
        }
    }
    $mpSrc = Join-Path $env:USERPROFILE ".claude\plugins\marketplaces\claude-plugins-official"
    if ($orgDirs.Count -gt 0 -and (Test-Path $mpSrc)) {
        foreach ($org in $orgDirs) {
            $dst = Join-Path $org "cowork_plugins"
            New-Item -ItemType Directory -Path "$dst\marketplaces" -Force | Out-Null
            if (-not (Test-Path "$dst\marketplaces\claude-plugins-official")) {
                robocopy $mpSrc "$dst\marketplaces\claude-plugins-official" /E /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
            }
            $km = [pscustomobject]@{
                "claude-plugins-official" = [pscustomobject]@{
                    source          = [pscustomobject]@{ source = "github"; repo = "anthropics/claude-plugins-official" }
                    installLocation = "$dst\marketplaces\claude-plugins-official"
                    lastUpdated     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")
                }
            }
            [System.IO.File]::WriteAllText((Join-Path $dst "known_marketplaces.json"), ($km | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
            if (-not (Test-Path (Join-Path $dst "installed_plugins.json"))) {
                [System.IO.File]::WriteAllText((Join-Path $dst "installed_plugins.json"), '{"version":2,"plugins":{}}', (New-Object System.Text.UTF8Encoding($false)))
            }
        }
        Say "Plugin marketplace ready ($($orgDirs.Count) account dir)" Green
    } else {
        Say "Marketplace: app pehli baar chal chuka tab tak skip - chalane ke baad dobara run karein" Yellow
    }
}

# ---------------------------------------------------------------
Step "6/6" "Summary"
Say "-------------------------------------------" Cyan
Say "Proxy:      http://127.0.0.1:4000  (har boot par: .\start-proxy.ps1)" Green
Say "API keys:   $envFile  (gitignored)" Green
if (-not $SkipCli)     { Say "CLI:        ho gaya - ab 'claude' command proxy use karegi" Green }
if (-not $SkipDesktop) { Say "Desktop:    3p gateway applied - APP RESTART KAREIN" Green }
Say "" ; Say "Model badalne ke liye app mein model picker use karein." White
Say "Logs: logs\proxy.out.log / logs\proxy.err.log" DarkGray
