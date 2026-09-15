# Atividade IoT — Banco de dados SQL na nuvem com Cloudflare D1

**Disciplina:** Internet das Coisas (IoT) · Turma AMF 2026-02
**Plataforma:** ESP32 (Arduino/PlatformIO) + Cloudflare Workers + Cloudflare D1

> **Continuação da atividade do KV.** Antes, você guardou os dados num banco
> **chave-valor** (KV). Agora vamos usar um **banco SQL de verdade** (o D1) e responder
> perguntas que no KV eram difíceis: *qual a temperatura média?*, *quantas leituras passaram
> de 30°C?*, *qual a máxima do dia?*. E o melhor: **o ESP32 quase não muda.**

Este documento tem duas partes. A **Parte 1 — Entenda** explica os conceitos (leia com
calma, é o conteúdo da aula). A **Parte 2 — Construa** é o passo a passo para você montar e
entregar. Leia a Parte 1 antes de pôr a mão na massa.

**Sumário**
- [Parte 1 — Entenda](#parte-1--entenda)
  - [1. O problema que o KV não resolvia bem](#1-o-problema-que-o-kv-não-resolvia-bem)
  - [2. O que é um banco de dados relacional](#2-o-que-é-um-banco-de-dados-relacional)
  - [3. O que é o Cloudflare D1](#3-o-que-é-o-cloudflare-d1)
  - [4. Tabelas: linhas, colunas, tipos e chave primária](#4-tabelas-linhas-colunas-tipos-e-chave-primária)
  - [5. SQL: a linguagem para conversar com o banco](#5-sql-a-linguagem-para-conversar-com-o-banco)
  - [6. Funções de resumo (agregação)](#6-funções-de-resumo-agregação)
  - [7. GROUP BY: resumo por grupo](#7-group-by-resumo-por-grupo)
  - [8. Como o Worker conversa com o D1 (e segurança)](#8-como-o-worker-conversa-com-o-d1-e-segurança)
  - [9. A grande sacada: o ESP32 não muda](#9-a-grande-sacada-o-esp32-não-muda)
- [Parte 2 — Construa (passo a passo)](#parte-2--construa-passo-a-passo)
- [Código de referência](#código-de-referência)
- [Entrega e perguntas](#entrega)

---

# Parte 1 — Entenda

## 1. O problema que o KV não resolvia bem

Na atividade anterior, o KV guardava os dados como **chave → valor**. Isso é ótimo para
"pegar o último valor", mas ruim para **perguntar** coisas sobre os dados. Se você quisesse a
**temperatura média da última hora**, teria que **listar todas** as leituras e calcular na mão,
dentro do código. Conforme os dados crescem, isso fica lento e trabalhoso.

Bancos **relacionais** foram feitos exatamente para isso: **guardar muitos registros e responder
perguntas sobre eles** com facilidade. É o que vamos usar agora.

## 2. O que é um banco de dados relacional

Um banco **relacional** organiza os dados em **tabelas** — como uma planilha, com **linhas**
e **colunas**. Cada linha é um registro (uma leitura do sensor), e cada coluna é um campo
daquele registro (qual sensor, qual valor, quando foi medido).

A grande vantagem é que você conversa com o banco usando **SQL**, uma linguagem em que você
**descreve o que quer** ("a média da temperatura", "as 10 últimas leituras", "quantas passaram
de 30") e o banco faz o trabalho pesado de buscar e calcular.

| | KV (antes) | Banco relacional / D1 (agora) |
|---|---|---|
| Organização | `chave → valor` | **tabelas** com linhas e colunas |
| Como pergunto | pego uma chave; o resto é no código | escrevo uma consulta **SQL** |
| "Média da temperatura" | listar tudo e somar na mão | `SELECT AVG(valor) ...` |
| Melhor para | último valor, cache, estado simples | **histórico e análise** |

## 3. O que é o Cloudflare D1

O **D1** é o banco de dados **SQL serverless** da Cloudflare. Ele é baseado no **SQLite** (um
banco relacional muito usado e leve). "Serverless" quer dizer o mesmo que no Worker: **você não
administra servidor nenhum** — cria o banco pelo painel e pronto.

Quem acessa o D1 é o seu **Worker**. Eles se conectam por um **binding** (uma "ligação")
chamado, nesta atividade, **`DB`**. No código do Worker, o banco aparece como `env.DB`.

```
ESP32  ──POST /insert──▶  Worker  ──SQL via env.DB──▶  D1 (tabela "leituras")
```

## 4. Tabelas: linhas, colunas, tipos e chave primária

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

- **Coluna** — um campo do registro. Aqui: `id`, `sensor`, `valor`, `timestamp`.
- **Tipo** — o que a coluna guarda. `INTEGER` (número inteiro), `REAL` (número com vírgula,
  ex.: 27.8), `TEXT` (texto).
- **`PRIMARY KEY AUTOINCREMENT`** — a **chave primária**: um identificador **único** de cada
  linha. Com `AUTOINCREMENT`, o próprio banco numera as linhas (1, 2, 3, …) — você não precisa
  se preocupar com o `id`.
- **`NOT NULL`** — aquela coluna **não pode ficar vazia** (toda leitura tem que ter sensor,
  valor e momento).

Depois de gravar algumas leituras, a tabela fica assim:

| id | sensor | valor | timestamp     |
|----|--------|-------|---------------|
| 1  | temp   | 27.8  | 1699999990000 |
| 2  | umid   | 61.0  | 1699999990000 |
| 3  | temp   | 28.1  | 1700000020000 |

## 5. SQL: a linguagem para conversar com o banco

**SQL** (Structured Query Language) é a linguagem dos bancos relacionais. Você vai usar poucos
comandos, e cada um faz uma coisa:

- **`CREATE TABLE`** — cria a estrutura da tabela (você faz isso **uma vez**).
  ```sql
  CREATE TABLE leituras (id INTEGER PRIMARY KEY AUTOINCREMENT, sensor TEXT, valor REAL, timestamp INTEGER);
  ```
- **`INSERT INTO`** — adiciona **uma linha** (uma leitura).
  ```sql
  INSERT INTO leituras (sensor, valor, timestamp) VALUES ('temp', 27.8, 1699999990000);
  ```
- **`SELECT ... FROM`** — **lê** dados de uma tabela.
  ```sql
  SELECT valor, timestamp FROM leituras;
  ```
- **`WHERE`** — **filtra**: só as linhas que atendem à condição.
  ```sql
  SELECT valor FROM leituras WHERE sensor = 'temp';
  SELECT valor FROM leituras WHERE valor > 30;
  ```
- **`ORDER BY`** — **ordena** o resultado (`ASC` crescente, `DESC` decrescente).
  ```sql
  SELECT valor, timestamp FROM leituras ORDER BY timestamp DESC;   -- mais novas primeiro
  ```
- **`LIMIT`** — **limita** a quantidade de linhas devolvidas.
  ```sql
  SELECT valor FROM leituras ORDER BY timestamp DESC LIMIT 1;      -- só a mais nova (o "último valor")
  ```

Repare que **"ler o último valor"** (o que o `/get` fazia no KV) vira, no SQL, um
`ORDER BY timestamp DESC LIMIT 1`.

## 6. Funções de resumo (agregação)

Aqui está o que o KV não fazia fácil. As **funções de agregação** olham para **várias linhas**
e devolvem **um número que as resume**:

- **`COUNT(*)`** — conta quantas linhas.
- **`AVG(valor)`** — média dos valores.
- **`MIN(valor)`** / **`MAX(valor)`** — o menor / o maior valor.
- **`SUM(valor)`** — a soma.

Exemplos:

```sql
-- Quantas leituras de temperatura existem?
SELECT COUNT(*) FROM leituras WHERE sensor = 'temp';

-- Média, mínima e máxima da temperatura:
SELECT AVG(valor), MIN(valor), MAX(valor) FROM leituras WHERE sensor = 'temp';

-- Quantas leituras de temperatura passaram de 30?
SELECT COUNT(*) FROM leituras WHERE sensor = 'temp' AND valor > 30;
```

Cada uma dessas perguntas, no KV, exigiria baixar tudo e calcular no código. No SQL, é **uma linha**.

## 7. GROUP BY: resumo por grupo

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

Ou seja: o banco **agrupou** as linhas por `sensor` e calculou a média e o máximo em cada grupo.
É por isso que, nesta atividade, o DHT11 envia **dois sensores** (`temp` e `umid`): para o
`GROUP BY` ter o que agrupar.

## 8. Como o Worker conversa com o D1 (e segurança)

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
- **`.first()`** — executa e devolve **a primeira linha** (ex.: `/get`, `/media`).
- **`.all()`** — executa e devolve **todas as linhas** em `results` (ex.: `/list`, `/resumo`).

> **Por que os `?` e o `.bind()`?** Nunca cole o valor direto no texto do SQL (ex.:
> `"... valor = " + entrada`). Se alguém enviar um texto malicioso, ele poderia virar comando
> e bagunçar o banco — é o ataque chamado **SQL injection**. Usar `?` + `.bind()` é o jeito
> **seguro** e correto.

## 9. A grande sacada: o ESP32 não muda

Trocamos o banco inteiro (KV → D1) e reescrevemos o Worker, mas o **ESP32 continua fazendo a
mesma coisa**: conecta no Wi-Fi e manda `POST /insert` com um JSON. Ele **não sabe** o que tem
atrás da API. Isso se chama **desacoplamento**: o dispositivo e o backend são independentes, e
você pode evoluir um sem mexer no outro. É um dos conceitos mais importantes de sistemas de IoT.

(A única diferença no ESP32 desta vez é que ele manda **dois** valores — `temp` e `umid` — para
darmos uso ao `GROUP BY`.)

---

# Parte 2 — Construa (passo a passo)

Agora a mão na massa. Faça **um passo de cada vez** e dê um **commit** ao final de cada um
(veja como no Passo 1). Parte da avaliação é ver a atividade **evoluindo** nos commits, e não
pronta de uma vez.

### Passo 0 — Material e contas

- Hardware: **ESP32** + **DHT11** + protoboard e jumpers (o mesmo da atividade anterior).
- Contas: uma no [GitHub](https://github.com) e uma no [Cloudflare](https://dash.cloudflare.com) (gratuitas).
- **Faça o fork** deste repositório (botão **Fork**, no topo) e **clone** o seu fork:
  ```bash
  git clone https://github.com/SEU-USUARIO/atividade-iot-d1.git
  cd atividade-iot-d1
  ```

### Passo 1 — O ciclo do Git (você vai repetir a cada passo)

Depois de terminar um passo, salve no GitHub com três comandos:

```bash
git add .
git commit -m "Passo 3: banco D1 criado e ligado ao Worker"
git push
```

> Faça commits **pequenos e frequentes**, um por passo, com uma mensagem que diga o que você fez.

### Passo 2 — Criar (ou abrir) o seu Worker

- **O que fazer:** ter um Worker com uma URL pública.
- **Como:** no painel da Cloudflare, vá em **Workers & Pages → Create → Worker**, dê um nome
  (ex.: `iot-d1`) e clique **Deploy**. Se você já tem o Worker da atividade do KV, pode usar o mesmo.
- **Confira:** abra a URL que apareceu (algo como `https://iot-d1.SEU-USUARIO.workers.dev`). Deve responder algo.

### Passo 3 — Criar o banco D1 e ligá-lo ao Worker

- **O que fazer:** criar o banco e conectá-lo ao Worker.
- **Como:**
  1. No painel, procure por **Storage & Databases → D1** e clique **Create** (ou "Create database"). Dê um nome, ex.: **`iot`**.
  2. Abra o **seu Worker → Settings → Bindings** (ou "Variables & Bindings") → **Add binding → D1 database**.
  3. Em **Variable name** escreva exatamente **`DB`** e escolha o banco `iot`. Salve e faça **Deploy**.
- **Por quê:** o **binding** é o que permite o código escrever `env.DB`. Sem ele, o Worker não enxerga o banco.
- **Confira:** o binding `DB → iot` deve aparecer listado nas configurações do Worker.

### Passo 4 — Criar a tabela `leituras`

- **O que fazer:** criar a estrutura onde os dados vão morar.
- **Como:** abra o banco **`iot`** no painel do D1 e vá na aba **Console** (ou "Query"). Cole o
  comando abaixo e clique **Execute/Run**:
  ```sql
  CREATE TABLE IF NOT EXISTS leituras (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    sensor    TEXT    NOT NULL,
    valor     REAL    NOT NULL,
    timestamp INTEGER NOT NULL
  );
  ```
- **Por quê:** você só pode gravar depois que a tabela existe (ver Parte 1, seção 4).
- **Confira:** rode `SELECT * FROM leituras;` — deve executar sem erro (ainda sem linhas).

### Passo 5 — Programar o Worker (`/insert` e `/get`)

- **O que fazer:** fazer o Worker gravar e ler usando SQL.
- **Como:** no editor do Worker (**Edit code**), apague o conteúdo e cole o **primeiro bloco** da
  seção [Código do Worker](#código-do-worker). Clique **Deploy**.
- **Entenda o que colou:** o `/insert` roda um `INSERT INTO` com os valores vindos do JSON; o
  `/get` roda um `SELECT ... ORDER BY timestamp DESC LIMIT 1` (o "último valor").
- **Confira:** abra `SUA-URL/get?sensor=temp` no navegador — deve dizer "Nenhum valor encontrado" (404), porque ainda não gravamos nada. Está certo!

### Passo 6 — Testar gravando e lendo (PowerShell)

- **O que fazer:** gravar algumas leituras à mão e conferir.
- **Como:** rode os comandos da seção [Testando pelo PowerShell](#testando-pelo-powershell). Grave 3 ou 4 valores diferentes de `temp`.
- **Confira:** `GET /get?sensor=temp` deve devolver o último valor que você gravou. **Tire um print.**

### Passo 7 — ESP32 enviando temperatura E umidade

- **O que fazer:** o sensor real alimenta o banco.
- **Como:** ligue o DHT11 (`VCC→3V3`, `GND→GND`, `DATA→GPIO 4`), instale a biblioteca **"DHT sensor library"** (Adafruit) e envie o código da seção [Código do ESP32](#código-do-esp32). Ele lê o DHT11, envia `temp` **e** `umid`, e entra em **deep sleep** por 30 s.
- **Por quê:** enviar dois sensores é o que dá sentido ao `GROUP BY` mais adiante; o deep sleep é a economia de energia da aula anterior.
- **Confira:** no Serial Monitor você vê os dois envios e o "Dormindo…". No `SUA-URL/get?sensor=umid` deve aparecer a umidade.

### Passo 8 — Consultas de análise (`/list` e `/media`)

- **O que fazer:** responder perguntas sobre os dados.
- **Como:** troque o Worker pelo **segundo bloco** da seção [Código do Worker](#código-do-worker) e faça **Deploy**.
- **Confira:** `SUA-URL/media?sensor=temp` deve devolver a **média, a mínima, a máxima e a contagem** da temperatura. **Tire um print.**

### Passo 9 — `GROUP BY` com `/resumo`

- **O que fazer:** um resumo de **todos** os sensores numa consulta só.
- **Como:** o mesmo segundo bloco já tem o `/resumo` (usa `GROUP BY sensor`).
- **Confira:** `SUA-URL/resumo` deve devolver **uma linha para `temp` e outra para `umid`**, cada uma com média, máximo e contagem. **Tire um print.**

### Passo 10 — Documentar e entregar

- Preencha o **`ENTREGA.md`** com suas respostas, as consultas SQL que usou e os prints.
- Faça o último commit (`git add . && git commit -m "Entrega final" && git push`) e abra um
  **Pull Request** (na página do seu fork: **Contribute → Open pull request**) com o **seu nome** no título.

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
e umidade). Credenciais no `config.h` (não versionar):

```cpp
// config.h  — NÃO versionar (está no .gitignore)
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

Ao terminar o **Passo 10**: `ENTREGA.md` preenchido (respostas + consultas SQL + prints), tudo
commitado, e **Pull Request** aberto com o seu nome no título. **Prazo:** a combinar com o professor.

## Critérios de avaliação

| Critério | Peso |
|---|---|
| Sistema funcionando: ESP32 → D1 → consultas respondendo | 35% |
| Modelagem e SQL corretos (tabela, `INSERT`, `SELECT`, `WHERE`) | 20% |
| Consultas de análise (`AVG`/`COUNT`/`MIN`/`MAX`) e `GROUP BY` no `/resumo` | 20% |
| Uso do Git: commits por passo, com histórico claro | 15% |
| `ENTREGA.md`: respostas e prints | 10% |

## Perguntas para responder no `ENTREGA.md`

1. Qual a diferença entre o **KV** (chave-valor) e um **banco relacional** como o D1? Quando cada um é melhor?
2. O que é o **D1** e o que é o **binding `DB`**?
3. Explique a tabela `leituras`: o que é cada **coluna** e seu **tipo**. Para que serve a **chave primária**?
4. Escreva a consulta SQL da **média da temperatura**. E a que **conta** quantas leituras de temperatura passaram de 30.
5. Para que serve o **`GROUP BY`** no `/resumo`? O que ele devolve?
6. Por que usamos `?` + `.bind(...)` em vez de colar o valor no texto do SQL?
7. O código do **ESP32** mudou muito ao trocar o KV pelo D1? O que isso ensina sobre a arquitetura?

Bom trabalho! 🚀
