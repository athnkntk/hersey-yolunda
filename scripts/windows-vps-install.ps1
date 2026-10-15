# Hersey Yolunda API — Windows VPS full installer (idempotent, re-runnable)
# Prereq: C:\hy\secrets\production.env with DATABASE_URL, DATA_ENCRYPTION_KEY,
#         LOOKUP_KEY, TICK_SECRET (KEY=value lines).
# Installs: OpenSSH repair, Node 22, app source, npm build, NSSM services
#           (HerseyAPI on 127.0.0.1:3000, HerseyCaddy with auto-TLS via sslip.io)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root     = 'C:\hy'
$repo     = "$root\app"
$nodeDir  = "$root\node"
$nssmDir  = "$root\nssm"
$caddyDir = "$root\caddy"
$logDir   = "$root\logs"
$envFile  = "$root\secrets\production.env"
$nssm     = "$nssmDir\nssm.exe"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: run PowerShell as Administrator.' -ForegroundColor Red; exit 1
}

foreach ($d in @($root, $repo, $nodeDir, $nssmDir, $caddyDir, $logDir, "$root\secrets")) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# --- 0. Repair OpenSSH (missing 'sshd' privsep account causes connection resets) ---
if (Test-Path 'C:\Windows\System32\OpenSSH\install-sshd.ps1') {
    Write-Host '==> Repairing OpenSSH...'
    & 'C:\Windows\System32\OpenSSH\install-sshd.ps1' | Out-Null
}
Restart-Service sshd -ErrorAction SilentlyContinue

# --- 1. Secrets check ---
if (-not (Test-Path $envFile)) {
@"
DATABASE_URL=
DATA_ENCRYPTION_KEY=
LOOKUP_KEY=
TICK_SECRET=
"@ | Out-File $envFile -Encoding ascii
}
$kv = @{}
Get-Content $envFile | ForEach-Object { if ($_ -match '^\s*([A-Za-z_]+)\s*=\s*(\S.*)$') { $kv[$Matches[1].Trim()] = $Matches[2].Trim() } }
$missing = @('DATABASE_URL','DATA_ENCRYPTION_KEY','LOOKUP_KEY','TICK_SECRET') | Where-Object { -not $kv[$_] }
if ($missing) {
    Write-Host "==> Fill these in $envFile then re-run: $($missing -join ', ')" -ForegroundColor Yellow
    notepad $envFile
    exit 0
}

# --- 2. Node.js 22 LTS (portable zip) ---
if (-not (Test-Path "$nodeDir\node.exe")) {
    Write-Host '==> Downloading Node.js...'
    $idx = (Invoke-WebRequest 'https://nodejs.org/dist/latest-v22.x/' -UseBasicParsing).Content
    $ver = [regex]::Match($idx, 'node-v([\d.]+)-win-x64\.zip').Groups[1].Value
    Invoke-WebRequest "https://nodejs.org/dist/v$ver/node-v$ver-win-x64.zip" -OutFile "$env:TEMP\node.zip" -UseBasicParsing
    Expand-Archive "$env:TEMP\node.zip" $root -Force
    Move-Item "$root\node-v$ver-win-x64" "$nodeDir.tmp" -Force
    Remove-Item $nodeDir -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item "$nodeDir.tmp" $nodeDir -Force
    Write-Host "    Node $ver installed."
}
$env:Path = "$nodeDir;$env:Path"

# --- 3. App source (main branch zip) ---
Write-Host '==> Downloading app source...'
Invoke-WebRequest 'https://github.com/athnkntk/hersey-yolunda/archive/refs/heads/main.zip' -OutFile "$env:TEMP\repo.zip" -UseBasicParsing
if (Test-Path "$repo\hersey-yolunda-main") { Remove-Item "$repo\hersey-yolunda-main" -Recurse -Force }
Expand-Archive "$env:TEMP\repo.zip" $repo -Force

# --- 4. Build backend ---
Write-Host '==> npm ci + build...'
Push-Location "$repo\hersey-yolunda-main\backend"
& "$nodeDir\npm.cmd" ci --no-audit --no-fund
& "$nodeDir\npm.cmd" run build
Pop-Location

# --- 5. NSSM + Caddy binaries ---
if (-not (Test-Path $nssm)) {
    Write-Host '==> Downloading NSSM...'
    Invoke-WebRequest 'https://nssm.cc/release/nssm-2.24.zip' -OutFile "$env:TEMP\nssm.zip" -UseBasicParsing
    Expand-Archive "$env:TEMP\nssm.zip" "$env:TEMP\nssm" -Force
    Copy-Item "$env:TEMP\nssm\nssm-2.24\win64\nssm.exe" $nssm -Force
}
if (-not (Test-Path "$caddyDir\caddy.exe")) {
    Write-Host '==> Downloading Caddy...'
    Invoke-WebRequest 'https://caddyserver.com/api/download?os=windows&arch=amd64' -OutFile "$caddyDir\caddy.exe" -UseBasicParsing
}

# --- 6. Caddyfile (auto-TLS via sslip.io) ---
$ip = (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 10)
@"
$ip.sslip.io {
    reverse_proxy 127.0.0.1:3000
}
"@ | Out-File "$caddyDir\Caddyfile" -Encoding ascii

# --- 7. Services ---
$merged = [ordered]@{}
Get-Content $envFile | ForEach-Object { if ($_ -match '^\s*([A-Za-z_]+)\s*=\s*(.*)$') { $merged[$Matches[1].Trim()] = $Matches[2].Trim() } }
# Bind localhost only — Caddy is the public edge on 443
$merged['NODE_ENV'] = 'production'; $merged['HOST'] = '127.0.0.1'
$merged['PORT'] = '3000'; $merged['SCHEDULER_MODE'] = 'external'
$envExtra = $merged.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
$backendDir = "$repo\hersey-yolunda-main\backend"

if (-not (Get-Service HerseyAPI -ErrorAction SilentlyContinue)) {
    & $nssm install HerseyAPI "$nodeDir\node.exe" 'dist\main.js'
}
& $nssm set HerseyAPI AppDirectory $backendDir | Out-Null
& $nssm set HerseyAPI AppEnvironmentExtra @envExtra | Out-Null
& $nssm set HerseyAPI AppStdout "$logDir\api.log" | Out-Null
& $nssm set HerseyAPI AppStderr "$logDir\api.log" | Out-Null
& $nssm set HerseyAPI AppRotateFiles 1 | Out-Null
& $nssm set HerseyAPI Start SERVICE_AUTO_START | Out-Null

if (-not (Get-Service HerseyCaddy -ErrorAction SilentlyContinue)) {
    & $nssm install HerseyCaddy "$caddyDir\caddy.exe" "run --config `"$caddyDir\Caddyfile`" --adapter caddyfile"
}
& $nssm set HerseyCaddy AppStdout "$logDir\caddy.log" | Out-Null
& $nssm set HerseyCaddy AppStderr "$logDir\caddy.log" | Out-Null
& $nssm set HerseyCaddy Start SERVICE_AUTO_START | Out-Null

# --- 8. Start + verify ---
Write-Host '==> Starting services...'
& $nssm restart HerseyAPI  | Out-Null
& $nssm restart HerseyCaddy | Out-Null
Start-Sleep 8

$local = $null
try { $local = Invoke-RestMethod 'http://127.0.0.1:3000/v1/health' -TimeoutSec 10 } catch {}
Write-Host ''
Write-Host '================================================' -ForegroundColor Green
Write-Host "  Local health: $($local | ConvertTo-Json -Compress)"
Write-Host "  Public URL : https://$ip.sslip.io"
Write-Host '  (TLS cert may take ~30s after first visit)'
Write-Host '================================================' -ForegroundColor Green
