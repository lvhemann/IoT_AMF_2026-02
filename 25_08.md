# IoT_AMF_2025-02

## Monitor de Memória e Stack

```bash  
  #include <Arduino.h>

void printMemoryInfo() {
  // Heap (memória livre global)
  size_t freeHeap = ESP.getFreeHeap();          // bytes livres no heap
  size_t minHeap  = ESP.getMinFreeHeap();       // menor valor de heap já disponível
  size_t maxAlloc = ESP.getMaxAllocHeap();      // maior bloco único alocável

  // Stack (da task atual)
  size_t freeStack = uxTaskGetStackHighWaterMark(NULL); // em palavras de 4 bytes
  freeStack *= sizeof(StackType_t);                     // converte para bytes

  Serial.println("=== Memória ESP32 ===");
  Serial.printf("Heap livre atual: %u bytes\n", freeHeap);
  Serial.printf("Heap mínimo já visto: %u bytes\n", minHeap);
  Serial.printf("Maior bloco contíguo disponível: %u bytes\n", maxAlloc);
  Serial.printf("Stack livre da task atual: %u bytes\n", freeStack);
  Serial.println("======================\n");
}

void setup() {
  Serial.begin(115200);
  delay(1000);
}

void loop() {
  printMemoryInfo();
  delay(2000); // imprime a cada 2 segundos
}

```

## Blink com Monitor de Memória e Stack
```bash
#ifndef APP_BLINK_H
#define APP_BLINK_H

#include <Arduino.h>

// Função simples para piscar um pino
inline void blink(uint8_t pin, uint32_t timeMs) {
  pinMode(pin, OUTPUT);
  digitalWrite(pin, HIGH);
  delay(timeMs);
  digitalWrite(pin, LOW);
  delay(timeMs);
}

#endif // APP_BLINK_H
```
# CPP
```bash
#include <Arduino.h>
#include "app_blink.h"

// --- Monitor de memória ---
void printMemoryInfo() {
  size_t freeHeap = ESP.getFreeHeap();
  size_t minHeap  = ESP.getMinFreeHeap();
  size_t maxAlloc = ESP.getMaxAllocHeap();

  size_t freeStack = uxTaskGetStackHighWaterMark(NULL);
  freeStack *= sizeof(StackType_t);

  Serial.println("=== Memória ESP32 ===");
  Serial.printf("Heap livre atual: %u bytes\n", (unsigned)freeHeap);
  Serial.printf("Heap mínimo já visto: %u bytes\n", (unsigned)minHeap);
  Serial.printf("Maior bloco contíguo disponível: %u bytes\n", (unsigned)maxAlloc);
  Serial.printf("Stack livre da task atual: %u bytes\n", (unsigned)freeStack);
  Serial.println("======================\n");
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n[Init] Blink + Monitor de Memória");
}

void loop() {
  blink(LED_BUILTIN, 500); // pisca com 500 ms HIGH e 500 ms LOW
  printMemoryInfo();       // imprime após cada ciclo
}


```


## Estouro de Memória
```bash
#include <Arduino.h>

/*
  ESP32 — Demonstração de Stack Overflow progressivo

  Ideia:
    - Uma task é criada com stack relativamente pequena.
    - A cada "passo", chamamos uma função recursiva com profundidade crescente.
    - Cada chamada usa um buffer local (FRAME_SIZE) para consumir stack.
    - Assim, a stack vai sendo "comida" com o tempo até estourar (<= 2 min).

  Ajustes:
    - STACK_WORDS: tamanho da stack da task em PALAVRAS (1 palavra = 4 bytes).
    - FRAME_SIZE:  bytes consumidos por frame de recursão (stack por chamada).
    - STEP_DELAY_MS: atraso entre passos (quanto menor, mais rápido estoura).
*/

static const uint16_t STACK_WORDS   = 768;   // 768 * 4 = ~3 KB para a task
static const uint16_t FRAME_SIZE    = 256;   // bytes por nível de recursão
static const uint16_t STEP_DELAY_MS = 150;   // atraso entre passos (<= 2 min total)

// ========== Monitor de heap/stack da task atual ==========
static void printMemoryInfo(const char* tag = "") {
  size_t freeHeap  = ESP.getFreeHeap();
  size_t minHeap   = ESP.getMinFreeHeap();
  size_t maxAlloc  = ESP.getMaxAllocHeap();
  size_t freeStack = uxTaskGetStackHighWaterMark(NULL) * sizeof(StackType_t);

  Serial.println("=== Memória ESP32 ===");
  if (tag && *tag) Serial.printf("[%s]\n", tag);
  Serial.printf("Heap livre atual: %u bytes\n", (unsigned)freeHeap);
  Serial.printf("Heap mínimo já visto: %u bytes\n", (unsigned)minHeap);
  Serial.printf("Maior bloco contíguo disponível: %u bytes\n", (unsigned)maxAlloc);
  Serial.printf("Stack livre (high-water): %u bytes\n", (unsigned)freeStack);
  Serial.println("======================\n");
}

// ========== Função recursiva que consome stack ==========
__attribute__((noinline)) static void eatStack(uint32_t depth) {
  // usa FRAME_SIZE bytes na stack desta chamada
  volatile uint8_t trash[FRAME_SIZE];
  for (uint16_t i = 0; i < FRAME_SIZE; ++i) trash[i] = (uint8_t)i;

  if (depth) eatStack(depth - 1);

  // impede otimizações/tail-call
  asm volatile("" ::: "memory");
}

// ========== Task que vai aumentar o consumo ao longo do tempo ==========
static void SlowOverflowTask(void* pv) {
  (void)pv;
  Serial.println("[SlowOverflowTask] Iniciada.");
  printMemoryInfo("inicio");

  uint32_t depth = 1; // começa leve e vai aumentando

  // Loop: a cada passo, aumenta 1 nível de recursão
  // e espera um pouquinho (STEP_DELAY_MS).
  for (;;) {
    Serial.printf("[SlowOverflowTask] depth=%u\n", (unsigned)depth);
    // Antes de atacar, mostra quanto de stack ainda sobrou
    size_t freeStack = uxTaskGetStackHighWaterMark(NULL) * sizeof(StackType_t);
    Serial.printf("  stack livre ~%u bytes\n", (unsigned)freeStack);

    // Tenta consumir stack proporcional à profundidade
    // Cada nível usa ~FRAME_SIZE bytes.
    eatStack(depth);

    // Se não estourou, incrementa e tenta de novo
    depth++;

    // Ritmo do teste (ajuste para caber no seu alvo de tempo)
    delay(STEP_DELAY_MS);
  }
}

// ========== Hook do FreeRTOS em caso de stack overflow ==========
extern "C" void vApplicationStackOverflowHook(TaskHandle_t xTask, char* pcTaskName) {
  (void)xTask;
  Serial.println("\n[HOOK] *** STACK OVERFLOW DETECTADO ***");
  if (pcTaskName) Serial.printf("[HOOK] Task: %s\n", pcTaskName);
  Serial.flush();
  delay(200);
  // Reinicia o chip para recuperar
  esp_restart();
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(10); }
  delay(300);
  Serial.println("\n[Init] Demo: stack overflow progressivo (<= 2 min)");

  // Cria a task com uma stack deliberadamente pequena
  BaseType_t ok = xTaskCreatePinnedToCore(
    SlowOverflowTask,          // função
    "SlowBoom",                // nome
    STACK_WORDS,               // stack em PALAVRAS (4 bytes cada)
    nullptr,                   // parâmetros
    tskIDLE_PRIORITY + 1,      // prioridade
    nullptr,                   // handle
    APP_CPU_NUM                // core (geralmente 1 para Arduino)
  );

  if (ok != pdPASS) {
    Serial.println("[Init] ERRO: não foi possível criar a task.");
  }
}

void loop() {
  // opcional: mostrar memória da loopTask periodicamente
  static uint32_t last = 0;
  if (millis() - last > 2000) {
    last = millis();
    printMemoryInfo("loop");
  }
  delay(1);
}



```

## Função Deep Sleep
```bash

#include <Arduino.h>

// Variável que sobrevive ao deep sleep (fica na RTC Memory)
RTC_DATA_ATTR int bootCount = 0;

// Função para imprimir motivo do último wakeup
void printWakeupReason() {
  esp_sleep_wakeup_cause_t reason = esp_sleep_get_wakeup_cause();

  switch (reason) {
    case ESP_SLEEP_WAKEUP_EXT0: Serial.println("Acordou por sinal externo usando RTC_IO"); break;
    case ESP_SLEEP_WAKEUP_EXT1: Serial.println("Acordou por sinal externo usando RTC_CNTL"); break;
    case ESP_SLEEP_WAKEUP_TIMER: Serial.println("Acordou por temporizador"); break;
    case ESP_SLEEP_WAKEUP_TOUCHPAD: Serial.println("Acordou por touchpad"); break;
    case ESP_SLEEP_WAKEUP_ULP: Serial.println("Acordou por ULP"); break;
    default: Serial.printf("Motivo de wakeup não identificado: %d\n", reason); break;
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000); // espera Serial abrir

  bootCount++;
  Serial.printf("Boot número: %d\n", bootCount);
  printWakeupReason();

  // Configura o tempo de deep sleep (em microssegundos)
  const uint64_t sleepTimeSec = 10;
  Serial.printf("Entrando em deep sleep por %llu segundos...\n", sleepTimeSec);

  esp_sleep_enable_timer_wakeup(sleepTimeSec * 1000000ULL);

  // Dá tempo de ver a mensagem no Serial antes de dormir
  delay(2000);

  Serial.println("Indo dormir agora...");
  Serial.flush();
  esp_deep_sleep_start();
}

void loop() {
  // Não será executado — ESP32 reinicia ao acordar do deep sleep
}

```


# Leitura BLE

## src - Controla tudo

```bash

#include <Arduino.h>
#include "app_ble.h"

static uint32_t lastScan = 0;
static const uint32_t SCAN_PERIOD_MS = 15000; // roda um scan a cada 15s

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(10); }
  delay(300);

  Serial.println("\n[Init] BLE RAW Scanner (demo estourar vs limitar)");
  initBLEScan(); // inicializa BLE e callbacks
}

void loop() {
  // dispara um scan periódico bloqueante (termina sozinho por duração ou por limite/heap)
  if (millis() - lastScan > SCAN_PERIOD_MS) {
    lastScan = millis();
    Serial.println("\n🔄 Iniciando varredura BLE...");
    updateStoredDevices(); // coleta tudo ao redor (ou até bater o limite/heap)
    // imprime um resumo e o RAW em hex
    Serial.printf("📊 Dispositivos únicos: %d\n", storedPackets.size());
    Serial.println("RAW (HEX) separados por ';':");
    Serial.println(getRawPacketsAsHexString());
  }

  // telemetria simples de heap
  static uint32_t lastInfo = 0;
  if (millis() - lastInfo > 2000) {
    lastInfo = millis();
    size_t freeHeap   = ESP.getFreeHeap();
    size_t minFree    = ESP.getMinFreeHeap();
    size_t maxAlloc   = ESP.getMaxAllocHeap();
    Serial.println("=== Memória ===");
    Serial.printf("Heap livre: %u | Min. já visto: %u | Maior bloco: %u\n",
                  (unsigned)freeHeap, (unsigned)minFree, (unsigned)maxAlloc);
  }

  delay(1);
}


```
## app_ble.h  Controla o BLE

```bash
#ifndef APP_BLE_H
#define APP_BLE_H

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEScan.h>
#include <BLEAdvertisedDevice.h>
#include <vector>
#include <set>
#include <string>

// Confg

// 0 = SEM LIMITE (didático: pode exaurir heap)
// 1 = COM LIMITE (recomendado)
#define BLE_LIMIT_DEVICES 0

// Limite de dispositivos quando BLE_LIMIT_DEVICES = 1
#ifndef MAX_DEVICES
#define MAX_DEVICES 200
#endif

// Duração padrão de um scan (segundos)
static int SCAN_DURATION = 20;

// Se BLE_LIMIT_DEVICES=1, para o scan ao passar desse uso de heap
static const float HEAP_STOP_PERCENT = 80.0f;

// INTERNOS 
static BLEScan *pBLEScan = nullptr;

struct RawPacket {
  std::vector<uint8_t> data;
  std::string mac;
  int rssi;
  RawPacket(const uint8_t* payload, int length, const std::string& macAddr, int rssiVal)
  : mac(macAddr), rssi(rssiVal) {
    data.assign(payload, payload + length);
  }
};

static std::vector<RawPacket> storedPackets;
static std::set<std::string>  seenMacs;

// --------- util: converte vetor de bytes para HEX string (sem espaços) ---------
static String bytesToHex(const std::vector<uint8_t>& v) {
  String s;
  s.reserve(v.size() * 2);
  for (auto b : v) {
    if (b < 0x10) s += '0';
    s += String(b, HEX);
  }
  return s;
}

//  CALLBACK PRINCIPAL 
class AllDevicesCallback : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice dev) override {
    // captura TUDO (sem filtro por nome), evitando duplicar por MAC
    std::string mac = std::string(dev.getAddress().toString().c_str());
    if (seenMacs.count(mac)) {
      return;
    }

    const uint8_t* payload = dev.getPayload();
    int length = dev.getPayloadLength();

    if (payload && length > 0) {
#if BLE_LIMIT_DEVICES
      // ---- MODO SEGURO: IF que limita ----
      if ((int)storedPackets.size() >= MAX_DEVICES) {
        Serial.printf("🛑 Limite MAX_DEVICES=%d atingido. Parando scan.\n", MAX_DEVICES);
        if (pBLEScan) pBLEScan->stop();
        return;
      }
#endif
      storedPackets.emplace_back(payload, length, mac, dev.getRSSI());
      seenMacs.insert(mac);

      // log básico
      Serial.printf("📡 %s | %d bytes | RSSI=%d | RAW=",
                    mac.c_str(), length, dev.getRSSI());
      for (int i = 0; i < length; ++i) {
        if (payload[i] < 0x10) Serial.print('0');
        Serial.print(payload[i], HEX);
      }
      Serial.println();

#if BLE_LIMIT_DEVICES
      // Checagem de heap (parada preventiva)
      uint32_t totalHeap = ESP.getHeapSize();
      uint32_t freeHeap  = ESP.getFreeHeap();
      float usagePercent = 100.0f * (float)(totalHeap - freeHeap) / (float)totalHeap;
      if (usagePercent > HEAP_STOP_PERCENT && pBLEScan) {
        Serial.printf("🛑 Heap em %.2f%% (> %.1f%%). Parando scan.\n",
                      usagePercent, HEAP_STOP_PERCENT);
        pBLEScan->stop();
      }
#endif
    }
  }
};

static AllDevicesCallback g_cb;

//  API 

inline void initBLEScan() {
  BLEDevice::init("ESP32_RAW_SCANNER");
  pBLEScan = BLEDevice::getScan();
  pBLEScan->setAdvertisedDeviceCallbacks(&g_cb);
  pBLEScan->setActiveScan(true); // pega payload completo com resposta de scan

  // Parâmetros “rápidos” de varredura (aprox. 20 ms janela/intervalo)
  esp_ble_scan_params_t scanParams = {
      .scan_type          = BLE_SCAN_TYPE_ACTIVE,
      .own_addr_type      = BLE_ADDR_TYPE_PUBLIC,
      .scan_filter_policy = BLE_SCAN_FILTER_ALLOW_ALL,
      .scan_interval      = 0x4000, // ~20ms
      .scan_window        = 0x4000
  };
  esp_ble_gap_set_scan_params(&scanParams);

  // Potência alta para captar mais longe (ajuste se precisar)
  esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_DEFAULT, ESP_PWR_LVL_P9);
  esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_ADV,     ESP_PWR_LVL_P9);
  esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_SCAN,    ESP_PWR_LVL_P9);
}

// Limpa estruturas e faz um scan bloqueante
inline void updateStoredDevices() {
  if (!pBLEScan) return;

  seenMacs.clear();
  storedPackets.clear();

  Serial.printf("Heap antes do scan: %u bytes\n", (unsigned)ESP.getFreeHeap());
  pBLEScan->setAdvertisedDeviceCallbacks(&g_cb);
  // true = bloqueante; retorna quando terminar ou quando pBLEScan->stop() for chamado
  pBLEScan->start(SCAN_DURATION, true);

  Serial.printf("Heap depois do scan: %u bytes\n", (unsigned)ESP.getFreeHeap());
  Serial.printf("Total únicos: %u\n", (unsigned)storedPackets.size());

  // relatório de uso de heap
  uint32_t totalHeap = ESP.getHeapSize();
  uint32_t freeHeap  = ESP.getFreeHeap();
  uint32_t usedHeap  = totalHeap - freeHeap;
  float usagePercent = (usedHeap / (float)totalHeap) * 100.0f;

  Serial.println("=== Memória do ESP32 ===");
  Serial.printf("Total heap: %u\n", (unsigned)totalHeap);
  Serial.printf("Heap livre: %u\n", (unsigned)freeHeap);
  Serial.printf("Heap usada: %u\n", (unsigned)usedHeap);
  Serial.printf("Uso: %.2f%%\n", usagePercent);
  Serial.println("========================");

  pBLEScan->clearResults(); // limpa buffers internos do BLEScan
}

// Exporta os payloads capturados em HEX, separados por ';'
inline String getRawPacketsAsHexString() {
  String out;
  for (const auto& pkt : storedPackets) {
    out += bytesToHex(pkt.data);
    out += ';';
  }
  if (out.endsWith(";")) out.remove(out.length() - 1);
  return out;
}

#endif // APP_BLE_H



```


##ESP32 + DeepSleep + EEPROM
```bash

#include <Arduino.h>
#include <EEPROM.h>

#define EEPROM_SIZE 64       // tamanho mínimo para reservar EEPROM
#define COUNTER_ADDR 0       // posição onde vamos salvar o contador
#define SLEEP_TIME_US 10e6   // 10 segundos em microssegundos

int bootCounter = 0;

void setup() {
  Serial.begin(115200);
  delay(500);

  // Inicializa EEPROM
  if (!EEPROM.begin(EEPROM_SIZE)) {
    Serial.println("Falha ao iniciar EEPROM!");
    while (1);
  }

  // Lê contador salvo
  EEPROM.get(COUNTER_ADDR, bootCounter);

  // Incrementa e salva de volta
  bootCounter++;
  EEPROM.put(COUNTER_ADDR, bootCounter);
  EEPROM.commit();  // importante para gravar na flash

  Serial.printf("ESP32 acordou %d vezes do deep sleep\n", bootCounter);

  // Configura wakeup por timer
  esp_sleep_enable_timer_wakeup(SLEEP_TIME_US);

  Serial.println("Indo dormir por 10 segundos...");
  delay(1000);

  esp_deep_sleep_start();
}

void loop() {
  // nunca roda, pois depois do deep sleep o ESP32 reinicia no setup()
}


```







