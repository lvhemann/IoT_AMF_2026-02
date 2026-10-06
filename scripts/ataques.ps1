# ================================================================
#  ATAQUES CONTRA O SEU PROPRIO WORKER (antes e depois das camadas)
#
#  Uso (na pasta scripts):
#    powershell -ExecutionPolicy Bypass -File .\ataques.ps1 -Url https://sua-api.SEU-USUARIO.workers.dev -Teste Falso
#    powershell -ExecutionPolicy Bypass -File .\ataques.ps1 -Url ... -ApiKey SUA_API_KEY -ChaveHmac SUA_CHAVE_HMAC -Teste Todos
#
#  Testes:
#    Falso       manda leitura falsa SEM nada (o que qualquer um faria)
#    SemChave    leitura sem API key
#    ComChave    leitura com API key, mas sem assinatura
#    Valido      leitura com API key + assinatura certa (o ESP32 faz isso)
#    Adulterado  assina valor=25.0 e manda valor=45.0 com a mesma assinatura
#    Replay      manda a MESMA requisicao valida duas vezes
#    Atrasado    requisicao assinada, mas com ts de 5 minutos atras
#    Tentativas  lista o que o Worker recusou (precisa da API key)
#    Todos       roda tudo, na ordem
# ================================================================
param(
  [Parameter(Mandatory = $true)][string]$Url,
  [string]$ApiKey = "",
  [string]$ChaveHmac = "",
  [ValidateSet("Falso", "SemChave", "ComChave", "Valido", "Adulterado", "Replay", "Atrasado", "Tentativas", "Todos")]
  [string]$Teste = "Todos"
)

$Url = $Url.TrimEnd("/")
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Agora { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Corpo([string]$valor, [long]$ts) {
  # montado como TEXTO, igual ao ESP32: a assinatura vale para estes bytes exatos
  return '{"nome":"atacante","sensor":"temp","valor":' + $valor + ',"ts":' + $ts + '}'
}

function Assinar([string]$msg) {
  if ($ChaveHmac -eq "") { throw "Passe -ChaveHmac para os testes com assinatura." }
  $hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($ChaveHmac))
  $mac = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($msg))
  return ($mac | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Enviar([string]$corpo, [hashtable]$cabecalhos) {
  try {
    $r = Invoke-WebRequest -Uri "$Url/insert" -Method POST -Body $corpo `
         -ContentType "application/json" -Headers $cabecalhos -UseBasicParsing
    return @{ Status = [int]$r.StatusCode; Texto = [string]$r.Content }
  } catch {
    $resp = $_.Exception.Response
    if ($null -eq $resp) { return @{ Status = -1; Texto = $_.Exception.Message } }
    return @{ Status = [int]$resp.StatusCode; Texto = [string]$_.ErrorDetails.Message }
  }
}

function Mostrar([string]$nome, [string]$esperado, $res) {
  $cor = if ($res.Status -ge 200 -and $res.Status -lt 300) { "Yellow" } else { "Green" }
  Write-Host ""
  Write-Host "== $nome ==" -ForegroundColor Cyan
  Write-Host "   esperado (camada 3 ligada): $esperado"
  Write-Host ("   obtido: HTTP {0}  {1}" -f $res.Status, $res.Texto) -ForegroundColor $cor
}

function Teste-Falso {
  $c = Corpo "999" (Agora)
  Mostrar "Falso (sem nada)" "401 - antes das camadas, isto GRAVAVA 999 no seu banco" (Enviar $c @{})
}
function Teste-SemChave {
  $c = Corpo "25.0" (Agora)
  Mostrar "Sem API key" "401" (Enviar $c @{})
}
function Teste-ComChave {
  $c = Corpo "25.0" (Agora)
  Mostrar "Com API key, sem assinatura" "401 (na camada 2 ainda passa: 200)" (Enviar $c @{ "X-API-Key" = $ApiKey })
}
function Teste-Valido {
  $c = Corpo "25.0" (Agora)
  $h = @{ "X-API-Key" = $ApiKey; "X-Assinatura" = (Assinar $c) }
  Mostrar "Valido (API key + assinatura)" "200" (Enviar $c $h)
}
function Teste-Adulterado {
  $ts = Agora
  $assinatura = Assinar (Corpo "25.0" $ts)       # assinou 25.0 ...
  $c = Corpo "45.0" $ts                          # ... mas manda 45.0
  $h = @{ "X-API-Key" = $ApiKey; "X-Assinatura" = $assinatura }
  Mostrar "Adulterado (assina 25.0, manda 45.0)" "401 assinatura invalida" (Enviar $c $h)
}
function Teste-Replay {
  $c = Corpo "25.0" (Agora)
  $h = @{ "X-API-Key" = $ApiKey; "X-Assinatura" = (Assinar $c) }
  Mostrar "Replay - 1a vez" "200" (Enviar $c $h)
  Mostrar "Replay - 2a vez (mesma requisicao)" "401 replay" (Enviar $c $h)
}
function Teste-Atrasado {
  $c = Corpo "25.0" ((Agora) - 300)
  $h = @{ "X-API-Key" = $ApiKey; "X-Assinatura" = (Assinar $c) }
  Mostrar "Atrasado (ts de 5 min atras)" "401 expirada" (Enviar $c $h)
}
function Teste-Tentativas {
  Write-Host ""
  Write-Host "== Tentativas recusadas (GET /tentativas) ==" -ForegroundColor Cyan
  try {
    Invoke-RestMethod -Uri "$Url/tentativas" -Headers @{ "X-API-Key" = $ApiKey } |
      Select-Object -First 10 motivo, ip, @{ n = "quando"; e = { [DateTimeOffset]::FromUnixTimeMilliseconds($_.timestamp).ToLocalTime().ToString("HH:mm:ss") } } |
      Format-Table -AutoSize
  } catch { Write-Host "   falhou: $($_.Exception.Message)" -ForegroundColor Red }
}

switch ($Teste) {
  "Todos" {
    Teste-Falso; Teste-SemChave; Teste-ComChave
    if ($ChaveHmac -ne "") { Teste-Valido; Teste-Adulterado; Teste-Replay; Teste-Atrasado }
    else { Write-Host "`n(sem -ChaveHmac: pulei os testes de assinatura)" }
    if ($ApiKey -ne "") { Teste-Tentativas }
  }
  default { & "Teste-$Teste" }
}
