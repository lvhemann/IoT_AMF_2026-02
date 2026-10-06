# Entrega — Estação Cofre (Segurança, Autenticação e Criptografia)

**Aluno:**
**Turma:** AMF 2026-02
**Prefixo MQTT (`NOME`):** `sis1a/________/`
**Link do Worker:** `https://sua-api.SEU-USUARIO.workers.dev`

> ⚠️ **Antes de enviar:** confiram que **nenhum print mostra uma chave** (API key, HMAC ou AES)
> e que o `config.h` **não** está no repositório. Se aparecer, borrem no print **e troquem a
> chave** (`gerar_chaves.ps1`).

---

## Evidências (prints)

### Passo 1 — Antes de trancar
- `ataques.ps1 -Teste Falso` contra o Worker antigo → **200**, e o 999 aparecendo em `/list?sensor=temp`:

- `cofre.html` em `ws :8080`, mostrando estações da turma **LEGÍVEIS**:

### Passo 3 — Camada 2 (API key)
- `ataques.ps1 -Teste Todos` com `-ApiKey`: `Falso`/`SemChave` → 401, `ComChave` → 200:

### Passo 4 — Camada 1 (TLS)
- Serial Monitor: NTP ok, MQTT na **8885** ok, HTTPS com **200**:

- Serial Monitor com a **CA errada**: falha de TLS (`X509 - Certificate verification failed`):

### Passos 5 e 6 — Camada 3 (HMAC + anti-replay)
- **Antes** (`EXIGIR_ASSINATURA = nao`): `Adulterado`, `Replay` e `Atrasado` passando com 200:

- **Depois** (`EXIGIR_ASSINATURA = sim`): `Adulterado` 401, `Replay` 200 → 401, `Atrasado` 401:

- Lista de **tentativas recusadas** (fim do script):

### Passo 7 — Camada 4 (cofre AES-GCM)
- Seu tópico `/cofre` aparecendo como **CIFRADO** na seção 1:

- Valores **decifrados** com a chave certa (✔ aberto):

- Chave com 1 caractere trocado, ou chave de colega (✘ não abriu):

### Passo 8 — Comandos assinados
- `OK: led:ON` (assinado):
- `RECUSADO: sem assinatura`:
- `RECUSADO: replay (comando repetido)`:
- `RECUSADO: assinatura invalida` (chave de colega):

---

## O que vocês mudaram no código

> (Além de preencher o `config.h`: mudaram algo no `.ino`, no `worker.js` ou na página? O quê e por quê?)

---

## Respostas

1. **No Passo 4 vocês trocaram a CA e a conexão falhou. Por que *falhar* é o comportamento correto? O que aconteceria com `setInsecure()` nessa mesma situação?**

2. **O TLS já cifra o caminho até o broker. Por que, mesmo assim, a temperatura aparecia legível para a turma no Passo 1, e por que o AES-GCM resolve isso?**

3. **Comparem API key e assinatura HMAC: o que um atacante consegue fazer se capturar *uma* requisição de cada tipo?**

4. **O `ts` vai *dentro* do corpo assinado. O que daria errado se ele fosse num cabeçalho separado, fora da assinatura?**

5. **Por que o Worker faz `request.text()` e assina o texto cru, em vez de fazer `request.json()` e montar o JSON de novo pra conferir?**

6. **As rotas `/list` e `/resumo` continuam abertas. Isso é problema? Para que tipo de dado (pensem no Projeto Final de vocês) passaria a ser?**

7. **A chave AES foi colada à mão na página. Como resolver isso num produto com mil dispositivos vendidos?**

8. **No seu Projeto Final, qual é o pior estrago que alguém faria sem as camadas de hoje? Qual camada vocês vão levar pra lá, e por quê?**

---

## Desafios extras (opcional)

- **Dado adicional autenticado:** passar o nome do tópico como *AAD* no AES-GCM
  (`mbedtls_gcm_crypt_and_tag(..., aad, aad_len, ...)`), pra que uma mensagem do `/cofre` de
  um colega não possa ser "transplantada" pro seu tópico.
- **Uma chave por dispositivo:** o Worker aceitar duas estações, cada uma com sua `CHAVE_HMAC`,
  escolhida pelo campo `nome` do corpo.
- **Alarme:** quando `/tentativas` passar de 10 recusas em 1 minuto, o Worker publicar um aviso
  (ou o ESP32 piscar o LED).
- **Rotação de chave:** trocar a `CHAVE_HMAC` sem derrubar o sistema (o Worker aceita a antiga e a
  nova por um tempo).

---

**Entrega:** este `ENTREGA.md` preenchido, `estacao_cofre.ino`, `worker.js` e `certificados.h`, no
GitHub de cada um, **sem o `config.h`**.
