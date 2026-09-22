# Serviço que roda NO SEU COMPUTADOR: fica LENDO os topicos do ESP32
# e permite ESCREVER comandos de volta (troca a regra / liga o LED).
#
# Instale antes:  pip install paho-mqtt
# Rode com:       python servico.py

import paho.mqtt.client as mqtt

BROKER = "test.mosquitto.org"          # broker publico Eclipse Mosquitto
NOME   = "leonam"                      # >>> troque pelo seu (mesmo do ESP32) <<<
base   = f"sis1a/{NOME}/"

# ---- LEITURA: chega uma mensagem de qualquer topico do prefixo ----
def ao_conectar(cliente, userdata, flags, rc, *args):
    print(f"Conectado ao Mosquitto. Ouvindo {base}#\n")
    cliente.subscribe(base + "#")

def ao_receber(cliente, userdata, msg):
    print(f"  [recebido] {msg.topic} = {msg.payload.decode()}")

# paho-mqtt 2.x usa CallbackAPIVersion; o try cobre as duas versoes
try:
    cliente = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
except (AttributeError, TypeError):
    cliente = mqtt.Client()

cliente.on_connect = ao_conectar
cliente.on_message = ao_receber
cliente.connect(BROKER, 1883, 30)
cliente.loop_start()                   # fica LENDO em segundo plano

print("Comandos: um NUMERO = novo limite | 'on'/'off' = LED | 'sair' = encerrar")
while True:
    entrada = input("> ").strip()
    if entrada.lower() == "sair":
        break
    elif entrada.lower() in ("on", "off"):
        cliente.publish(base + "comando", "led:" + entrada.upper())   # ESCREVE
        print("  [enviado] led:" + entrada.upper())
    elif entrada:
        cliente.publish(base + "comando", "limite:" + entrada)        # ESCREVE
        print("  [enviado] limite:" + entrada)

cliente.loop_stop()
cliente.disconnect()
print("Encerrado.")
