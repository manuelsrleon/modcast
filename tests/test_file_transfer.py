#!/usr/bin/env python3
"""
Tests para Modcast con mods persistentes.
Los mods se almacenan en una carpeta compartida ./mods
Cada jugador selecciona qué mods usar, y el sistema descarga automáticamente
los mods que otros jugadores seleccionaron.
"""

import json
import socket
import threading
import time
import os
import hashlib
import random
import string
import shutil

class ModcastTestClient:
    def __init__(self, name, session_id, mods_folder="mods", host="127.0.0.1", port=5050):
        self.name = name
        self.session_id = session_id
        self.host = host
        self.port = port
        self.sock = None
        self.running = False
        
        # Carpeta compartida de mods (persistente)
        self.mods_folder = mods_folder
        os.makedirs(self.mods_folder, exist_ok=True)
        
        self.events_received = []
        self.responses_received = []
        self.local_mods = {}  # Mods que este cliente tiene localmente
        
    def connect(self):
        """Conecta al MSAPI de Elixir"""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.connect((self.host, self.port))
            print(f"[{self.name}] ✓ Conectado a Modcast ({self.host}:{self.port})")
            print(f"[{self.name}] 📁 Carpeta de mods: {self.mods_folder}")
            self.running = True
            threading.Thread(target=self._listen, daemon=True).start()
            return True
        except ConnectionRefusedError:
            print(f"[{self.name}] ✗ Error: No se puede conectar. ¿Está corriendo Modcast?")
            return False
    
    def _listen(self):
        """Escucha eventos del servidor"""
        file_obj = self.sock.makefile("r")
        while self.running:
            try:
                line = file_obj.readline()
                if not line:
                    break
                data = json.loads(line.strip())
                if "event" in data:
                    self.events_received.append(data)
                    self._handle_event(data["event"], data.get("data", {}))
                elif "response" in data:
                    self.responses_received.append(data)
                    self._handle_response(data["response"], data.get("message", ""))
            except json.JSONDecodeError:
                pass
            except Exception as e:
                if self.running:
                    print(f"[{self.name}] Error en listener: {e}")
                break
    
    def _handle_event(self, event_type, data):
        """Maneja eventos del servidor"""
        handlers = {
            "mod_ready": lambda d: print(f"[{self.name}] 📦 Mod descargado: {d.get('display_name')} (hash: {d.get('hash', '')[:8]}...)"),
            "all_mods_ready": lambda d: print(f"[{self.name}] ✓ Todos los mods listos!"),
            "game_started": lambda d: print(f"[{self.name}] 🎮 Juego iniciado"),
            "entity_created": lambda d: print(f"[{self.name}] 🚗 Entidad creada: {d}"),
            "mod_hash_mismatch": lambda d: print(f"[{self.name}] ✗ Error de hash: {d}")
        }
        if event_type in handlers:
            handlers[event_type](data)
    
    def _handle_response(self, status, message):
        """Maneja respuestas a comandos"""
        symbol = "✓" if status == "ok" else "✗"
        color = "\033[92m" if status == "ok" else "\033[91m"
        print(f"{color}[{self.name}] {symbol} {message}\033[0m")
    
    def send_command(self, command):
        """Envía un comando al servidor"""
        try:
            msg = json.dumps(command) + "\n"
            self.sock.sendall(msg.encode("utf-8"))
            time.sleep(0.1)
            return True
        except Exception as e:
            print(f"[{self.name}] Error enviando comando: {e}")
            return False
    
    def create_test_mod(self, name, size_kb=1):
        """Crea un archivo .zip de prueba con contenido aleatorio"""
        filename = f"{name}.zip"
        filepath = os.path.join(self.mods_folder, filename)
        
        # Generar contenido aleatorio
        content = ''.join(random.choices(string.ascii_letters + string.digits, k=size_kb * 1024))
        
        with open(filepath, 'w') as f:
            f.write(content)
        
        # Calcular hash
        with open(filepath, 'rb') as f:
            file_hash = hashlib.md5(f.read()).hexdigest()
        
        self.local_mods[file_hash] = {
            "filename": filename,
            "path": filepath,
            "hash": file_hash
        }
        
        print(f"[{self.name}] 📝 Creado mod: {filename} (hash: {file_hash[:8]}...)")
        return file_hash
    
    def scan_mods_folder(self):
        """Escanea la carpeta de mods y devuelve los hashes"""
        mods = []
        if os.path.exists(self.mods_folder):
            for filename in os.listdir(self.mods_folder):
                if filename.endswith('.zip'):
                    filepath = os.path.join(self.mods_folder, filename)
                    with open(filepath, 'rb') as f:
                        file_hash = hashlib.md5(f.read()).hexdigest()
                    mods.append(file_hash)
        return mods
    
    def start_session(self):
        """Inicia una sesión como host"""
        command = {
            "action": "start_session",
            "session": self.session_id,
            "player": self.name
        }
        return self.send_command(command)
    
    def join_session(self, host_ip="127.0.0.1"):
        """Se une a una sesión existente"""
        command = {
            "action": "join_session",
            "session": self.session_id,
            "player": self.name,
            "host": host_ip
        }
        return self.send_command(command)
    
    def select_mods(self, mod_hashes):
        """Selecciona mods para esta sesión (anuncia automáticamente)"""
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
    
    def start_game(self):
        """Inicia el juego"""
        return self.send_command({"action": "start_game"})
    
    def get_stats(self):
        """Obtiene estadísticas"""
        return self.send_command({"action": "get_stats"})
    
    def list_available_mods(self):
        """Lista mods disponibles"""
        return self.send_command({"action": "list_available_mods"})
    
    def disconnect(self):
        """Desconecta el cliente"""
        self.running = False
        if self.sock:
            self.sock.close()
        print(f"[{self.name}] Desconectado")


def cleanup_mods_folder():
    """Limpia la carpeta de mods antes de tests"""
    if os.path.exists("mods"):
        shutil.rmtree("mods")
    os.makedirs("mods")
    print("🧹 Carpeta mods limpiada")


def test_basic_mod_sharing():
    """
    Test 1: Compartición básica de mods
    - Player1 tiene espada_fuego
    - Player2 tiene espada_hielo
    - Ambos seleccionan sus mods
    - Sistema descarga automáticamente los mods faltantes
    - Ambos terminan con ambos mods
    """
    print("\n" + "="*70)
    print("TEST 1: Compartición básica de mods (2 jugadores, 1 mod cada uno)")
    print("="*70 + "\n")
    
    cleanup_mods_folder()
    session_id = "test_basic_" + str(int(time.time()))
    
    player1 = ModcastTestClient("Player1", session_id)
    player2 = ModcastTestClient("Player2", session_id)
    
    if not player1.connect() or not player2.connect():
        print("✗ Error de conexión")
        return False
    
    try:
        # Paso 1: Cada jugador crea su mod
        print("\n[TEST] Paso 1: Cada jugador crea su propio mod...")
        hash_fuego = player1.create_test_mod("espada_fuego", size_kb=3)
        hash_hielo = player2.create_test_mod("espada_hielo", size_kb=3)
        time.sleep(0.5)
        
        # Paso 2: Player1 hostea
        print("\n[TEST] Paso 2: Player1 inicia sesión...")
        player1.start_session()
        time.sleep(1)
        
        # Paso 3: Player2 se une
        print("\n[TEST] Paso 3: Player2 se une...")
        player2.join_session()
        time.sleep(1)
        
        # Paso 4: Cada jugador selecciona su mod
        print("\n[TEST] Paso 4: Cada jugador selecciona su mod...")
        player1.select_mods([hash_fuego])
        time.sleep(0.5)
        player2.select_mods([hash_hielo])
        time.sleep(3)  # Tiempo para transferencias
        
        # Paso 5: Verificar que ambos tienen ambos mods
        print("\n[TEST] Paso 5: Verificando que ambos tienen ambos mods...")
        
        mods_p1 = player1.scan_mods_folder()
        mods_p2 = player2.scan_mods_folder()
        
        success = (
            hash_fuego in mods_p1 and hash_hielo in mods_p1 and
            hash_fuego in mods_p2 and hash_hielo in mods_p2
        )
        
        if success:
            print(f"\n✓ TEST PASADO!")
            print(f"  Player1 tiene {len(mods_p1)} mods: espada_fuego ✓, espada_hielo ✓")
            print(f"  Player2 tiene {len(mods_p2)} mods: espada_fuego ✓, espada_hielo ✓")
            return True
        else:
            print(f"\n✗ TEST FALLIDO!")
            print(f"  Player1 mods: {mods_p1}")
            print(f"  Player2 mods: {mods_p2}")
            return False
            
    finally:
        player1.disconnect()
        player2.disconnect()


def test_multiple_mods_per_player():
    """
    Test 2: Múltiples mods por jugador
    - Player1 tiene: coche_rojo, coche_azul
    - Player2 tiene: mapa_desierto
    - Player1 selecciona sus 2 mods
    - Player2 selecciona su mod
    - Todos terminan con los 3 mods
    """
    print("\n" + "="*70)
    print("TEST 2: Múltiples mods por jugador")
    print("="*70 + "\n")
    
    cleanup_mods_folder()
    session_id = "test_multiple_" + str(int(time.time()))
    
    player1 = ModcastTestClient("Player1", session_id)
    player2 = ModcastTestClient("Player2", session_id)
    
    if not player1.connect() or not player2.connect():
        return False
    
    try:
        # Crear mods
        print("\n[TEST] Creando mods...")
        hash_rojo = player1.create_test_mod("coche_rojo", size_kb=2)
        hash_azul = player1.create_test_mod("coche_azul", size_kb=2)
        hash_desierto = player2.create_test_mod("mapa_desierto", size_kb=5)
        time.sleep(0.5)
        
        # Conectar
        print("\n[TEST] Conectando jugadores...")
        player1.start_session()
        time.sleep(1)
        player2.join_session()
        time.sleep(1)
        
        # Seleccionar mods
        print("\n[TEST] Seleccionando mods...")
        player1.select_mods([hash_rojo, hash_azul])
        time.sleep(0.5)
        player2.select_mods([hash_desierto])
        time.sleep(4)  # Más tiempo para múltiples transferencias
        
        # Verificar
        print("\n[TEST] Verificando...")
        mods_p1 = player1.scan_mods_folder()
        mods_p2 = player2.scan_mods_folder()
        
        all_hashes = {hash_rojo, hash_azul, hash_desierto}
        success = all_hashes.issubset(set(mods_p1)) and all_hashes.issubset(set(mods_p2))
        
        if success:
            print(f"\n✓ TEST PASADO!")
            print(f"  Todos los jugadores tienen los 3 mods")
            return True
        else:
            print(f"\n✗ TEST FALLIDO!")
            print(f"  Player1: {len(mods_p1)}/3 mods")
            print(f"  Player2: {len(mods_p2)}/3 mods")
            return False
            
    finally:
        player1.disconnect()
        player2.disconnect()


def test_three_players():
    """
    Test 3: Tres jugadores con mods diferentes
    - Player1: espada_fuego
    - Player2: escudo_hielo  
    - Player3: arco_viento
    - Todos seleccionan sus mods
    - Todos terminan con los 3 mods
    """
    print("\n" + "="*70)
    print("TEST 3: Tres jugadores intercambiando mods")
    print("="*70 + "\n")
    
    cleanup_mods_folder()
    session_id = "test_three_" + str(int(time.time()))
    
    player1 = ModcastTestClient("Player1", session_id)
    player2 = ModcastTestClient("Player2", session_id)
    player3 = ModcastTestClient("Player3", session_id)
    
    if not player1.connect() or not player2.connect() or not player3.connect():
        return False
    
    try:
        # Crear mods
        print("\n[TEST] Cada jugador crea su mod...")
        hash1 = player1.create_test_mod("espada_fuego", size_kb=2)
        hash2 = player2.create_test_mod("escudo_hielo", size_kb=2)
        hash3 = player3.create_test_mod("arco_viento", size_kb=2)
        time.sleep(0.5)
        
        # Conectar
        print("\n[TEST] Conectando jugadores...")
        player1.start_session()
        time.sleep(1)
        player2.join_session()
        time.sleep(1)
        player3.join_session()
        time.sleep(1)
        
        # Seleccionar mods
        print("\n[TEST] Cada jugador selecciona su mod...")
        player1.select_mods([hash1])
        time.sleep(0.5)
        player2.select_mods([hash2])
        time.sleep(0.5)
        player3.select_mods([hash3])
        time.sleep(5)  # Tiempo para todas las transferencias
        
        # Verificar
        print("\n[TEST] Verificando que todos tienen todos los mods...")
        mods_p1 = player1.scan_mods_folder()
        mods_p2 = player2.scan_mods_folder()
        mods_p3 = player3.scan_mods_folder()
        
        all_hashes = {hash1, hash2, hash3}
        success = (
            all_hashes.issubset(set(mods_p1)) and
            all_hashes.issubset(set(mods_p2)) and
            all_hashes.issubset(set(mods_p3))
        )
        
        if success:
            print(f"\n✓ TEST PASADO!")
            print(f"  Player1: 3/3 mods ✓")
            print(f"  Player2: 3/3 mods ✓")
            print(f"  Player3: 3/3 mods ✓")
            return True
        else:
            print(f"\n✗ TEST FALLIDO!")
            print(f"  Player1: {len(mods_p1)}/3 mods")
            print(f"  Player2: {len(mods_p2)}/3 mods")
            print(f"  Player3: {len(mods_p3)}/3 mods")
            return False
            
    finally:
        player1.disconnect()
        player2.disconnect()
        player3.disconnect()


def test_persistence_across_sessions():
    """
    Test 4: Persistencia entre sesiones
    - Sesión 1: Player1 y Player2 comparten mods
    - Sesión 2: Player1 y Player3 se conectan
    - Player3 selecciona un mod que Player1 ya descargó en sesión 1
    - Verificar que NO se vuelve a descargar (ya está en carpeta)
    """
    print("\n" + "="*70)
    print("TEST 4: Persistencia de mods entre sesiones")
    print("="*70 + "\n")
    
    cleanup_mods_folder()
    
    # SESIÓN 1
    print("\n[TEST] === SESIÓN 1 ===")
    session1_id = "test_persist1_" + str(int(time.time()))
    
    player1 = ModcastTestClient("Player1", session1_id)
    player2 = ModcastTestClient("Player2", session1_id)
    
    if not player1.connect() or not player2.connect():
        return False
    
    try:
        # Sesión 1: compartir mods
        hash_espada = player1.create_test_mod("espada_legendaria", size_kb=3)
        hash_escudo = player2.create_test_mod("escudo_divino", size_kb=3)
        
        player1.start_session()
        time.sleep(1)
        player2.join_session()
        time.sleep(1)
        
        player1.select_mods([hash_espada])
        time.sleep(0.5)
        player2.select_mods([hash_escudo])
        time.sleep(3)
        
        # Verificar que Player1 ahora tiene ambos mods
        mods_p1_session1 = player1.scan_mods_folder()
        print(f"[TEST] Player1 después de sesión 1: {len(mods_p1_session1)} mods")
        
        player1.disconnect()
        player2.disconnect()
        time.sleep(1)
        
    except Exception as e:
        print(f"✗ Error en sesión 1: {e}")
        return False
    
    # SESIÓN 2
    print("\n[TEST] === SESIÓN 2 ===")
    session2_id = "test_persist2_" + str(int(time.time()))
    
    player1_new = ModcastTestClient("Player1", session2_id)
    player3 = ModcastTestClient("Player3", session2_id)
    
    if not player1_new.connect() or not player3.connect():
        return False
    
    try:
        # Player3 crea el MISMO mod que Player2 tenía (mismo contenido = mismo hash)
        # Simular esto creando el archivo directamente
        hash_escudo_p3 = player3.create_test_mod("escudo_divino", size_kb=3)
        
        player1_new.start_session()
        time.sleep(1)
        player3.join_session()
        time.sleep(1)
        
        # Player1 selecciona espada (ya la tiene de sesión 1)
        # Player3 selecciona escudo
        player1_new.select_mods([hash_espada])
        time.sleep(0.5)
        player3.select_mods([hash_escudo_p3])
        time.sleep(2)  # Menos tiempo - Player1 ya tiene escudo
        
        # Verificar
        mods_p1_session2 = player1_new.scan_mods_folder()
        mods_p3 = player3.scan_mods_folder()
        
        success = (
            hash_espada in mods_p1_session2 and
            hash_escudo in mods_p1_session2 and
            len(mods_p1_session2) == 2 and
            len(mods_p3) == 2
        )
        
        if success:
            print(f"\n✓ TEST PASADO!")
            print(f"  Player1 reutilizó mods de sesión anterior")
            print(f"  No hubo descarga redundante")
            return True
        else:
            print(f"\n✗ TEST FALLIDO!")
            return False
            
    finally:
        player1_new.disconnect()
        player3.disconnect()


def test_selective_sharing():
    """
    Test 5: Compartición selectiva
    - Player1 tiene 5 mods en su carpeta
    - Player1 solo selecciona 2 para compartir
    - Player2 solo debería ver/descargar esos 2, no los 5
    """
    print("\n" + "="*70)
    print("TEST 5: Compartición selectiva (solo mods seleccionados)")
    print("="*70 + "\n")
    
    cleanup_mods_folder()
    session_id = "test_selective_" + str(int(time.time()))
    
    player1 = ModcastTestClient("Player1", session_id)
    player2 = ModcastTestClient("Player2", session_id)
    
    if not player1.connect() or not player2.connect():
        return False
    
    try:
        # Player1 crea 5 mods pero solo seleccionará 2
        print("\n[TEST] Player1 crea 5 mods...")
        hash1 = player1.create_test_mod("mod1", size_kb=1)
        hash2 = player1.create_test_mod("mod2", size_kb=1)
        hash3 = player1.create_test_mod("mod3", size_kb=1)
        hash4 = player1.create_test_mod("mod4", size_kb=1)
        hash5 = player1.create_test_mod("mod5", size_kb=1)
        
        # Player2 crea 1 mod
        hash_p2 = player2.create_test_mod("mod_player2", size_kb=1)
        time.sleep(0.5)
        
        # Conectar
        player1.start_session()
        time.sleep(1)
        player2.join_session()
        time.sleep(1)
        
        # Player1 solo selecciona 2 de sus 5 mods
        print("\n[TEST] Player1 selecciona SOLO 2 de sus 5 mods...")
        player1.select_mods([hash1, hash2])  # Solo estos 2
        time.sleep(0.5)
        player2.select_mods([hash_p2])
        time.sleep(3)
        
        # Verificar
        print("\n[TEST] Verificando...")
        mods_p2 = player2.scan_mods_folder()
        
        # Player2 debería tener: mod1, mod2, mod_player2 = 3 mods
        # NO debería tener: mod3, mod4, mod5
        expected_mods = {hash1, hash2, hash_p2}
        unexpected_mods = {hash3, hash4, hash5}
        
        has_expected = expected_mods.issubset(set(mods_p2))
        has_unexpected = any(h in mods_p2 for h in unexpected_mods)
        
        if has_expected and not has_unexpected:
            print(f"\n✓ TEST PASADO!")
            print(f"  Player2 tiene solo los 3 mods seleccionados")
            print(f"  Player2 NO tiene los mods no seleccionados ✓")
            return True
        else:
            print(f"\n✗ TEST FALLIDO!")
            print(f"  Player2 tiene: {len(mods_p2)} mods (esperado: 3)")
            if has_unexpected:
                print(f"  Player2 tiene mods NO seleccionados ✗")
            return False
            
    finally:
        player1.disconnect()
        player2.disconnect()


def run_all_tests():
    """Ejecuta todos los tests"""
    print("\n" + "="*70)
    print("EJECUTANDO SUITE COMPLETA DE TESTS MODCAST")
    print("="*70)
    
    tests = [
        ("Compartición básica", test_basic_mod_sharing),
        ("Múltiples mods por jugador", test_multiple_mods_per_player),
        ("Tres jugadores", test_three_players),
        ("Persistencia entre sesiones", test_persistence_across_sessions),
        ("Compartición selectiva", test_selective_sharing)
    ]
    
    results = []
    for name, test_func in tests:
        try:
            print(f"\n\n{'='*70}")
            print(f"Ejecutando: {name}")
            print('='*70)
            result = test_func()
            results.append((name, result))
            time.sleep(2)
        except Exception as e:
            print(f"\n✗ TEST '{name}' FALLÓ CON EXCEPCIÓN: {e}")
            import traceback
            traceback.print_exc()
            results.append((name, False))
    
    # Resumen
    print("\n\n" + "="*70)
    print("RESUMEN DE TESTS")
    print("="*70)
    
    passed = sum(1 for _, r in results if r)
    total = len(results)
    
    for name, result in results:
        status = "✓ PASADO" if result else "✗ FALLIDO"
        color = "\033[92m" if result else "\033[91m"
        print(f"{color}{status}\033[0m - {name}")
    
    print(f"\n{'='*70}")
    print(f"Resultado final: {passed}/{total} tests pasados ({passed*100//total}%)")
    print('='*70)
    
    return passed == total


def interactive_mode():
    """Modo interactivo para debugging"""
    print("\n=== MODO INTERACTIVO ===\n")
    
    name = input("Nombre del cliente: ").strip() or "TestClient"
    session = input("Session ID: ").strip() or f"test_{int(time.time())}"
    
    client = ModcastTestClient(name, session)
    
    if not client.connect():
        return
    
    print("\nComandos:")
    print("  h - Hostear sesión")
    print("  j - Unirse a sesión")
    print("  c - Crear mod local")
    print("  l - Listar mods disponibles")
    print("  s - Seleccionar mods para esta sesión")
    print("  start - Iniciar juego")
    print("  stats - Ver estadísticas")
    print("  q - Salir")
    
    while True:
        try:
            cmd = input(f"\n[{name}] > ").strip().lower()
            
            if cmd == 'q':
                break
            elif cmd == 'h':
                client.start_session()
            elif cmd == 'j':
                client.join_session()
            elif cmd == 'c':
                mod_name = input("Nombre del mod: ").strip()
                size = int(input("Tamaño (KB): ").strip() or "1")
                client.create_test_mod(mod_name, size)
            elif cmd == 'l':
                mods = client.scan_mods_folder()
                print(f"Mods en carpeta: {len(mods)}")
                for mod_hash in mods:
                    print(f"  - {mod_hash[:16]}...")
            elif cmd == 's':
                mods = client.scan_mods_folder()
                print(f"Mods disponibles:")
                for i, mod_hash in enumerate(mods):
                    print(f"  {i+1}. {mod_hash[:16]}...")
                selection = input("Selecciona (números separados por coma): ").strip()
                if selection:
                    indices = [int(x.strip())-1 for x in selection.split(",")]
                    selected_hashes = [mods[i] for i in indices if 0 <= i < len(mods)]
                    client.select_mods(selected_hashes)
            elif cmd == 'start':
                client.start_game()
            elif cmd == 'stats':
                client.get_stats()
                
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Error: {e}")
    
    client.disconnect()


def main():
    """Menú principal"""
    print("=== TEST SUITE MODCAST ===\n")
    print("1. Ejecutar todos los tests")
    print("2. Test 1: Compartición básica")
    print("3. Test 2: Múltiples mods por jugador")
    print("4. Test 3: Tres jugadores")
    print("5. Test 4: Persistencia entre sesiones")
    print("6. Test 5: Compartición selectiva")
    print("7. Modo interactivo")
    print("0. Salir\n")
    
    choice = input("Selecciona opción: ").strip()
    
    if choice == "1":
        run_all_tests()
    elif choice == "2":
        test_basic_mod_sharing()
    elif choice == "3":
        test_multiple_mods_per_player()
    elif choice == "4":
        test_three_players()
    elif choice == "5":
        test_persistence_across_sessions()
    elif choice == "6":
        test_selective_sharing()
    elif choice == "7":
        interactive_mode()


if __name__ == "__main__":
    main()