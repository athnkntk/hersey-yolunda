# Hersey Yolunda API — Windows VPS full installer (idempotent, re-runnable)
# Secrets are read from C:\hy\secrets\production.env (KEY=value lines) OR may be
# embedded as a $kv hashtable by the generated variant of this script.
# Installs: OpenSSH repair, Node 22, app source, npm install, Windows services
#           (HerseyAPI on 127.0.0.1:3000, HerseyCaddy with auto-TLS via sslip.io)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root     = 'C:\hy'
$repo     = "$root\app"
$nodeDir  = "$root\node"
$caddyDir = "$root\caddy"
$logDir   = "$root\logs"
$envFile  = "$root\secrets\production.env"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: run PowerShell as Administrator.' -ForegroundColor Red; exit 1
}

foreach ($d in @($root, $repo, $nodeDir, $caddyDir, $logDir, "$root\secrets")) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# --- 0. Repair OpenSSH (missing 'sshd' privsep account causes connection resets) ---
if (Test-Path 'C:\Windows\System32\OpenSSH\install-sshd.ps1') {
    Write-Host '==> Repairing OpenSSH...'
    & 'C:\Windows\System32\OpenSSH\install-sshd.ps1' | Out-Null
}
Restart-Service sshd -ErrorAction SilentlyContinue

# --- 1. Secrets: read env file unless a $kv hashtable is already embedded above ---
if (-not $kv) {
    $kv = @{}
    foreach ($line in (Get-Content $envFile)) {
        $clean = ($line -replace '[^\x20-\x7E]', '')
        if ($clean -match '^\s*([A-Za-z_]+)\s*=\s*(\S.*)$') {
            $key = $Matches[1].Trim()
            $v = $Matches[2].Trim()
            if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
            $kv[$key] = $v
        }
    }
}
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
    if (Test-Path $nodeDir) { Remove-Item $nodeDir -Recurse -Force }
    Move-Item "$root\node-v$ver-win-x64" $nodeDir -Force
    Write-Host "    Node $ver installed."
}
$env:Path = "$nodeDir;$env:Path"
# Propagate to child processes AND persist for cmd wrappers
[Environment]::SetEnvironmentVariable('Path', "$nodeDir;" + [Environment]::GetEnvironmentVariable('Path','Machine'), 'Machine')

# --- 3. App source (main branch zip) ---
Write-Host '==> Downloading app source...'
Invoke-WebRequest 'https://github.com/athnkntk/hersey-yolunda/archive/refs/heads/main.zip' -OutFile "$env:TEMP\repo.zip" -UseBasicParsing
if (Test-Path "$repo\hersey-yolunda-main") { Remove-Item "$repo\hersey-yolunda-main" -Recurse -Force }
Expand-Archive "$env:TEMP\repo.zip" $repo -Force
$backendDir = "$repo\hersey-yolunda-main\backend"

# --- 4. Install deps + typecheck (tsx runs the app; esbuild postinstall is
#        unnecessary — the win32 binary arrives via optional dependencies) ---
Write-Host '==> npm ci + typecheck...'
Push-Location $backendDir
& "$nodeDir\npm.cmd" ci --include=dev --ignore-scripts --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
& "$nodeDir\npm.cmd" run build   # typecheck smoke test; non-fatal
Pop-Location

# --- 5. Caddy binary ---
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

# --- 7. Scheduled tasks running at startup as SYSTEM (auto-restart on crash) ---
$merged = [ordered]@{}
foreach ($k in $kv.Keys) { $merged[$k] = $kv[$k] }
$merged['NODE_ENV'] = 'production'; $merged['HOST'] = '127.0.0.1'
$merged['PORT'] = '3000'; $merged['SCHEDULER_MODE'] = 'external'
$envLines = @($merged.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })

# cmd wrappers hold the env inline (scheduled tasks can't take per-task env)
$setLines = ($envLines | ForEach-Object { "set `"$_`"" }) -join "`r`n"
@"
@echo off
$setLines
cd /d $backendDir
"$nodeDir\node.exe" --import tsx src\main.ts >> "$logDir\api.log" 2>&1
"@ | Out-File "$root\run-api.cmd" -Encoding ascii
@"
@echo off
"$caddyDir\caddy.exe" run --config "$caddyDir\Caddyfile" --adapter caddyfile >> "$logDir\caddy.log" 2>&1
"@ | Out-File "$root\run-caddy.cmd" -Encoding ascii
icacls "$root\run-api.cmd" /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

foreach ($t in @('HerseyAPI','HerseyCaddy')) {
    Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
    sc.exe delete $t 2>$null | Out-Null   # clean any leftover from the sc.exe attempt
}
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit 0 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'HerseyAPI'   -Action (New-ScheduledTaskAction -Execute "$root\run-api.cmd")   -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Register-ScheduledTask -TaskName 'HerseyCaddy' -Action (New-ScheduledTaskAction -Execute "$root\run-caddy.cmd") -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

# --- 8. Start + verify ---
Write-Host '==> Starting services...'
Start-ScheduledTask -TaskName 'HerseyAPI'
Start-ScheduledTask -TaskName 'HerseyCaddy'
Start-Sleep 12

$local = $null
try { $local = Invoke-RestMethod 'http://127.0.0.1:3000/v1/health' -TimeoutSec 10 } catch {}
Write-Host ''
Write-Host '================================================' -ForegroundColor Green
Write-Host "  Local health: $($local | ConvertTo-Json -Compress)"
Write-Host "  Public URL : https://$ip.sslip.io"
Write-Host '  (TLS cert may take ~30s after first visit)'
Write-Host '================================================' -ForegroundColor Green
