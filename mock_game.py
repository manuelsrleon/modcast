import json
import socket
import sys
import threading
import time

# Configuración
HOST = "127.0.0.1"
PORT = 5050


def listen_to_server(sock):
    """Escucha mensajes que vienen de Elixir (Eventos)"""
    file_obj = sock.makefile("r")  # Leemos línea por línea
    for line in file_obj:
        try:
            data = json.loads(line)
            print(
                f"\n[GODOT] < Recibido evento de Modcast: {json.dumps(data, indent=2)}"
            )
            print("[GODOT] > Escribe comando (o 'quit'): ", end="", flush=True)
        except:
            print(f"\n[GODOT] < Datos crudos recibidos: {line}")


def start_mock_client():
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((HOST, PORT))
        print(f"[GODOT] Conectado a Modcast en {HOST}:{PORT}")
    except ConnectionRefusedError:
        print("Error: No se puede conectar. ¿Está corriendo 'Modcast.MSAPI' en IEx?")
        return

    # Arrancar hilo para escuchar respuestas sin bloquear el input
    listener = threading.Thread(target=listen_to_server, args=(sock,), daemon=True)
    listener.start()

    print("Comandos disponibles (escribe el número):")
    print("1. Iniciar Host (start_session)")
    print("2. Unirse a Partida (join_session)")
    print("3. Iniciar Juego (start_game)")
    print("4. Crear Entidad (register_entity)")
    print("5. Transferir Entidad (transfer_entity)")
    print("6. Salir de Partida (leave_session)")
    print("7. JSON Personalizado")

    while True:
        print("\n[GODOT] > ", end="")
        user_input = input()

        command = {}

        if user_input == "quit":
            break
        elif user_input == "1":
            command = {
                "action": "start_session",
                "session": "partida_test",
                "player": "jugador_python",
            }
        elif user_input == "2":
            command = {
                "action": "join_session",
                "session": "test_session",
                "player": "jugador_invitado",
                "host": "127.0.0.1",
            }
        elif user_input == "3":
            command = {
                "action": "start_game"
            }
        elif user_input == "4":
            command = {
                "action": "register_entity",
                "entity": "entidad_1",
                "asset": "coche_rojo",
                "player": "jugador_python",
                "hash": "hash_falso_123",
            }
        elif user_input == "5":
            command = {
                "action": "transfer_entity",
                "entity": "entidad_1",
                "new_player": "jugador_invitado",
            }
        elif user_input == "6":
            session = input("Introduce session_id: ")
            command = {
                "action": "leave_session",
                "session": session
            }
        elif user_input == "7":
            raw = input("Introduce JSON: ")
            try:
                command = json.loads(raw)
            except:
                print("JSON inválido")
                continue
        else:
            continue

        # Enviar al socket con salto de línea (protocolo line-based)
        msg = json.dumps(command) + "\n"
        sock.sendall(msg.encode("utf-8"))

    sock.close()


if __name__ == "__main__":
    start_mock_client()