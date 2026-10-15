# Hersey Yolunda API — Windows VPS bootstrap
# Run ONCE in an elevated PowerShell (Run as Administrator).
# Installs OpenSSH Server + Devin's deploy key, then prints the public IP.
# Everything else (Node, service, Caddy TLS) is done remotely over SSH.

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: PowerShell must be run as Administrator.' -ForegroundColor Red
    exit 1
}

Write-Host '==> Installing OpenSSH Server...'
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null

Set-Service sshd -StartupType Automatic
Start-Service sshd

# Firewall: SSH (22) now; HTTP/HTTPS (80/443) for Caddy later
foreach ($rule in @(
    @{ Name = 'OpenSSH-Server'; Port = 22 },
    @{ Name = 'HY-HTTP';        Port = 80 },
    @{ Name = 'HY-HTTPS';       Port = 443 }
)) {
    if (-not (Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $rule.Name -DisplayName $rule.Name `
            -Direction Inbound -Protocol TCP -LocalPort $rule.Port -Action Allow | Out-Null
    }
}

Write-Host '==> Installing deploy key...'
$keyFile = 'C:\ProgramData\ssh\administrators_authorized_keys'
New-Item -ItemType Directory -Force -Path C:\ProgramData\ssh | Out-Null
'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIkU8vpYGNtF1oPdHYXzO5dlA57TLgF3l3akNJ6NomEr devin-hy-vps-deploy' |
    Out-File -FilePath $keyFile -Encoding ascii -Force

# Required ACL: only Administrators + SYSTEM may read this file
icacls $keyFile /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

Restart-Service sshd

$ip = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10)
Write-Host ''
Write-Host '================================================' -ForegroundColor Green
Write-Host "  DONE. Public IP: $ip" -ForegroundColor Green
Write-Host '  Send this IP to Devin. It will finish the setup.' -ForegroundColor Green
Write-Host '================================================' -ForegroundColor Green
