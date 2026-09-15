# Atividade IoT — Banco de dados SQL na nuvem com Cloudflare D1

**Disciplina:** Internet das Coisas (IoT) · Turma AMF 2026-02
**Plataforma:** ESP32 (Arduino/PlatformIO) + Cloudflare Workers + Cloudflare D1

> **Continuação da atividade do KV.** Antes, você guardou os dados num banco
> **chave-valor** (KV). Agora vamos usar um **banco SQL de verdade** (o D1) e responder
> perguntas que no KV eram difíceis: *qual a temperatura média?*, *quantas leituras passaram
> de 30°C?*, *qual a máxima do dia?*. E o melhor: **o ESP32 quase não muda.**

Este documento tem duas partes. A **Parte 1 — Entenda** explica os conceitos (leia com
calma, é o conteúdo da aula). A **Parte 2 — Construa** é o passo a passo para você montar.
Leia a Parte 1 antes de pôr a mão na massa.

**Sumário**
- [Parte 1 — Entenda](#parte-1--entenda)
  - [1. O problema que o KV não resolvia bem](#1-o-problema-que-o-kv-não-resolvia-bem)
  - [2. O que é um banco de dados relacional](#2-o-que-é-um-banco-de-dados-relacional)
  - [3. KV × D1 (a comparação)](#3-kv--d1-a-comparação)
  - [4. O que é o Cloudflare D1](#4-o-que-é-o-cloudflare-d1)
  - [5. Tabelas: linhas, colunas, tipos e chave primária](#5-tabelas-linhas-colunas-tipos-e-chave-primária)
  - [6. SQL: a linguagem para conversar com o banco](#6-sql-a-linguagem-para-conversar-com-o-banco)
  - [7. Funções de resumo (agregação)](#7-funções-de-resumo-agregação)
  - [8. GROUP BY: resumo por grupo](#8-group-by-resumo-por-grupo)
  - [9. Como o Worker conversa com o D1 (e segurança)](#9-como-o-worker-conversa-com-o-d1-e-segurança)
  - [10. A grande sacada: o ESP32 não muda](#10-a-grande-sacada-o-esp32-não-muda)
- [Parte 2 — Construa (passo a passo)](#parte-2--construa-passo-a-passo)
- [Código de referência](#código-de-referência)
- [Entrega e perguntas](#entrega)

---

# Parte 1 — Entenda

## 1. O problema que o KV não resolvia bem

Na atividade anterior, o KV guardava os dados como **chave → valor** (ex.: `sensor:123 → { "temp": 26.4 }`).
É um banco **chave-valor distribuído globalmente**, ótimo para "pegar o último valor". Mas ele
tem uma **limitação**: **não faz consultas complexas** (`SELECT`, `WHERE`, etc.). Se você
quisesse a **temperatura média da última hora**, teria que **listar tudo** e calcular na mão,
dentro do código.

Bancos **relacionais** foram feitos exatamente para isso: **guardar muitos registros e responder
perguntas sobre eles** com facilidade. É o que vamos usar agora.

## 2. O que é um banco de dados relacional

Um banco **relacional** organiza os dados em **tabelas** — como uma planilha, com **linhas**
e **colunas**. Cada linha é um registro (uma leitura do sensor), e cada coluna é um campo
daquele registro (qual sensor, qual valor, quando foi medido).

A grande vantagem é que você conversa com o banco usando **SQL**, uma linguagem em que você
**descreve o que quer** ("a média da temperatura", "as 10 últimas leituras", "quantas passaram
de 30") e o banco faz o trabalho pesado de buscar e calcular.

## 3. KV × D1 (a comparação)

| Banco | Modelo | Melhor para… | Limites / característica |
|-------|--------|--------------|--------------------------|
| **KV** | Chave-valor | Últimos estados, cache, configs | ~25 MB por valor; **consistência eventual** |
| **D1** | **SQL** (SQLite) | Histórico, relatórios, consultas complexas | **SQL completo**; dados consistentes |

Em uma frase: **KV para estado simples; D1 para histórico e análise.** No D1 você pode escrever,
por exemplo:

```sql
SELECT * FROM leituras WHERE valor > 25 ORDER BY timestamp DESC;
```

## 4. O que é o Cloudflare D1

O **D1** é o banco de dados **SQL serverless** da Cloudflare, baseado no **SQLite** (um banco
relacional leve e muito usado). "Serverless" quer dizer o mesmo que no Worker: **você não
administra servidor nenhum** — cria o banco pelo painel e pronto.

Quem acessa o D1 é o seu **Worker**. Eles se conectam por um **binding** (uma "ligação")
chamado, nesta atividade, **`DB`**. No código do Worker, o banco aparece como `env.DB`.

```
ESP32  ──POST /insert──▶  Worker  ──SQL via env.DB──▶  D1 (tabela "leituras")
```

## 5. Tabelas: linhas, colunas, tipos e chave primária

Antes de guardar qualquer dado, você precisa **criar a tabela** — definir quais colunas ela terá
e o **tipo** de cada uma. A nossa tabela se chama `leituras`:

```sql
CREATE TABLE IF NOT EXISTS leituras (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,  -- numero unico de cada linha
  sensor    TEXT    NOT NULL,                   -- "temp" ou "umid"
  valor     REAL    NOT NULL,                   -- o numero medido
  timestamp INTEGER NOT NULL                    -- quando foi medido (em ms)
);
```

Entendendo cada parte:

- **Coluna** — um campo do registro: `id`, `sensor`, `valor`, `timestamp`.
- **Tipo** — o que a coluna guarda. `INTEGER` (inteiro), `REAL` (número com vírgula, ex.: 27.8), `TEXT` (texto).
- **`PRIMARY KEY AUTOINCREMENT`** — a **chave primária**: identificador **único** de cada linha. Com `AUTOINCREMENT`, o próprio banco numera as linhas (1, 2, 3…).
- **`NOT NULL`** — a coluna **não pode ficar vazia**.

Depois de gravar algumas leituras, a tabela fica assim:

| id | sensor | valor | timestamp     |
|----|--------|-------|---------------|
| 1  | temp   | 27.8  | 1699999990000 |
| 2  | umid   | 61.0  | 1699999990000 |
| 3  | temp   | 28.1  | 1700000020000 |

## 6. SQL: a linguagem para conversar com o banco

**SQL** (Structured Query Language) é a linguagem dos bancos relacionais. Você vai usar poucos
comandos, e cada um faz uma coisa:

- **`CREATE TABLE`** — cria a estrutura da tabela (você faz isso **uma vez**).
- **`INSERT INTO`** — adiciona **uma linha** (uma leitura).
  ```sql
  INSERT INTO leituras (sensor, valor, timestamp) VALUES ('temp', 27.8, 1699999990000);
  ```
- **`SELECT ... FROM`** — **lê** dados.
  ```sql
  SELECT valor, timestamp FROM leituras;
  ```
- **`WHERE`** — **filtra** as linhas.
  ```sql
  SELECT valor FROM leituras WHERE sensor = 'temp';
  SELECT valor FROM leituras WHERE valor > 30;
  ```
- **`ORDER BY`** — **ordena** (`ASC` crescente, `DESC` decrescente).
  ```sql
  SELECT valor, timestamp FROM leituras ORDER BY timestamp DESC;   -- mais novas primeiro
  ```
- **`LIMIT`** — **limita** a quantidade de linhas.
  ```sql
  SELECT valor FROM leituras ORDER BY timestamp DESC LIMIT 1;      -- só a mais nova (o "último valor")
  ```

Repare que **"ler o último valor"** (o que o `/get` fazia no KV) vira, no SQL, um
`ORDER BY timestamp DESC LIMIT 1`.

## 7. Funções de resumo (agregação)

Aqui está o que o KV não fazia fácil. As **funções de agregação** olham para **várias linhas**
e devolvem **um número que as resume**:

- **`COUNT(*)`** — conta quantas linhas.
- **`AVG(valor)`** — média dos valores.
- **`MIN(valor)`** / **`MAX(valor)`** — o menor / o maior valor.
- **`SUM(valor)`** — a soma.

```sql
-- Quantas leituras de temperatura existem?
SELECT COUNT(*) FROM leituras WHERE sensor = 'temp';

-- Média, mínima e máxima da temperatura:
SELECT AVG(valor), MIN(valor), MAX(valor) FROM leituras WHERE sensor = 'temp';

-- Quantas leituras de temperatura passaram de 30?
SELECT COUNT(*) FROM leituras WHERE sensor = 'temp' AND valor > 30;
```

Cada uma dessas perguntas, no KV, exigiria baixar tudo e calcular no código. No SQL, é **uma linha**.

## 8. GROUP BY: resumo por grupo

E se você quiser a média **de cada sensor** (temperatura e umidade) de uma vez? O **`GROUP BY`**
separa as linhas em grupos e aplica a agregação **dentro de cada grupo**.

Suponha a tabela:

| sensor | valor |
|--------|-------|
| temp   | 27.8  |
| temp   | 28.1  |
| umid   | 61.0  |
| umid   | 59.0  |

A consulta:

```sql
SELECT sensor, AVG(valor) AS media, MAX(valor) AS maximo
FROM leituras
GROUP BY sensor;
```

Devolve **uma linha por sensor**:

| sensor | media | maximo |
|--------|-------|--------|
| temp   | 27.95 | 28.1   |
| umid   | 60.0  | 61.0   |

É por isso que, nesta atividade, o DHT11 envia **dois sensores** (`temp` e `umid`): para o
`GROUP BY` ter o que agrupar.

## 9. Como o Worker conversa com o D1 (e segurança)

No Worker, você **prepara** o comando SQL, **liga** os valores e **executa**:

```javascript
await env.DB
  .prepare("INSERT INTO leituras (sensor, valor, timestamp) VALUES (?, ?, ?)")
  .bind(sensor, valor, Date.now())   // preenche os "?" na ordem
  .run();                            // executa
```

- **`.prepare("... ?...")`** — o texto do SQL, com **`?`** onde entram os valores.
- **`.bind(a, b, c)`** — preenche os `?`, **na ordem**.
- **`.run()`** — executa quando **não** espera linhas de volta (ex.: `INSERT`).
- **`.first()`** — devolve **a primeira linha** (ex.: `/get`, `/media`).
- **`.all()`** — devolve **todas as linhas** em `results` (ex.: `/list`, `/resumo`).

> **Por que os `?` e o `.bind()`?** Nunca cole o valor direto no texto do SQL. Se alguém enviar
> um texto malicioso, ele poderia virar comando e bagunçar o banco — o ataque chamado
> **SQL injection**. Usar `?` + `.bind()` é o jeito **seguro** e correto.

## 10. A grande sacada: o ESP32 não muda

Trocamos o banco inteiro (KV → D1) e reescrevemos o Worker, mas o **ESP32 continua fazendo a
mesma coisa**: conecta no Wi-Fi e manda `POST /insert` com um JSON. Ele **não sabe** o que tem
atrás da API. Isso se chama **desacoplamento**: o dispositivo e o backend são independentes, e
você pode evoluir um sem mexer no outro. (A única diferença desta vez é que o ESP32 manda
**dois** valores — `temp` e `umid` — para darmos uso ao `GROUP BY`.)

---

# Parte 2 — Construa (passo a passo)

Agora a mão na massa. Faça **um passo de cada vez** e só siga adiante quando a verificação
("Confira") der certo. As **telas de cada passo** (prints da Cloudflare) estão nos slides da aula.

### Passo 0 — Material e conta

- Hardware: **ESP32** + **DHT11** + protoboard e jumpers (o mesmo da atividade anterior).
- Uma conta no [Cloudflare](https://dash.cloudflare.com) (gratuita).

### Passo 1 — Criar o Worker (Workers & Pages)

- **O que fazer:** ter um Worker com uma URL pública.
- **Como:** no painel da Cloudflare, vá em **Workers & Pages → Create → Worker**, dê um nome
  (ex.: `iot-d1`) e clique **Deploy**. Se você já tem o Worker da atividade do KV, pode reaproveitá-lo.
- **Confira:** abra a URL que apareceu (ex.: `https://iot-d1.SEU-USUARIO.workers.dev`) — deve responder algo.

### Passo 2 — Criar o banco D1

- **O que fazer:** criar o banco de dados.
- **Como:** no painel, procure por **Storage & Databases → D1** e clique **Create** (ou "Create database"). Dê um nome, ex.: **`iot`**.
- **Por quê:** é onde a tabela e as leituras vão morar.
- **Confira:** o banco `iot` aparece na lista de bancos D1.

### Passo 3 — Associar o Worker ao D1 (o binding `DB`)

- **O que fazer:** ligar o seu Worker ao banco, para o código enxergar `env.DB`.
- **Como:** abra o **seu Worker → Settings → Bindings** (ou "Variables & Bindings") →
  **Add binding → D1 database**. Em **Variable name** escreva exatamente **`DB`**, escolha o
  banco `iot`, salve e faça **Deploy**.
- **Por quê:** sem o binding, o Worker não consegue falar com o banco.
- **Confira:** o binding `DB → iot` aparece listado nas configurações do Worker.

### Passo 4 — Criar a tabela `leituras`

- **O que fazer:** criar a estrutura onde os dados vão morar.
- **Como:** abra o banco **`iot`** no painel do D1, vá na aba **Console** (ou "Query"), cole o
  comando abaixo e clique **Execute/Run**:
  ```sql
  CREATE TABLE IF NOT EXISTS leituras (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    sensor    TEXT    NOT NULL,
    valor     REAL    NOT NULL,
    timestamp INTEGER NOT NULL
  );
  ```
- **Confira:** rode `SELECT * FROM leituras;` — deve executar sem erro (ainda sem linhas).

### Passo 5 — Programar o Worker (`/insert` e `/get`)

- **O que fazer:** fazer o Worker gravar e ler usando SQL.
- **Como:** no editor do Worker (**Edit code**), apague o conteúdo e cole o **primeiro bloco** da
  seção [Código do Worker](#código-do-worker). Clique **Deploy**.
- **Entenda:** o `/insert` roda um `INSERT INTO`; o `/get` roda um `SELECT ... ORDER BY timestamp DESC LIMIT 1` (o "último valor").
- **Confira:** abra `SUA-URL/get?sensor=temp` no navegador — deve dizer "Nenhum valor encontrado" (404), porque ainda não gravamos nada. Está certo!

### Passo 6 — Testar gravando e lendo (PowerShell)

- **O que fazer:** gravar algumas leituras à mão e conferir.
- **Como:** rode os comandos da seção [Testando pelo PowerShell](#testando-pelo-powershell). Grave 3 ou 4 valores diferentes de `temp`.
- **Confira:** `GET /get?sensor=temp` devolve o último valor gravado. **Tire um print.**

### Passo 7 — ESP32 enviando temperatura E umidade

- **O que fazer:** o sensor real alimenta o banco.
- **Como:** ligue o DHT11 (`VCC→3V3`, `GND→GND`, `DATA→GPIO 4`), instale a biblioteca **"DHT sensor library"** (Adafruit) e envie o código da seção [Código do ESP32](#código-do-esp32). Ele lê o DHT11, envia `temp` **e** `umid`, e entra em **deep sleep** por 30 s.
- **Por quê:** dois sensores dão sentido ao `GROUP BY`; o deep sleep é a economia de energia da aula anterior.
- **Confira:** no Serial Monitor você vê os dois envios e o "Dormindo…". Em `SUA-URL/get?sensor=umid` aparece a umidade.

### Passo 8 — Consultas de análise (`/list` e `/media`)

- **O que fazer:** responder perguntas sobre os dados.
- **Como:** troque o Worker pelo **segundo bloco** da seção [Código do Worker](#código-do-worker) e faça **Deploy**.
- **Confira:** `SUA-URL/media?sensor=temp` devolve **média, mínima, máxima e contagem** da temperatura. **Tire um print.**

### Passo 9 — `GROUP BY` com `/resumo`

- **O que fazer:** um resumo de **todos** os sensores numa consulta só.
- **Como:** o mesmo segundo bloco já tem o `/resumo` (usa `GROUP BY sensor`).
- **Confira:** `SUA-URL/resumo` devolve **uma linha para `temp` e outra para `umid`**, cada uma com média, máximo e contagem. **Tire um print.**

### Passo 10 — Entregar

- Preencha o **`ENTREGA.md`** com suas respostas, as **consultas SQL** que usou e os **prints**.
- Entregue ao professor da forma combinada (plataforma da turma / e-mail).

---

# Código de referência

## Código do Worker

Comece pelo **primeiro bloco** (Passo 5). No **Passo 8** troque pelo **segundo bloco**.

### Bloco 1 — `/insert` e `/get`

```javascript
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Gravar uma leitura
    if (url.pathname === "/insert" && request.method === "POST") {
      const body = await request.json();               // { sensor, valor }
      const sensor = body.sensor || "temp";
      const valor  = Number(body.valor ?? 0);

      await env.DB.prepare(
        "INSERT INTO leituras (sensor, valor, timestamp) VALUES (?, ?, ?)"
      ).bind(sensor, valor, Date.now()).run();

      return new Response(`OK: ${sensor}=${valor}`);
    }

    // Ler o último valor de um sensor
    if (url.pathname === "/get") {
      const sensor = url.searchParams.get("sensor") || "temp";
      const row = await env.DB.prepare(
        "SELECT valor, timestamp FROM leituras WHERE sensor = ? ORDER BY timestamp DESC LIMIT 1"
      ).bind(sensor).first();

      if (!row) return new Response("Nenhum valor encontrado", { status: 404 });
      return Response.json(row);
    }

    return new Response("Use POST /insert ou GET /get?sensor=temp");
  }
}
```

### Bloco 2 — adiciona `/list`, `/media` e `/resumo`

```javascript
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/insert" && request.method === "POST") {
      const body = await request.json();
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

    // Últimas 50 leituras de um sensor
    if (url.pathname === "/list") {
      const sensor = url.searchParams.get("sensor") || "temp";
      const { results } = await env.DB.prepare(
        "SELECT valor, timestamp FROM leituras WHERE sensor = ? ORDER BY timestamp DESC LIMIT 50"
      ).bind(sensor).all();
      return Response.json(results);
    }

    // Média, mínima, máxima e contagem de um sensor
    if (url.pathname === "/media") {
      const sensor = url.searchParams.get("sensor") || "temp";
      const row = await env.DB.prepare(
        `SELECT AVG(valor) AS media, MIN(valor) AS minimo,
                MAX(valor) AS maximo, COUNT(*) AS n
         FROM leituras WHERE sensor = ?`
      ).bind(sensor).first();
      return Response.json(row);
    }

    // Resumo de TODOS os sensores de uma vez (GROUP BY)
    if (url.pathname === "/resumo") {
      const { results } = await env.DB.prepare(
        `SELECT sensor, AVG(valor) AS media, MAX(valor) AS maximo, COUNT(*) AS n
         FROM leituras GROUP BY sensor`
      ).all();
      return Response.json(results);
    }

    return new Response("Use /insert, /get, /list, /media ou /resumo");
  }
}
```

> **Boas práticas:** os valores sempre entram por `?` + `.bind(...)`, nunca colados no texto do
> SQL. Além de ser o jeito certo, protege contra **SQL injection**.

## Testando pelo PowerShell

Troque a URL pela do **seu** Worker.

```powershell
# Gravar uma leitura de temperatura
Invoke-RestMethod `
  -Uri "https://sua-api.SEU-USUARIO.workers.dev/insert" `
  -Method POST `
  -Body (@{ sensor="temp"; valor=27.8 } | ConvertTo-Json) `
  -ContentType "application/json"

# Consultas
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/get?sensor=temp"
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/list?sensor=temp"
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/media?sensor=temp"
Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/resumo"
```

## Código do ESP32

**É quase igual ao da atividade anterior** — a diferença é enviar **dois valores** (temperatura
e umidade). Credenciais no `config.h`:

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

// Envia um valor para o Worker (POST /insert)
void enviar(const char* sensor, float valor) {
  HTTPClient http;
  http.begin(String(WORKER_URL) + "/insert");
  http.addHeader("Content-Type", "application/json");
  String corpo = String("{\"sensor\":\"") + sensor + "\",\"valor\":" + String(valor, 1) + "}";
  int code = http.POST(corpo);
  Serial.printf("  %s=%.1f -> HTTP %d\n", sensor, valor, code);
  http.end();
}

void setup() {
  Serial.begin(115200);
  dht.begin();

  WiFi.begin(WIFI_SSID, WIFI_PASS);              // 1) conecta no Wi-Fi
  Serial.print("Conectando ao WiFi");
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println(" ok");

  float t = dht.readTemperature();               // 2) le o sensor fisico
  float h = dht.readHumidity();
  envios++;
  Serial.printf("Envio #%d\n", envios);
  if (!isnan(t)) enviar("temp", t);              // 3) envia os dois valores
  if (!isnan(h)) enviar("umid", h);

  const uint64_t DORME_SEG = 30;                 // 4) dorme para poupar energia
  Serial.printf("Dormindo por %llu s...\n", DORME_SEG);
  Serial.flush();
  esp_sleep_enable_timer_wakeup(DORME_SEG * 1000000ULL);
  esp_deep_sleep_start();
}

void loop() { }   // nunca executa: tudo esta no setup()
```

---

# Entrega

Ao terminar o **Passo 10**: `ENTREGA.md` preenchido (respostas + consultas SQL + prints),
entregue ao professor da forma combinada. **Prazo:** a combinar.

## Critérios de avaliação

| Critério | Peso |
|---|---|
| Sistema funcionando: ESP32 → D1 → consultas respondendo | 40% |
| Modelagem e SQL corretos (tabela, `INSERT`, `SELECT`, `WHERE`) | 25% |
| Consultas de análise (`AVG`/`COUNT`/`MIN`/`MAX`) e `GROUP BY` no `/resumo` | 20% |
| `ENTREGA.md`: respostas e prints | 15% |

## Perguntas para responder no `ENTREGA.md`

1. Qual a diferença entre o **KV** (chave-valor) e um **banco relacional** como o D1? Quando cada um é melhor?
2. O que é o **D1** e o que é o **binding `DB`**?
3. Explique a tabela `leituras`: o que é cada **coluna** e seu **tipo**. Para que serve a **chave primária**?
4. Escreva a consulta SQL da **média da temperatura**. E a que **conta** quantas leituras de temperatura passaram de 30.
5. Para que serve o **`GROUP BY`** no `/resumo`? O que ele devolve?
6. Por que usamos `?` + `.bind(...)` em vez de colar o valor no texto do SQL?
7. O código do **ESP32** mudou muito ao trocar o KV pelo D1? O que isso ensina sobre a arquitetura?

Bom trabalho! 🚀
