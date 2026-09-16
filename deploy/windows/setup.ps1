#requires -RunAsAdministrator
# Hersey Yolunda - Windows Server kurulum script'i.
# Yonetici PowerShell'de: powershell -ExecutionPolicy Bypass -File setup.ps1
# Kurar: Chocolatey, Git, Node.js LTS, PostgreSQL 17, Caddy.
# Olusturur: hersey DB + kullanici, API ve Caddy baslangic gorevleri, 80/443 firewall kurallari.
$ErrorActionPreference = 'Stop'

$root   = 'C:\hersey-yolunda'
$domain = '92.205.190.116.sslip.io'

function RandHex([int]$n) { -join ((1..$n) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) }) }
$pgSuperPass = "Hy$(RandHex 12)"
$pgAppPass   = "Hy$(RandHex 16)"
$encKey      = RandHex 64
$lookupKey   = RandHex 64

Write-Host '==> Chocolatey kuruluyor...' -ForegroundColor Cyan
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}
$env:Path = "$env:Path;C:\ProgramData\chocolatey\bin"

Write-Host '==> Paketler kuruluyor (git, nodejs-lts, postgresql17, caddy)...' -ForegroundColor Cyan
choco install -y git nodejs-lts caddy --no-progress
choco install -y postgresql17 --params "'/Password:$pgSuperPass'" --no-progress
refreshenv | Out-Null

Write-Host '==> Repo cekiliyor...' -ForegroundColor Cyan
if (-not (Test-Path "$root\.git")) {
    & 'C:\Program Files\Git\bin\git.exe' clone https://github.com/athnkntk/hersey-yolunda.git $root
} else {
    & 'C:\Program Files\Git\bin\git.exe' -C $root pull --ff-only
}

Write-Host '==> PostgreSQL kullanici ve veritabani olusturuluyor...' -ForegroundColor Cyan
$pgBin = Get-ChildItem 'C:\Program Files\PostgreSQL' -Directory |
    Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object { Join-Path $_.FullName 'bin' }
$env:PGPASSWORD = $pgSuperPass
& "$pgBin\psql.exe" -U postgres -h 127.0.0.1 -c "CREATE USER hersey PASSWORD '$pgAppPass';" -c "CREATE DATABASE hersey OWNER hersey;"
Remove-Item Env:PGPASSWORD

Write-Host '==> Backend bagimliliklari kuruluyor...' -ForegroundColor Cyan
Set-Location "$root\backend"
& 'C:\Program Files\nodejs\npm.cmd' ci --include=dev

Write-Host '==> Baslangic scripti yaziliyor (gizli anahtarlar sadece bu sunucuda)...' -ForegroundColor Cyan
@"
`$env:NODE_ENV='production'
`$env:HOST='0.0.0.0'
`$env:PORT='3000'
`$env:SCHEDULER_MODE='internal'
`$env:DATABASE_URL='postgres://hersey:$pgAppPass@127.0.0.1:5432/hersey'
`$env:DATA_ENCRYPTION_KEY='$encKey'
`$env:LOOKUP_KEY='$lookupKey'
Set-Location '$root\backend'
& 'C:\Program Files\nodejs\node.exe' --import tsx src/main.ts
"@ | Out-File -Encoding utf8 "$root\deploy\windows\start-api.ps1"

Write-Host '==> DOMAIN ortam degiskeni ve baslangic gorevleri ayarlaniyor...' -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable('DOMAIN', $domain, 'Machine')

$apiAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File $root\deploy\windows\start-api.ps1"
$webAction = New-ScheduledTaskAction -Execute 'C:\ProgramData\chocolatey\bin\caddy.exe' `
    -Argument "run --config $root\deploy\windows\Caddyfile --adapter caddyfile"
$startup   = New-ScheduledTaskTrigger -AtStartup
foreach ($t in @(@('HerseyYolundaAPI', $apiAction), @('HerseyYolundaWeb', $webAction))) {
    Unregister-ScheduledTask -TaskName $t[0] -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $t[0] -Action $t[1] -Trigger $startup -RunLevel Highest -User 'SYSTEM' | Out-Null
    Start-ScheduledTask -TaskName $t[0]
}

Write-Host '==> Firewall: 80 ve 443 aciliyor...' -ForegroundColor Cyan
foreach ($p in @(80, 443)) {
    if (-not (Get-NetFirewallRule -DisplayName "HerseyYolunda-$p" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "HerseyYolunda-$p" -Direction Inbound -LocalPort $p -Protocol TCP -Action Allow | Out-Null
    }
}

Write-Host '==> Dogrulama (30 sn bekleniyor)...' -ForegroundColor Cyan
Start-Sleep -Seconds 30
try {
    $health = Invoke-RestMethod -Uri "https://$domain/v1/health" -TimeoutSec 15
    Write-Host "CANLI: $($health | ConvertTo-Json -Compress)" -ForegroundColor Green
} catch {
    Write-Host "HTTPS henuz hazir degil (sertifika aliniyor olabilir). 1-2 dk sonra tekrar dene:" -ForegroundColor Yellow
    Write-Host "  Invoke-RestMethod https://$domain/v1/health" -ForegroundColor Yellow
    Write-Host "Caddy logu: Get-ScheduledTask HerseyYolundaWeb durumunda; sertifika icin 80/443 disaridan erisilebilir olmali." -ForegroundColor Yellow
}
Write-Host "Tamam. API gorev logu icin: Get-ScheduledTaskInfo HerseyYolundaAPI" -ForegroundColor Cyan
