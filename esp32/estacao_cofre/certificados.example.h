// ================================================================
//  NAO preencha a mao: rode  scripts\gerar_certificados.ps1
//  e ele cria o "certificados.h" aqui nesta pasta.
//
//  Estes sao certificados PUBLICOS das autoridades certificadoras
//  (CAs). Nao sao segredo - pode versionar no GitHub sem medo.
// ================================================================

// Raiz (e intermediarios) da cadeia do SEU Worker (*.workers.dev)
const char* CA_WORKER = R"CERT(
-----BEGIN CERTIFICATE-----
(cole aqui, ou rode o script)
-----END CERTIFICATE-----
)CERT";

// CA do broker test.mosquitto.org (portas 8883/8885)
// Fonte: https://test.mosquitto.org/ssl/mosquitto.org.crt
const char* CA_MOSQUITTO = R"CERT(
-----BEGIN CERTIFICATE-----
(cole aqui, ou rode o script)
-----END CERTIFICATE-----
)CERT";
