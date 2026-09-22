// ================================================================
//  PONTO DE PARTIDA — publica TUDO em UM UNICO topico (JSON).
//  O trabalho da turma e' EVOLUIR isto (ver o README):
//   - dividir temp e umidade em DOIS topicos;
//   - acrescentar um topico do LED (ON/OFF);
//   - separar os logs (Wi-Fi e TLS) em topicos proprios;
//   - implementar Deep Sleep.
// ================================================================
#include <WiFi.h>
#include <PubSubClient.h>
#include <DHT.h>
#include <time.h>
#include "config.h"

// >>> TROQUE "leonam" por algo UNICO seu (nome/matricula) <<<
#define NOME "leonam"

#define DHTPIN 4
#define DHTTYPE DHT11
#define LED 2

DHT dht(DHTPIN, DHTTYPE);
WiFiClient wifi;
PubSubClient mqtt(wifi);

String TOPICO     = String("sis1a/") + NOME + "/dados";     // <<< UNICO topico (por enquanto)
String TOPICO_CMD = String("sis1a/") + NOME + "/comando";   // recebimento

float limite = 30.0;          // a REGRA: acende o LED acima disso
bool  ledOn  = false;
long  tempoConexao = 0;       // quanto tempo levou p/ conectar no Wi-Fi (ms)
unsigned long ultimo = 0;

String horaLocal() {
  struct tm t;
  if (!getLocalTime(&t)) return "sem-hora";
  char buf[25];
  strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &t);
  return String(buf);
}

// RECEBIMENTO: comando vindo do serviço (Python/HTML)
void aoReceber(char* topico, byte* payload, unsigned int len) {
  String msg;
  for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
  Serial.printf("RECEBIDO [%s]: %s\n", topico, msg.c_str());
  if (msg.startsWith("limite:")) {
    limite = msg.substring(7).toFloat();
    Serial.printf(" -> novo limite = %.1f\n", limite);
  } else if (msg.startsWith("led:")) {
    String e = msg.substring(4);
    digitalWrite(LED, (e == "ON" || e == "1") ? HIGH : LOW);
  }
}

void conectar() {
  while (!mqtt.connected()) {
    Serial.print("Conectando ao Mosquitto...");
    String id = String("esp32-") + NOME + "-" + String(random(9999));
    if (mqtt.connect(id.c_str())) {
      Serial.println(" ok");
      mqtt.subscribe(TOPICO_CMD.c_str());   // ouve o comando
    } else {
      Serial.printf(" falhou rc=%d (2s)\n", mqtt.state());
      delay(2000);
    }
  }
}

// ENVIO: monta UM JSON com tudo (temp, umid, led, log de Wi-Fi e de TLS)
void publicarTudo() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  ledOn = (!isnan(t) && t > limite);
  digitalWrite(LED, ledOn ? HIGH : LOW);

  bool relogioOk = (horaLocal() != "sem-hora");

  String json = "{";
  json += "\"temp\":" + String(t, 1) + ",";
  json += "\"umid\":" + String(h, 1) + ",";
  json += "\"led\":\"" + String(ledOn ? "ON" : "OFF") + "\",";
  // log de Wi-Fi
  json += "\"wifi\":{\"ssid\":\"" + WiFi.SSID() + "\",\"rssi\":" + String(WiFi.RSSI()) +
          ",\"ip\":\"" + WiFi.localIP().toString() + "\",\"ms\":" + String(tempoConexao) + "},";
  // log de TLS (hora + se o relogio esta sincronizado)
  json += "\"tls\":{\"hora\":\"" + horaLocal() + "\",\"relogio_ok\":" + (relogioOk ? "true" : "false") + "}";
  json += "}";

  mqtt.publish(TOPICO.c_str(), json.c_str());
  Serial.println(json);
}

void setup() {
  Serial.begin(115200);
  pinMode(LED, OUTPUT);
  dht.begin();

  unsigned long t0 = millis();
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Conectando ao WiFi");
  while (WiFi.status() != WL_CONNECTED) { delay(300); Serial.print("."); }
  tempoConexao = millis() - t0;
  Serial.printf("\n ok | IP=%s | RSSI=%d dBm | %ld ms\n",
                WiFi.localIP().toString().c_str(), WiFi.RSSI(), tempoConexao);

  configTime(-3 * 3600, 0, "pool.ntp.org", "time.nist.gov");  // hora local (UTC-3) p/ o log de TLS

  mqtt.setServer("test.mosquitto.org", 1883);   // broker publico Eclipse Mosquitto
  mqtt.setCallback(aoReceber);
  conectar();
}

void loop() {
  if (!mqtt.connected()) conectar();
  mqtt.loop();
  if (millis() - ultimo > 10000) {   // publica a cada 10 s
    ultimo = millis();
    publicarTudo();
  }
}
