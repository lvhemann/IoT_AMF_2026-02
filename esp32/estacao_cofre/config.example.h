// ================================================================
//  Copie este arquivo para "config.h" e preencha.
//  O config.h guarda SEGREDOS: ele NUNCA vai pro GitHub
//  (ja esta no .gitignore). Nunca imprima esses valores no Serial.
// ================================================================

// --- Wi-Fi (rede 2,4 GHz). No Wokwi: "Wokwi-GUEST" e senha "" ---
#define WIFI_SSID  "SEU_WIFI"
#define WIFI_PASS  "SUA_SENHA"

// --- Identidade: algo UNICO seu (nome/matricula), sem espaco ---
#define NOME       "leonam"

// --- Seu Worker (sem barra no final) ---
#define WORKER_URL "https://sua-api.SEU-USUARIO.workers.dev"

// --- Camada 2: API key (o MESMO valor do Secret API_KEY no Worker) ---
#define API_KEY    "troque-por-uma-chave-sua"

// --- Camada 3: chave da assinatura HMAC (o MESMO valor do Secret
//     CHAVE_HMAC no Worker e do campo "Chave HMAC" na pagina) ---
#define CHAVE_HMAC "troque-por-outra-chave-bem-longa"

// --- Camada 4: chave AES-128 do cofre = 32 caracteres hexadecimais
//     (0-9, a-f). Gere a sua com o script scripts\gerar_chaves.ps1 ---
#define CHAVE_AES_HEX "00112233445566778899aabbccddeeff"

// --- Broker MQTT com TLS + login (porta 8885 do test.mosquitto.org).
//     Esse login e' publico (e' um broker de teste) - num sistema real,
//     cada dispositivo teria o seu. ---
#define MQTT_HOST  "test.mosquitto.org"
#define MQTT_PORTA 8885
#define MQTT_USER  "rw"
#define MQTT_PASS  "readwrite"
