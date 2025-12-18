# test_simple_connection.py
import socket
import json
import time

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(("127.0.0.1", 5050))
print("✓ Conectado a MSAPI")

# Start session
cmd = {"action": "start_session", "session": "debug_test", "player": "Host"}
sock.send((json.dumps(cmd) + "\n").encode())
time.sleep(2)

# Intentar join desde otro proceso
sock2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock2.connect(("127.0.0.1", 5050))
print("✓ Segundo cliente conectado")

cmd2 = {"action": "join_session", "session": "debug_test", "player": "Client", "host": "127.0.0.1"}
sock2.send((json.dumps(cmd2) + "\n").encode())

print("Esperando 5 segundos...")
time.sleep(5)

print("¿Sigue conectado?")
time.sleep(10)
