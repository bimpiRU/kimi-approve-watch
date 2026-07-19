# make-cert.ps1 — самоподписанный сертификат для HTTPS Jarvis Hub (data\cert.pfx)
$ErrorActionPreference = 'Stop'
$dataDir = Join-Path $PSScriptRoot 'data'
New-Item -ItemType Directory -Force $dataDir | Out-Null
$pfxPath = Join-Path $dataDir 'cert.pfx'
$pass = ConvertTo-SecureString -String 'jarvis-hub' -Force -AsPlainText
$cert = New-SelfSignedCertificate -DnsName 'localhost', 'jarvis-hub' -CertStoreLocation 'Cert:\CurrentUser\My' `
    -NotAfter (Get-Date).AddYears(5) -KeyExportPolicy Exportable -KeyLength 2048 `
    -FriendlyName 'Jarvis Hub HTTPS'
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pass | Out-Null
Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
Write-Host "сертификат создан: $pfxPath (пароль: jarvis-hub)" -ForegroundColor Green
Write-Host 'браузер будет ругаться на самоподписанный сертификат — это норма: Advanced → Proceed.'
Write-Host 'перезапусти сервер (кнопка в пульте) — HTTPS поднимется на порту 8443.'
