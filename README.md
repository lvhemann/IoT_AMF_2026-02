# Atividade IoT — Estação de sensores na nuvem com Cloudflare D1

**Disciplina:** Internet das Coisas (IoT) · Turma AMF 2026-02
**Plataforma:** ESP32 (Arduino/PlatformIO) + Cloudflare Workers + Cloudflare D1

> **Continuação da atividade do KV.** Antes você guardou os dados num banco **chave-valor** (KV).
> Agora vamos usar um **banco SQL de verdade** (o D1) e montar uma **estação de sensores
> funcional**: o ESP32 lê **temperatura e umidade** (DHT11), envia as duas para a nuvem, e ainda
> registra um **log de cada conexão** (IP, sinal, tempo para conectar, internet). No fim você
> consulta tudo com SQL — inclusive médias e resumos que o KV não fazia fácil.

Este documento tem duas partes. A **Parte 1 — Entenda** explica os conceitos (é o conteúdo da
aula). A **Parte 2 — Construa** é o passo a passo. Leia a Parte 1 antes de pôr a mão na massa.

**Sumário**
- [Parte 1 — Entenda](#parte-1--entenda)
  - [1. O problema que o KV não resolvia bem](#1-o-problema-que-o-kv-não-resolvia-bem)
  - [2. O que é um banco de dados relacional](#2-o-que-é-um-banco-de-dados-relacional)
  - [3. KV × D1 (a comparação)](#3-kv--d1-a-comparação)
  - [4. O que é o Cloudflare D1](#4-o-que-é-o-cloudflare-d1)
  - [5. As tabelas do projeto](#5-as-tabelas-do-projeto)
  - [6. SQL: a linguagem para conversar com o banco](#6-sql-a-linguagem-para-conversar-com-o-banco)
  - [7. Funções de resumo (agregação)](#7-funções-de-resumo-agregação)
  - [8. GROUP BY: resumo por grupo](#8-group-by-resumo-por-grupo)
  - [9. O log de conexão (diagnóstico do dispositivo)](#9-o-log-de-conexão-diagnóstico-do-dispositivo)
  - [10. Como o Worker conversa com o D1 (e segurança)](#10-como-o-worker-conversa-com-o-d1-e-segurança)
- [Parte 2 — Construa (passo a passo)](#parte-2--construa-passo-a-passo)
- [Código de referência](#código-de-referência)
- [Entrega e perguntas](#entrega)

---

# Parte 1 — Entenda

## 1. O problema que o KV não resolvia bem

Na atividade anterior, o KV guardava os dados como **chave → valor** (ex.: `sensor:123 → { "temp": 26.4 }`).
É um banco **chave-valor distribuído globalmente**, ótimo para "pegar o último valor". Mas ele
tem uma **limitação**: **não faz consultas complexas** (`SELECT`, `WHERE`, etc.). Para a
**temperatura média da última hora**, você teria que **listar tudo** e calcular na mão, no código.

Bancos **relacionais** foram feitos exatamente para isso: **guardar muitos registros e responder
perguntas sobre eles** com facilidade.

## 2. O que é um banco de dados relacional

Um banco **relacional** organiza os dados em **tabelas** — como uma planilha, com **linhas** e
**colunas**. Cada linha é um registro; cada coluna é um campo. Você conversa com o banco usando
**SQL**, uma linguagem em que você **descreve o que quer** e o banco busca e calcula.

## 3. KV × D1 (a comparação)

| Banco | Modelo | Melhor para… | Limites / característica |
|-------|--------|--------------|--------------------------|
| **KV** | Chave-valor | Últimos estados, cache, configs | ~25 MB por valor; **consistência eventual** |
| **D1** | **SQL** (SQLite) | Histórico, relatórios, consultas complexas | **SQL completo**; dados consistentes |

Em uma frase: **KV para estado simples; D1 para histórico e análise.** No D1 você pode escrever:

```sql
SELECT * FROM leituras WHERE valor > 25 ORDER BY timestamp DESC;
```

## 4. O que é o Cloudflare D1

O **D1** é o banco de dados **SQL serverless** da Cloudflare, baseado no **SQLite**. "Serverless"
quer dizer que **você não administra servidor nenhum** — cria o banco pelo painel e pronto. Quem
acessa o D1 é o seu **Worker**, através de um **binding** (uma "ligação") chamado aqui **`DB`**.
No código, o banco aparece como `env.DB`.

```
ESP32  ──POST /insert e /log──▶  Worker  ──SQL via env.DB──▶  D1 (tabelas "leituras" e "conexoes")
```

## 5. As tabelas do projeto

Nossa estação usa **duas tabelas**. A primeira guarda as **medições** dos sensores:

```sql
CREATE TABLE IF NOT EXISTS leituras (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,  -- numero unico de cada linha
  sensor    TEXT    NOT NULL,                   -- "temp" ou "umid"
  valor     REAL    NOT NULL,                   -- o numero medido
  timestamp INTEGER NOT NULL                    -- quando foi medido (ms)
);
```

A segunda guarda os **logs de conexão** do dispositivo (veja a seção 9):

```sql
CREATE TABLE IF NOT EXISTS conexoes (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  ip        TEXT,               -- IP que o ESP32 recebeu na rede
  rssi      INTEGER,            -- forca do sinal Wi-Fi (dBm)
  tempo_ms  INTEGER,            -- tempo que levou para conectar (ms)
  internet  INTEGER,            -- 1 = internet respondeu, 0 = nao
  timestamp INTEGER NOT NULL
);
```

Entendendo a estrutura de uma tabela (vale para as duas):

- **Coluna** — um campo do registro. **Tipo** — o que ela guarda: `INTEGER` (inteiro),
  `REAL` (com vírgula, ex.: 27.8), `TEXT` (texto).
- **`PRIMARY KEY AUTOINCREMENT`** — a **chave primária**: identificador **único** de cada linha,
  numerado pelo próprio banco (1, 2, 3…).
- **`NOT NULL`** — a coluna não pode ficar vazia.

## 6. SQL: a linguagem para conversar com o banco

Você vai usar poucos comandos, cada um com um papel:

- **`CREATE TABLE`** — cria a estrutura (uma vez).
- **`INSERT INTO`** — adiciona uma linha:
  ```sql
  INSERT INTO leituras (sensor, valor, timestamp) VALUES ('temp', 27.8, 1699999990000);
  ```
- **`SELECT ... FROM`** — lê dados. **`WHERE`** filtra; **`ORDER BY`** ordena; **`LIMIT`** limita:
  ```sql
  SELECT valor, timestamp FROM leituras
  WHERE sensor = 'temp' ORDER BY timestamp DESC LIMIT 1;   -- o "ultimo valor"
  ```

Repare: **"ler o último valor"** (o que o `/get` fazia no KV) vira `ORDER BY timestamp DESC LIMIT 1`.

## 7. Funções de resumo (agregação)

As **funções de agregação** olham várias linhas e devolvem **um número que as resume**:
`COUNT(*)` (quantas), `AVG(valor)` (média), `MIN`/`MAX` (menor/maior), `SUM` (soma).

```sql
SELECT AVG(valor), MIN(valor), MAX(valor) FROM leituras WHERE sensor = 'temp';
SELECT COUNT(*) FROM leituras WHERE sensor = 'temp' AND valor > 30;   -- quantas passaram de 30
```

No KV, isso exigia baixar tudo e calcular no código. No SQL, é **uma linha**.

## 8. GROUP BY: resumo por grupo

O **`GROUP BY`** separa as linhas em grupos e aplica a agregação **dentro de cada grupo**.
Como enviamos **dois sensores** (`temp` e `umid`), podemos resumir os dois de uma vez:

```sql
SELECT sensor, AVG(valor) AS media, MAX(valor) AS maximo
FROM leituras
GROUP BY sensor;
```

| sensor | media | maximo |
|--------|-------|--------|
| temp   | 27.95 | 28.1   |
| umid   | 60.0  | 61.0   |

O banco **agrupou** por `sensor` e calculou a média e o máximo em cada grupo.

## 9. O log de conexão (diagnóstico do dispositivo)

Numa estação de verdade, não basta guardar as medições — você também quer saber **se o dispositivo
está saudável**: ele conectou? com qual **IP**? a **internet** respondeu? **quanto tempo** levou
para conectar? qual a **força do sinal**? Esses dados formam um **log de conexão**, e ajudam muito
a diagnosticar problemas no campo (ex.: um sensor que demora demais para conectar pode estar longe
do roteador).

A cada ciclo, o ESP32 mede e envia (por `POST /log`):

- **IP** — o endereço que o roteador deu ao ESP32 (ex.: `192.168.0.42`). Ele vem de `WiFi.localIP()`.
- **RSSI** — a força do sinal Wi-Fi, em dBm (quanto mais perto de 0, melhor; ex.: -55 é bom, -85 é fraco). Vem de `WiFi.RSSI()`.
- **tempo_ms** — quanto tempo levou para conectar. Medimos com `millis()` **antes** e **depois** de conectar e subtraímos.
- **internet** — se a nuvem respondeu (1) ou não (0). Conectar ao **roteador** não garante **internet**; sabemos que há internet porque o `POST` para o Worker recebeu uma resposta HTTP.

Tudo isso vai para a tabela `conexoes` e pode ser listado por `GET /logs`.

## 10. Como o Worker conversa com o D1 (e segurança)

No Worker, você **prepara** o SQL, **liga** os valores e **executa**:

```javascript
await env.DB
  .prepare("INSERT INTO leituras (sensor, valor, timestamp) VALUES (?, ?, ?)")
  .bind(sensor, valor, Date.now())   // preenche os "?" na ordem
  .run();
```

- **`.prepare("... ?...")`** — o SQL, com **`?`** onde entram os valores.
- **`.bind(a, b, c)`** — preenche os `?`, na ordem.
- **`.run()`** — executa sem esperar linhas (ex.: `INSERT`). **`.first()`** — a primeira linha.
  **`.all()`** — todas as linhas (em `results`).

> **Segurança:** nunca cole o valor direto no texto do SQL. Use `?` + `.bind()` — protege contra
> **SQL injection**.

**A grande sacada:** trocamos o banco (KV → D1) e reescrevemos o Worker, mas o **ESP32 continua
mandando JSON por HTTP** — ele não sabe o que tem atrás da API. Isso é **desacoplamento**: dá para
evoluir o backend sem mexer no hardware.

---

# Parte 2 — Construa (passo a passo)

Faça **um passo de cada vez** e só siga quando o "Confira" der certo. As **telas de cada passo**
(prints da Cloudflare) estão nos slides da aula.

### Passo 0 — Material e conta

- Hardware: **ESP32** + **DHT11** + protoboard e jumpers.
- Uma conta no [Cloudflare](https://dash.cloudflare.com) (gratuita).

### Passo 1 — Criar o Worker (Workers & Pages)

- **Como:** **Workers & Pages → Create → Worker**, dê um nome (ex.: `iot-d1`) e **Deploy**. (Pode reaproveitar o Worker do KV.)
- **Confira:** a URL (ex.: `https://iot-d1.SEU-USUARIO.workers.dev`) responde algo.

### Passo 2 — Criar o banco D1

- **Como:** **Storage & Databases → D1 → Create**. Nome: **`iot`**.
- **Confira:** o banco `iot` aparece na lista.

### Passo 3 — Associar o Worker ao D1 (binding `DB`)

- **Como:** **seu Worker → Settings → Bindings → Add binding → D1 database**. Variable name: **`DB`**, banco `iot`. Salve e **Deploy**.
- **Por quê:** sem o binding, o código não enxerga `env.DB`.
- **Confira:** o binding `DB → iot` aparece nas configurações.

### Passo 4 — Criar as DUAS tabelas

- **Como:** abra o banco `iot` → aba **Console** e rode os **dois** comandos (seção [As tabelas](#5-as-tabelas-do-projeto)): `CREATE TABLE ... leituras` e `CREATE TABLE ... conexoes`.
- **Confira:** `SELECT * FROM leituras;` e `SELECT * FROM conexoes;` executam sem erro.

### Passo 5 — Programar o Worker

- **Como:** no editor do Worker, cole o código da seção [Código do Worker](#código-do-worker) (já traz todos os endpoints) e **Deploy**.
- **Confira:** `SUA-URL/get?sensor=temp` responde 404 ("Nenhum valor") — normal, ainda sem dados.

### Passo 6 — Testar gravando à mão (PowerShell)

- **Como:** rode os comandos da seção [Testando pelo PowerShell](#testando-pelo-powershell): grave alguns `temp` e alguns `umid`.
- **Confira:** `/list?sensor=temp` e `/list?sensor=umid` mostram as leituras; `/resumo` mostra os dois sensores. **Print.**

### Passo 7 — ESP32: temperatura, umidade E log de conexão

- **Como:** ligue o DHT11 (`VCC→3V3`, `GND→GND`, `DATA→GPIO 4`), instale a biblioteca **"DHT sensor library"** (Adafruit) e envie o código da seção [Código do ESP32](#código-do-esp32). A cada ciclo ele: mede o **tempo para conectar**, pega **IP** e **RSSI**, envia **`temp`** e **`umid`**, envia o **log** (`/log`) e entra em **deep sleep**.
- **Confira:** no Serial Monitor aparecem o IP, o RSSI, o tempo e os envios. Em `SUA-URL/get?sensor=umid` aparece a umidade; em `SUA-URL/logs` aparece o log. **Print.**

### Passo 8 — Consultas de análise e o resumo

- **Confira:** `SUA-URL/media?sensor=temp` (média/mín/máx/contagem) e `SUA-URL/resumo` (os dois sensores, com `GROUP BY`) respondem certo. `SUA-URL/logs` lista as conexões. **Prints.**

### Passo 9 — Entregar (produto funcional)

Sua estação precisa estar **funcionando de verdade**. Para entregar:

1. O ESP32 grava **temperatura e umidade** reais (DHT11) — confirmado em `/list?sensor=temp` e `/list?sensor=umid`.
2. O `/resumo` mostra os **dois sensores** com `GROUP BY`.
3. O **log de conexão** funciona: `/logs` mostra **IP, RSSI, tempo de conexão e internet** de cada ciclo.
4. Preencha o **`ENTREGA.md`** (respostas, consultas SQL e prints) e entregue ao professor da forma combinada.

---

# Código de referência

## Código do Worker

```javascript
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // ---- SENSORES ----
    if (url.pathname === "/insert" && request.method === "POST") {
      const body = await request.json();               // { sensor, valor }
      const sensor = body.sensor || "temp";
      const valor  = Number(body.valor ?? 0);
      await env.DB.prepare(
        "INSERT INTO leituras (sensor, valor, timestamp) VALUES (?, ?, ?)"
      ).bind(sensor, valor, Date.now()).run();
      return new Response(`OK: ${sensor}=${valor}`);
    }

    if (url.pathname === "/get") {
      const sensor = url.searchParams.get("sensor") || "temp";
      const row = await env.DB.prepare(
        "SELECT valor, timestamp FROM leituras WHERE sensor = ? ORDER BY timestamp DESC LIMIT 1"
      ).bind(sensor).first();
      if (!row) return new Response("Nenhum valor encontrado", { status: 404 });
      return Response.json(row);
    }

    if (url.pathname === "/list") {
      const sensor = url.searchParams.get("sensor") || "temp";
      const { results } = await env.DB.prepare(
        "SELECT valor, timestamp FROM leituras WHERE sensor = ? ORDER BY timestamp DESC LIMIT 50"
      ).bind(sensor).all();
      return Response.json(results);
    }

    if (url.pathname === "/media") {
      const sensor = url.searchParams.get("sensor") || "temp";
      const row = await env.DB.prepare(
        `SELECT AVG(valor) AS media, MIN(valor) AS minimo,
                MAX(valor) AS maximo, COUNT(*) AS n
         FROM leituras WHERE sensor = ?`
      ).bind(sensor).first();
      return Response.json(row);
    }

    if (url.pathname === "/resumo") {
      const { results } = await env.DB.prepare(
        `SELECT sensor, AVG(valor) AS media, MAX(valor) AS maximo, COUNT(*) AS n
         FROM leituras GROUP BY sensor`
      ).all();
      return Response.json(results);
    }

    // ---- LOG DE CONEXAO ----
    if (url.pathname === "/log" && request.method === "POST") {
      const b = await request.json();   // { ip, rssi, tempo_ms, internet }
      await env.DB.prepare(
        "INSERT INTO conexoes (ip, rssi, tempo_ms, internet, timestamp) VALUES (?, ?, ?, ?, ?)"
      ).bind(b.ip || "", Number(b.rssi ?? 0), Number(b.tempo_ms ?? 0),
             Number(b.internet ?? 0), Date.now()).run();
      return new Response("LOG OK");
    }

    if (url.pathname === "/logs") {
      const { results } = await env.DB.prepare(
        "SELECT ip, rssi, tempo_ms, internet, timestamp FROM conexoes ORDER BY timestamp DESC LIMIT 50"
      ).all();
      return Response.json(results);
    }

    return new Response("Use /insert, /get, /list, /media, /resumo, /log, /logs");
  }
}
```

## Testando pelo PowerShell

```powershell
# Gravar temperatura e umidade
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/insert" -Method POST `
  -Body (@{ sensor="temp"; valor=27.8 } | ConvertTo-Json) -ContentType "application/json"
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/insert" -Method POST `
  -Body (@{ sensor="umid"; valor=61 } | ConvertTo-Json) -ContentType "application/json"

# Consultar
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/list?sensor=temp"
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/list?sensor=umid"
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/media?sensor=temp"
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/resumo"
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/logs"
```

## Código do ESP32

Credenciais no `config.h`:

```cpp
// config.h
#define WIFI_SSID   "SEU_WIFI"
#define WIFI_PASS   "SUA_SENHA"
#define WORKER_URL  "https://sua-api.SEU-USUARIO.workers.dev"
```

```cpp
#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include "config.h"

#define DHTPIN  4
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

RTC_DATA_ATTR int envios = 0;          // sobrevive ao deep sleep

// Envia um valor de sensor (POST /insert). Devolve o codigo HTTP.
int enviar(const char* sensor, float valor) {
  HTTPClient http;
  http.begin(String(WORKER_URL) + "/insert");
  http.addHeader("Content-Type", "application/json");
  String corpo = String("{\"sensor\":\"") + sensor + "\",\"valor\":" + String(valor, 1) + "}";
  int code = http.POST(corpo);
  Serial.printf("  %s=%.1f -> HTTP %d\n", sensor, valor, code);
  http.end();
  return code;
}

// Envia o log de conexao (POST /log)
void enviarLog(String ip, int rssi, long tempo_ms, int internet) {
  HTTPClient http;
  http.begin(String(WORKER_URL) + "/log");
  http.addHeader("Content-Type", "application/json");
  String corpo = "{\"ip\":\"" + ip + "\",\"rssi\":" + String(rssi) +
                 ",\"tempo_ms\":" + String(tempo_ms) +
                 ",\"internet\":" + String(internet) + "}";
  int code = http.POST(corpo);
  Serial.printf("  LOG (ip=%s rssi=%d %ldms net=%d) -> HTTP %d\n",
                ip.c_str(), rssi, tempo_ms, internet, code);
  http.end();
}

void setup() {
  Serial.begin(115200);
  dht.begin();

  // 1) Conecta no Wi-Fi medindo o tempo
  unsigned long t0 = millis();
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Conectando ao WiFi");
  while (WiFi.status() != WL_CONNECTED) { delay(200); Serial.print("."); }
  long tempo = millis() - t0;                 // tempo para conectar (ms)
  String ip  = WiFi.localIP().toString();     // IP recebido na rede
  int   rssi = WiFi.RSSI();                    // forca do sinal (dBm)
  Serial.printf("\n ok | IP=%s | RSSI=%d dBm | %ld ms\n", ip.c_str(), rssi, tempo);

  // 2) Le o DHT11 e envia temperatura E umidade
  envios++;
  Serial.printf("Envio #%d\n", envios);
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  int code = 0;
  if (!isnan(t)) code = enviar("temp", t);
  if (!isnan(h)) enviar("umid", h);

  // 3) Envia o log de conexao (internet = a nuvem respondeu?)
  int internet = (code > 0) ? 1 : 0;
  enviarLog(ip, rssi, tempo, internet);

  // 4) Deep sleep para economizar energia
  const uint64_t DORME_SEG = 30;
  Serial.printf("Dormindo por %llu s...\n", DORME_SEG);
  Serial.flush();
  esp_sleep_enable_timer_wakeup(DORME_SEG * 1000000ULL);
  esp_deep_sleep_start();
}

void loop() { }   // nunca executa: tudo esta no setup()
```

---

# Entrega

**Produto final:** uma estação que grava temperatura e umidade reais no D1, lista as duas,
faz resumos com SQL e mantém um log das conexões do dispositivo. Entregue o `ENTREGA.md`
preenchido (respostas + consultas SQL + prints).

## Perguntas para responder

**Banco de dados**

1. Com suas palavras, qual a diferença entre um banco **chave-valor (KV)** e um **relacional (D1)**? Dê um exemplo de pergunta que é fácil de responder no D1 e difícil no KV.
2. O que é o **binding `DB`**? Sem ele, o que aconteceria ao usar `env.DB` no Worker?
3. Descreva as tabelas `leituras` e `conexoes`: o que cada **coluna** guarda e o seu **tipo**. O que é a **chave primária** (`id`) e para que serve?

**SQL**

4. Escreva a consulta SQL que retorna a **média da temperatura**.
5. Escreva a consulta SQL que **conta quantas leituras de temperatura passaram de 30**.
6. O que o **`GROUP BY sensor`** faz no `/resumo`? Quantas linhas ele devolve na sua estação, e por quê?

**Dispositivo e conexão**

7. Quais dados o **log de conexão** registra? Explique como cada um ajuda a diagnosticar um sensor instalado no campo.
8. Como o ESP32 calcula o **tempo de conexão**? O que representam o **IP** e o **RSSI** de uma conexão Wi-Fi?
9. Conectar-se ao roteador é o mesmo que ter **internet**? Explique como o campo **`internet`** do log distingue as duas situações.

Bom trabalho! 
