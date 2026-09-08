Atividade IoT — Sensor físico na nuvem com KV + Cloudflare Workers
Disciplina: Internet das Coisas (IoT) · Turma AMF 2026-02 Plataforma: ESP32 (Arduino/PlatformIO) + Cloudflare Workers + Cloudflare KV

Nesta atividade você vai construir, do zero, um sistema em que um ESP32 lê um sensor físico, envia a leitura para um banco de dados na nuvem e economiza energia dormindo entre os envios — como faria um sensor de verdade alimentado por bateria. Você vai desenvolver por etapas, versionando cada passo no GitHub (commits), e no final entregar a atividade pronta e funcionando.

Leia este documento inteiro antes de começar: ele é a explicação e o enunciado.


1. O que você vai construir
Um sistema completo de IoT com duas partes de hardware e duas na nuvem:

flowchart LR

    A[Nó sensor<br/>ESP32 + DHT11<br/>lê, envia e dorme] -->|Wi-Fi · HTTPS · POST /insert| B[Cloudflare Worker<br/>API serverless]

    B -->|put / get / list| C[(Cloudflare KV<br/>banco chave-valor)]

    B -->|HTTPS · GET /get| E[Nó atuador<br/>ESP32 + LED<br/>lê e reage]

    D[PowerShell / navegador] -->|GET /get, /list| B

Nó sensor (ESP32 + sensor físico) — lê a temperatura de um sensor real (DHT11), conecta no Wi-Fi, envia o valor para a nuvem e entra em deep sleep para gastar quase nada de energia até a próxima leitura. É o comportamento típico de um sensor a bateria.
Cloudflare Worker — programa em JavaScript que roda na nuvem e é a porta de entrada (a "API"). Recebe os dados e guarda no banco; devolve quando alguém pede.
Cloudflare KV — banco de dados chave-valor que guarda cada leitura. É onde os dados ficam salvos de verdade, sobrevivendo a reinícios do ESP32.
Nó atuador (ESP32 + LED) — fica ligado, lê o último valor da nuvem e age (acende um LED quando a temperatura passa de um limite).

No final, você terá uma URL pública (algo como https://sua-api.SEU-USUARIO.workers.dev) alimentada por um sensor real que dorme entre as medições.


2. Material necessário
2× ESP32 DevKit (um para o nó sensor, um para o nó atuador) + cabos USB. Dá para fazer com 1 só, alternando os códigos, mas com 2 você vê os dois nós funcionando juntos.
1× sensor de temperatura DHT11 (o DHT22 ou um LM35 também servem — ajuste o código).
1× LED + resistor de 220 Ω (para o nó atuador). Muitas placas já têm um LED embutido no GPIO 2.
Protoboard e jumpers.
(Opcional, mas recomendado para a parte de energia) uma bateria ou power bank, para testar o nó sensor sem o cabo do computador.


3. Como funciona
São leituras de sensor, uma conexão Wi-Fi e mensagens HTTP indo e voltando.
3.1 A conexão Wi-Fi
O ESP32 tem Wi-Fi embutido. Nesta atividade ele funciona em modo estação (STA): conecta a um roteador usando o nome da rede (SSID) e a senha, exatamente como o seu celular.

O ESP32 clássico só enxerga redes 2,4 GHz (não conecta em Wi-Fi de 5 GHz).
Ele precisa estar conectado antes de tentar qualquer requisição HTTP — por isso o código espera o WiFi.status() == WL_CONNECTED.
Sem Wi-Fi, não há nuvem: a conexão é o que liga o dispositivo ao Worker.
3.2 A energia — por que o sensor "dorme"
Um sensor de verdade costuma ficar longe da tomada, funcionando com bateria. Se ele ficasse ligado o tempo todo com o Wi-Fi ativo (consumo de ~80 a 160 mA), a bateria duraria pouco. A solução é o Deep Sleep:

o ESP32 acorda, liga o Wi-Fi, mede o sensor e envia para a nuvem;
depois dorme (deep sleep), desligando CPU e Wi-Fi — o consumo cai para a casa dos microamperes;
um temporizador o acorda de novo depois de um tempo, e o ciclo recomeça.

Como no deep sleep o ESP32 reinicia ao acordar (roda o setup() de novo), todo o trabalho fica no setup(). Uma variável marcada com RTC_DATA_ATTR sobrevive ao sono e serve, por exemplo, para contar quantos envios já foram feitos.

A troca é clara: você economiza muita energia, mas os dados só chegam a cada intervalo (ex.: a cada 30 s), não continuamente.
3.3 O que é o Cloudflare Workers
Um jeito de rodar código sem ter um servidor. Você escreve uma função em JavaScript, faz o deploy, e a Cloudflare te dá uma URL. Toda vez que alguém acessa essa URL, a função roda e responde — e ainda roda perto de quem acessa (na "borda"), o que deixa rápido.
3.4 O que é o KV (Key-Value / chave-valor)
Um banco de dados bem simples: cada dado é guardado por uma chave única (um texto) e recuperado por essa mesma chave. Sem tabelas, sem SQL — só chave → valor.

Chave (key)
Valor (value)
sensor:temp:last
{ "valor": 27.8, "timestamp": ... }
sensor:temp:1699999999
{ "valor": 27.8, "timestamp": ... }


Operações: put grava, get lê, list({ prefix }) lista as chaves de um prefixo (o histórico).

⚠️ O KV tem consistência eventual: logo após gravar, a leitura pode levar alguns segundos para refletir o novo valor. É normal.
3.5 O que é HTTP (as mensagens)
ESP32, navegador e PowerShell falam com o Worker por HTTP (na versão segura, HTTPS). Cada conversa é uma requisição e uma resposta.

Uma requisição tem método (GET = ler, POST = enviar/gravar), URL (com caminho, ex.: /insert, e às vezes parâmetros, ex.: ?sensor=temp) e, às vezes, um corpo em JSON (ex.: { "sensor": "temp", "valor": 27.8 }). A resposta traz um status (200 ok, 400 pedido errado, 404 não achou, 500 erro no servidor) e um corpo.
3.6 Os três endpoints (as "portas" da API)
Caminho
Método
Para quê
/insert
POST
O nó sensor grava uma leitura (JSON no corpo).
/get
GET
Qualquer um lê o último valor de um sensor.
/list
GET
Qualquer um lê o histórico de um sensor.

3.7 O caminho completo (passo a passo)
O nó sensor acorda e conecta no Wi-Fi.
Ele lê o DHT11 e monta POST /insert com { "sensor":"temp", "valor":27.8 }.
O Worker recebe, lê o JSON e chama KV.put("sensor:temp:last", ...) — salvo.
O nó sensor entra em deep sleep por alguns segundos.
O nó atuador faz GET /get?sensor=temp; o Worker chama KV.get(...) e devolve o JSON.
O nó atuador interpreta o JSON e acende o LED se a temperatura passou do limite.


4. A atividade — desenvolva por etapas
Faça uma etapa de cada vez e dê um commit ao final de cada uma (veja a seção 8). Parte da avaliação é ver a atividade evoluindo no histórico do GitHub, não pronta de uma vez.

Etapa 0 — Preparação. Crie uma conta no Cloudflare.
Etapa 1 — Criar o Worker e o KV. No painel: Workers & Pages → Create → Worker, dê um nome e faça Deploy. Crie o banco em Storage & Databases → KV → Create namespace e ligue-o ao Worker em Settings → Bindings com o nome KV_SENSOR. Anote sua URL.
Etapa 2 — Implementar /insert e /get. Cole no editor do Worker o código da seção 5 (primeiro bloco) e faça Deploy.
Etapa 3 — Testar pelo PowerShell. Grave e leia um valor com os comandos da seção 6. Tire um print.
Etapa 4 — Montar o sensor físico. Ligue o DHT11 ao ESP32 (seção 7) e leia a temperatura no Serial Monitor, ainda sem nuvem. Confirme que o valor faz sentido.
Etapa 5 — Enviar a leitura real (Wi-Fi + POST). Faça o nó sensor conectar no Wi-Fi e enviar a temperatura do DHT11 com POST /insert. Confira no /get.
Etapa 6 — Economia de energia (Deep Sleep). Faça o nó sensor dormir entre os envios (acorda, mede, envia, dorme). Use RTC_DATA_ATTR para contar os envios. Teste, se der, alimentando por bateria/power bank.
Etapa 7 — Nó atuador. Em outro ESP32 (ou no mesmo), leia GET /get, interprete o JSON e acenda o LED quando a temperatura passar do limite.
Etapa 8 — Histórico com /list. Adicione a gravação no histórico e o endpoint /list (seção 5, segundo bloco). Liste e confira os timestamps.
Etapa 9 — Documentar e entregar. Preencha o ENTREGA.md com respostas e prints e abra o Pull Request (seção 8).


5. Código do Worker (referência)
Comece pelo primeiro bloco (etapa 2). Na etapa 8 troque pelo segundo bloco, que adiciona o histórico e o /list.
5.1 Versão 1 — /insert e /get
export default {

  async fetch(request, env) {

    const url = new URL(request.url);

    // Gravar uma leitura

    if (url.pathname === "/insert" && request.method === "POST") {

      const body = await request.json();          // { sensor, valor }

      if (!env.KV_SENSOR)

        return new Response("Binding KV_SENSOR nao encontrado!", { status: 500 });

      const nome  = body.sensor || "temp";

      const valor = body.valor  ?? "0";

      await env.KV_SENSOR.put(`sensor:${nome}:last`, JSON.stringify({

        valor: valor,

        timestamp: Date.now()

      }));

      return new Response(`OK: ${nome}=${valor}`);

    }

    // Ler o último valor

    if (url.pathname === "/get") {

      const nome = url.searchParams.get("sensor");

      if (!nome) return new Response("Informe ?sensor=temp", { status: 400 });

      const data = await env.KV_SENSOR.get(`sensor:${nome}:last`, { type: "json" });

      if (!data) return new Response("Nenhum valor encontrado", { status: 404 });

      return new Response(JSON.stringify(data, null, 2), {

        headers: { "Content-Type": "application/json" }

      });

    }

    return new Response("Use POST /insert ou GET /get?sensor=nome");

  }

}
5.2 Versão 2 — adiciona histórico e /list
export default {

  async fetch(request, env) {

    const url = new URL(request.url);

    if (url.pathname === "/insert" && request.method === "POST") {

      const body = await request.json();

      if (!env.KV_SENSOR)

        return new Response("Binding KV_SENSOR nao encontrado!", { status: 500 });

      const nome  = body.sensor || "temp";

      const valor = body.valor  ?? "0";

      const timestamp = Date.now();

      await env.KV_SENSOR.put(`sensor:${nome}:last`,

        JSON.stringify({ valor, timestamp }));            // último valor

      await env.KV_SENSOR.put(`sensor:${nome}:${timestamp}`,

        JSON.stringify({ valor, timestamp }));            // histórico

      return new Response(`OK: ${nome}=${valor}`);

    }

    if (url.pathname === "/get") {

      const nome = url.searchParams.get("sensor");

      if (!nome) return new Response("Informe ?sensor=temp", { status: 400 });

      const data = await env.KV_SENSOR.get(`sensor:${nome}:last`, { type: "json" });

      if (!data) return new Response("Nenhum valor encontrado", { status: 404 });

      return new Response(JSON.stringify(data, null, 2), {

        headers: { "Content-Type": "application/json" }

      });

    }

    if (url.pathname === "/list") {

      const nome = url.searchParams.get("sensor");

      if (!nome) return new Response("Informe ?sensor=temp", { status: 400 });

      const { keys } = await env.KV_SENSOR.list({ prefix: `sensor:${nome}:` });

      let historico = [];

      for (let k of keys) {

        if (k.name.endsWith(":last")) continue;   // pula o "last"

        const val = await env.KV_SENSOR.get(k.name, { type: "json" });

        if (val) historico.push(val);

      }

      return new Response(JSON.stringify(historico, null, 2), {

        headers: { "Content-Type": "application/json" }

      });

    }

    return new Response("Use POST /insert, GET /get?sensor=nome ou GET /list?sensor=nome");

  }

}


6. Testando pelo PowerShell (Windows)
Troque a URL pela do seu Worker.

# Gravar um valor

Invoke-RestMethod `

  -Uri "https://sua-api.SEU-USUARIO.workers.dev/insert" `

  -Method POST `

  -Body (@{ sensor="temp"; valor=27.8 } | ConvertTo-Json) `

  -ContentType "application/json"

# Ler o último valor

Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/get?sensor=temp"

# Ler o histórico

Invoke-RestMethod -Uri "https://sua-api.SEU-USUARIO.workers.dev/list?sensor=temp"


7. Código do ESP32 (referência)
Instale a biblioteca do sensor (Arduino IDE → Gerenciar Bibliotecas → "DHT sensor library" da Adafruit + "Adafruit Unified Sensor"). Coloque as credenciais em um config.h ao lado do .ino (não suba esse arquivo):

// config.h  — NÃO versionar (está no .gitignore)

#define WIFI_SSID   "SEU_WIFI"      // rede 2,4 GHz

#define WIFI_PASS   "SUA_SENHA"

#define WORKER_URL  "https://sua-api.SEU-USUARIO.workers.dev"
7.1 Ligação do sensor DHT11
DHT11
ESP32
VCC
3V3
GND
GND
DATA
GPIO 4


(Módulos de 3 pinos já têm o resistor de pull-up. Em sensores de 4 pinos, ligue um resistor de 10 kΩ entre DATA e 3V3.)
7.2 Nó sensor — ler o DHT11, enviar e dormir (Wi-Fi + POST + Deep Sleep)
#include <WiFi.h>

#include <HTTPClient.h>

#include <DHT.h>

#include "config.h"

#define DHTPIN  4

#define DHTTYPE DHT11

DHT dht(DHTPIN, DHTTYPE);

RTC_DATA_ATTR int envios = 0;          // sobrevive ao deep sleep

void setup() {

  Serial.begin(115200);

  dht.begin();

  // 1) Conecta no Wi-Fi

  WiFi.begin(WIFI_SSID, WIFI_PASS);

  Serial.print("Conectando ao WiFi");

  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }

  Serial.println(" ok");

  // 2) Le o sensor fisico

  float temp = dht.readTemperature();          // graus Celsius

  if (isnan(temp)) {

    Serial.println("Falha ao ler o DHT11!");

  } else {

    // 3) Envia para a nuvem

    HTTPClient http;

    http.begin(String(WORKER_URL) + "/insert");

    http.addHeader("Content-Type", "application/json");

    String corpo = "{\"sensor\":\"temp\",\"valor\":" + String(temp, 1) + "}";

    int code = http.POST(corpo);

    envios++;

    Serial.printf("Envio #%d -> HTTP %d | temp=%.1f C\n", envios, code, temp);

    http.end();                                // libera memoria

  }

  // 4) Dorme para economizar energia

  const uint64_t DORME_SEG = 30;

  Serial.printf("Dormindo por %llu s...\n", DORME_SEG);

  Serial.flush();

  esp_sleep_enable_timer_wakeup(DORME_SEG * 1000000ULL);

  esp_deep_sleep_start();                       // ao acordar, reinicia no setup()

}

void loop() { }   // nunca executa: o trabalho todo esta no setup()
7.3 Nó atuador — ler da nuvem e acender o LED (fica ligado)
#include <WiFi.h>

#include <HTTPClient.h>

#include <ArduinoJson.h>

#include "config.h"

#define LED    2          // LED embutido de muitas placas ESP32

#define LIMITE 30.0       // acende acima disso

void setup() {

  Serial.begin(115200);

  pinMode(LED, OUTPUT);

  WiFi.begin(WIFI_SSID, WIFI_PASS);

  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }

  Serial.println(" WiFi ok");

}

void loop() {

  if (WiFi.status() == WL_CONNECTED) {

    HTTPClient http;

    http.begin(String(WORKER_URL) + "/get?sensor=temp");

    int code = http.GET();

    if (code == 200) {

      String payload = http.getString();

      StaticJsonDocument<200> doc;

      deserializeJson(doc, payload);

      float valor = doc["valor"];

      Serial.printf("temp = %.1f C\n", valor);

      digitalWrite(LED, valor > LIMITE ? HIGH : LOW);   // reage ao valor

    }

    http.end();

  }

  delay(10000);   // consulta a cada 10 s (este no fica ligado, por isso nao dorme)

}

Por que o atuador não dorme? Porque ele precisa estar sempre pronto para reagir — por isso costuma ficar ligado na tomada. Quem economiza energia é o nó sensor, que só acorda para medir e enviar.


8. Como entregar (Git + Pull Request)
Você entrega fazendo commits ao longo do trabalho. Depois de fazer o fork e clonar o seu repositório, ao final de cada etapa rode:

git add .

git commit -m "Etapa 6: nó sensor com deep sleep"

git push

Ao terminar a Etapa 9: preencha o ENTREGA.md (respostas + prints do Serial Monitor e do PowerShell), faça o último commit e abra um Pull Request (na página do seu fork: Contribute → Open pull request) com o seu nome no título.

Prazo: a combinar com o professor.


9. Perguntas para responder no ENTREGA.md
Com suas palavras, o que é o Cloudflare Workers e o que é o KV?
Explique o caminho de um dado desde o sensor físico até ficar salvo no KV.
O que o Deep Sleep desliga no ESP32 e por que isso economiza energia? O que muda no consumo?
Por que a variável de contagem usa RTC_DATA_ATTR? O que aconteceria sem isso?
Por que o nó sensor dorme, mas o nó atuador fica ligado?
Por que o ESP32 precisa conectar no Wi-Fi antes de enviar a leitura?
Qual a diferença entre a chave sensor:temp:last e as chaves sensor:temp:<timestamp>?
Por que a senha do Wi-Fi não pode ser enviada ao GitHub?

Bom trabalho! 🚀

