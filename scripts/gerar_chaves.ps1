# ================================================================
#  GERA as tres chaves da atividade (aleatorias de verdade)
#
#  Uso:  powershell -ExecutionPolicy Bypass -File .\gerar_chaves.ps1
#
#  Copie cada valor para o lugar indicado. Guarde num lugar seguro
#  (gerenciador de senhas). NAO cole em print, chat ou commit.
# ================================================================
function Aleatorio([int]$n) {
  $b = New-Object byte[] $n
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  return ($b | ForEach-Object { $_.ToString("x2") }) -join ""
}

$api  = Aleatorio 16    # 32 caracteres
$hmac = Aleatorio 32    # 64 caracteres
$aes  = Aleatorio 16    # 32 caracteres hex = 128 bits

Write-Host ""
Write-Host "API_KEY       = $api"  -ForegroundColor Yellow
Write-Host "   -> Worker: Secret API_KEY   |  config.h: API_KEY"
Write-Host ""
Write-Host "CHAVE_HMAC    = $hmac" -ForegroundColor Yellow
Write-Host "   -> Worker: Secret CHAVE_HMAC  |  config.h: CHAVE_HMAC  |  pagina: Chave HMAC"
Write-Host ""
Write-Host "CHAVE_AES_HEX = $aes"  -ForegroundColor Yellow
Write-Host "   -> config.h: CHAVE_AES_HEX  |  pagina: Chave AES   (o Worker NAO precisa dessa)"
Write-Host ""
