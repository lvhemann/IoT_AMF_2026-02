# Entrega — Trabalho MQTT (Mosquitto): tópicos, logs e Deep Sleep

**Aluno(s):**
**Turma:** AMF 2026-02
**Seu prefixo de tópico:** `sis1a/______/`
**Serviço usado:** ( ) Python  ( ) HTML

---

## Checklist do que foi feito

- [ ] Tarefa 1 — temperatura e umidade em **tópicos separados** (`.../temp`, `.../umid`)
- [ ] Tarefa 2 — **tópico do LED** (`.../led` = ON/OFF)
- [ ] Tarefa 3 — **logs** de Wi-Fi e TLS em tópicos próprios
- [ ] Tarefa 4 — **Deep Sleep** com contador de ciclos (`RTC_DATA_ATTR`)
- [ ] Tarefa 5 — serviço (Python/HTML) lendo os novos tópicos e enviando comando

Liste os tópicos que o seu ESP32 publica:

>

---

## Evidências (prints)

- **Serial do ESP32** publicando os tópicos separados (e o contador de ciclos do Deep Sleep):

- **Serviço no seu PC** lendo os tópicos ao vivo:

- **Logs** (Wi-Fi: SSID/RSSI/IP/tempo · TLS: hora/relógio) aparecendo:

- **Recebimento**: você enviou um novo limite e o Serial mostrando `-> novo limite = ...` + o LED:

---

## Respostas

1. **Por que separar em vários tópicos é melhor do que um só? Uma vantagem.**

2. **O que os logs de Wi-Fi e de TLS dizem sobre a saúde do dispositivo?**

3. **Por que o relógio (hora) importa para o TLS?**

4. **O que muda no código ao usar Deep Sleep (por que o trabalho vai para o `setup()`)?**

5. **Qual o trade-off do Deep Sleep com o recebimento de comandos em tempo real?**

6. **Caminho de um comando: do seu serviço até o LED acender.**

---

**Entrega:** envie este `ENTREGA.md` preenchido + o código do ESP32 + o serviço, ao professor.
