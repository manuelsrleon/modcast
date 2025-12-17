import json
import socket
import threading
import time
import os
import hashlib

class ModcastClient:
    def __init__(self, name, host="127.0.0.1", port=5050, session_id="test_session"):
        self.name = name
        self.host = host
        self.port = port
        self.session_id = session_id
        self.sock = None
        self.running = False
        self.available_mods = {}
        
    def connect(self):
        """Conecta al MSAPI de Elixir"""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.connect((self.host, self.port))
            print(f"[{self.name}] Conectado a Modcast")
            self.running = True
            return True
        except ConnectionRefusedError:
            print(f"[{self.name}] Error: No se puede conectar a {self.host}:{self.port}")
            return False
    
    def listen(self):
        """Escucha eventos del servidor"""
        file_obj = self.sock.makefile("r")
        while self.running:
            try:
                line = file_obj.readline()
                if not line:
                    break
                
                data = json.loads(line.strip())
                
                if "event" in data:
                    self._handle_event(data["event"], data.get("data", {}))
                elif "response" in data:
                    self._handle_response(data["response"], data.get("message", ""))
                else:
                    print(f"[{self.name}] < Datos recibidos: {data}")
                    
            except json.JSONDecodeError:
                print(f"[{self.name}] < Datos crudos: {line.strip()}")
            except Exception as e:
                print(f"[{self.name}] Error en listener: {e}")
                break
    
    def _handle_event(self, event_type, data):
        """Maneja eventos del servidor"""
        handlers = {
            "entity_created": lambda d: print(f"[{self.name}] < ENTIDAD CREADA: {d}"),
            "entity_transferred": lambda d: print(f"[{self.name}] < ENTIDAD TRANSFERIDA: {d}"),
            "game_started": lambda d: print(f"[{self.name}] < JUEGO INICIADO"),
            "mod_ready": lambda d: self._handle_mod_ready(d),
            "mod_hash_mismatch": lambda d: print(f"[{self.name}] < HASH MISMATCH: {d}"),
            "all_mods_ready": lambda d: print(f"[{self.name}] < TODOS LOS MODS LISTOS")
        }
        
        if event_type in handlers:
            handlers[event_type](data)
        else:
            print(f"[{self.name}] < Evento desconocido: {event_type} - {data}")
    
    def _handle_mod_ready(self, data):
        """Maneja cuando un mod está listo"""
        print(f"[{self.name}] < MOD LISTO: {data.get('display_name', 'Unknown')}")
        print(f"  Hash: {data.get('hash', '')[:8]}...")
        print(f"  Archivo: {data.get('filename', '')}")
    
    def _handle_response(self, status, message):
        """Maneja respuestas a comandos"""
        color = "\033[92m" if status == "ok" else "\033[91m"
        print(f"{color}[{self.name}] ✓ {message}\033[0m")
    
    def send_command(self, command):
        """Envía un comando al servidor"""
        try:
            msg = json.dumps(command) + "\n"
            self.sock.sendall(msg.encode("utf-8"))
            return True
        except Exception as e:
            print(f"[{self.name}] Error enviando comando: {e}")
            return False
    
    def start_session(self, is_host=True, host_ip="127.0.0.1"):
        """Inicia o se une a una sesión"""
        if is_host:
            command = {
                "action": "start_session",
                "session": self.session_id,
                "player": self.name
            }
        else:
            command = {
                "action": "join_session",
                "session": self.session_id,
                "player": self.name,
                "host": host_ip
            }
        return self.send_command(command)
    
    def announce_required_mods(self, mod_hashes):
        """Anuncia mods requeridos"""
        command = {
            "action": "announce_required_mods",
            "hashes": mod_hashes  # ← Usa 'hashes' como espera el MSAPI
        }
        return self.send_command(command)
    
    def select_mods(self, mod_hashes):
        """Selecciona mods para el jugador"""
        command = {
            "action": "select_mods",
            "player": self.name,
            "hashes": mod_hashes
        }
        return self.send_command(command)
    
    def get_selected_mods(self):
        """Obtiene mods seleccionados por este jugador"""
        command = {
            "action": "get_selected_mods",
            "player": self.name
        }
        return self.send_command(command)
    
    def register_entity(self, entity_id, asset_id, mod_hash):
        """Registra una entidad con un mod"""
        command = {
            "action": "register_entity",
            "entity": entity_id,
            "asset": asset_id,
            "player": self.name,
            "hash": mod_hash
        }
        return self.send_command(command)
    
    def transfer_entity(self, entity_id, new_player):
        """Transfiere una entidad a otro jugador"""
        command = {
            "action": "transfer_entity",
            "entity": entity_id,
            "new_player": new_player
        }
        return self.send_command(command)
    
    def get_entity(self, entity_id):
        """Obtiene una entidad por ID"""
        command = {
            "action": "get_entity",
            "entity": entity_id
        }
        return self.send_command(command)
    
    def get_all_entities(self):
        """Obtiene todas las entidades"""
        return self.send_command({"action": "get_all_entities"})
    
    def get_phase(self):
        """Obtiene la fase actual del juego"""
        return self.send_command({"action": "get_phase"})
    
    def get_players(self):
        """Obtiene la lista de jugadores"""
        return self.send_command({"action": "get_players"})
    
    def get_stats(self):
        """Obtiene estadísticas del juego"""
        return self.send_command({"action": "get_stats"})
    
    def get_mod_info(self, hash):
        """Obtiene información de un mod"""
        command = {
            "action": "get_mod_info",
            "hash": hash
        }
        return self.send_command(command)
    
    def is_mod_available(self, hash):
        """Verifica si un mod está disponible"""
        command = {
            "action": "is_mod_available",
            "hash": hash
        }
        return self.send_command(command)
    
    def list_available_mods(self):
        """Lista mods disponibles"""
        return self.send_command({"action": "list_available_mods"})
    
    def start_game(self):
        """Inicia el juego"""
        return self.send_command({"action": "start_game"})
    
    def leave_session(self):
        """Abandona la sesión"""
        return self.send_command({
            "action": "leave_session",
            "session": self.session_id
        })
    
    def scan_local_mods(self, mods_folder):
        """Escanea mods locales y calcula sus hashes"""
        if not os.path.exists(mods_folder):
            return []
        
        mods = []
        for filename in os.listdir(mods_folder):
            if filename.endswith(".zip"):
                filepath = os.path.join(mods_folder, filename)
                try:
                    with open(filepath, 'rb') as f:
                        file_hash = hashlib.md5(f.read()).hexdigest()
                    mods.append({
                        "filename": filename,
                        "hash": file_hash,
                        "path": filepath
                    })
                except Exception as e:
                    print(f"[{self.name}] Error leyendo {filename}: {e}")
        
        return mods
    
    def create_test_mods(self, folder="test_mocks/mod_files"):
        """Crea archivos .zip de prueba vacíos"""
        os.makedirs(folder, exist_ok=True)
        
        test_mods = [
            ("car_red.zip", b"red_car_model"),
            ("car_blue.zip", b"blue_car_model"), 
            ("weapon_laser.zip", b"laser_weapon_model"),
            ("map_desert.zip", b"desert_map_data")
        ]
        
        created = []
        for filename, content in test_mods:
            path = os.path.join(folder, filename)
            if not os.path.exists(path):
                with open(path, 'wb') as f:
                    f.write(content)
                # Calcular hash
                with open(path, 'rb') as f:
                    file_hash = hashlib.md5(f.read()).hexdigest()
                created.append((filename, file_hash))
                print(f"[{self.name}] Creado {filename} -> Hash: {file_hash[:8]}...")
        
        return created
    
    def run_interactive(self):
        """Ejecuta cliente en modo interactivo"""
        listener = threading.Thread(target=self.listen, daemon=True)
        listener.start()
        
        print(f"\n[{self.name}] Comandos interactivos:")
        print("  h: Hostear nueva sesión")
        print("  j: Unirse a sesión existente")
        print("  a: Anunciar mods requeridos")
        print("  s: Seleccionar mods")
        print("  gs: Obtener mods seleccionados")
        print("  r: Registrar entidad")
        print("  t: Transferir entidad")
        print("  start: Iniciar juego")
        print("  stats: Obtener estadísticas")
        print("  phase: Obtener fase actual")
        print("  players: Obtener jugadores")
        print("  mods: Listar mods disponibles")
        print("  l: Salir de sesión")
        print("  q: Salir")
        print("  m: Mandar comando JSON personalizado")
        
        while self.running:
            try:
                cmd = input(f"[{self.name}] > ").strip().lower()
                
                if cmd == 'q':
                    break
                elif cmd == 'h':
                    self.start_session(is_host=True)
                elif cmd == 'j':
                    host_ip = input("IP del host: ").strip() or "127.0.0.1"
                    self.start_session(is_host=False, host_ip=host_ip)
                elif cmd == 'a':
                    mods_input = input("Hashes de mods (separados por coma): ").strip()
                    mods = [m.strip() for m in mods_input.split(",") if m.strip()]
                    self.announce_required_mods(mods)
                elif cmd == 's':
                    mods_input = input("Hashes de mods a seleccionar (separados por coma): ").strip()
                    mods = [m.strip() for m in mods_input.split(",") if m.strip()]
                    self.select_mods(mods)
                elif cmd == 'gs':
                    self.get_selected_mods()
                elif cmd == 'r':
                    entity = input("ID entidad: ").strip() or f"entity_{self.name}"
                    asset = input("ID asset: ").strip() or "default_asset"
                    mod_hash = input("Hash del mod: ").strip() or "test_hash"
                    self.register_entity(entity, asset, mod_hash)
                elif cmd == 't':
                    entity = input("ID entidad: ").strip() or f"entity_{self.name}"
                    new_player = input("Nuevo jugador: ").strip()
                    self.transfer_entity(entity, new_player)
                elif cmd == 'start':
                    self.start_game()
                elif cmd == 'stats':
                    self.get_stats()
                elif cmd == 'phase':
                    self.get_phase()
                elif cmd == 'players':
                    self.get_players()
                elif cmd == 'mods':
                    self.list_available_mods()
                elif cmd == 'l':
                    self.leave_session()
                elif cmd == 'm':
                    json_str = input("JSON: ").strip()
                    try:
                        command = json.loads(json_str)
                        self.send_command(command)
                    except json.JSONDecodeError:
                        print("JSON inválido")
                else:
                    print("Comando desconocido")
                    
            except KeyboardInterrupt:
                print(f"\n[{self.name}] Saliendo...")
                break
            except Exception as e:
                print(f"[{self.name}] Error: {e}")
        
        self.disconnect()
    
    def disconnect(self):
        """Desconecta el cliente"""
        self.running = False
        if self.sock:
            self.sock.close()
        print(f"[{self.name}] Desconectado")

def main():
    """Función principal para cliente standalone"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Cliente Mock para Modcast")
    parser.add_argument("--name", required=True, help="Nombre del jugador")
    parser.add_argument("--host", default="127.0.0.1", help="Host de Modcast MSAPI")
    parser.add_argument("--port", type=int, default=5050, help="Puerto de Modcast MSAPI")
    parser.add_argument("--session", default="test_session", help="ID de sesión")
    
    args = parser.parse_args()
    
    client = ModcastClient(
        name=args.name,
        host=args.host,
        port=args.port,
        session_id=args.session
    )
    
    if client.connect():
        client.run_interactive()

if __name__ == "__main__":
    main()
