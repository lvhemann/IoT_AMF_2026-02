# ================================================================
#  GERA esp32\estacao_cofre\certificados.h
#
#  Uso (na pasta scripts):
#    powershell -ExecutionPolicy Bypass -File .\gerar_certificados.ps1 -Worker sua-api.SEU-USUARIO.workers.dev
#
#  O que ele faz:
#   1. Conecta no seu Worker por HTTPS, pega a cadeia de certificados
#      e guarda as CAs (intermediarias + raiz) - o leaf do site fica de fora.
#   2. Baixa a CA do broker test.mosquitto.org (mosquitto.org.crt).
#   3. Escreve tudo no formato que o ESP32 entende.
#  Rode de novo se um dia o HTTPS do ESP32 comecar a falhar com
#  "X509 - Certificate verification failed": a Cloudflare trocou a CA.
# ================================================================
param([Parameter(Mandatory = $true)][string]$Worker)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Worker = $Worker -replace '^https?://', '' -replace '/.*$', ''

function Para-Pem([byte[]]$der) {
  $b64 = [Convert]::ToBase64String($der)
  $linhas = for ($i = 0; $i -lt $b64.Length; $i += 64) { $b64.Substring($i, [Math]::Min(64, $b64.Length - $i)) }
  return "-----BEGIN CERTIFICATE-----`n" + ($linhas -join "`n") + "`n-----END CERTIFICATE-----"
}

# ---- 1) cadeia do Worker ----
Write-Host "Conectando em $Worker ..."
$tcp = New-Object Net.Sockets.TcpClient($Worker, 443)
$ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false)
$ssl.AuthenticateAsClient($Worker)
$folha = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $ssl.RemoteCertificate
$ssl.Dispose(); $tcp.Dispose()

$cadeia = New-Object Security.Cryptography.X509Certificates.X509Chain
[void]$cadeia.Build($folha)
$pemWorker = @()
Write-Host "Certificado do site: $($folha.Subject)"
for ($i = 1; $i -lt $cadeia.ChainElements.Count; $i++) {      # i=0 e' o leaf: pula
  $c = $cadeia.ChainElements[$i].Certificate
  Write-Host "  + CA: $($c.Subject)  (valida ate $($c.NotAfter.ToString('dd/MM/yyyy')))"
  $pemWorker += (Para-Pem $c.RawData)
}
if ($pemWorker.Count -eq 0) { throw "Nao consegui montar a cadeia do Worker." }

# ---- 2) CA do Mosquitto ----
Write-Host "Baixando a CA do test.mosquitto.org ..."
$mosq = (Invoke-WebRequest -Uri "https://test.mosquitto.org/ssl/mosquitto.org.crt" -UseBasicParsing).Content
if ($mosq -is [byte[]]) { $mosq = [Text.Encoding]::ASCII.GetString($mosq) }
$mosq = ($mosq -replace "`r", "").Trim()
if ($mosq -notmatch "BEGIN CERTIFICATE") { throw "O arquivo baixado nao parece um certificado PEM." }
Write-Host "  + CA: mosquitto.org"

# ---- 3) escreve o .h ----
$destino = Join-Path $PSScriptRoot "..\esp32\estacao_cofre\certificados.h"
$h = @"
// Gerado por gerar_certificados.ps1 em $(Get-Date -Format 'dd/MM/yyyy HH:mm') para $Worker
// Certificados PUBLICOS das autoridades (CAs): pode versionar, nao e' segredo.

const char* CA_WORKER = R"CERT(
$($pemWorker -join "`n")
)CERT";

const char* CA_MOSQUITTO = R"CERT(
$mosq
)CERT";
"@
[IO.File]::WriteAllText([IO.Path]::GetFullPath($destino), ($h -replace "`r", ""))
Write-Host ""
Write-Host "Pronto: $([IO.Path]::GetFullPath($destino))" -ForegroundColor Green
