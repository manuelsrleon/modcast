#!/usr/bin/env python3
"""
Test multi-instancia REAL para Modcast - VERSIÓN CORREGIDA
Lanza múltiples procesos Elixir independientes con carpetas de mods separadas.

FLUJO CORRECTO IMPLEMENTADO:
1. Escanear carpeta local
2. SELECCIONAR mods a usar (antes de unirse)
3. Unirse a sesión
4. Anunciar SOLO los mods seleccionados
5. Comparar con otros peers
6. Descargar diferencias
7. Esperar a que todos tengan todos los mods
8. Pasar a fase :in_game

NO NECESITAS HACER NADA MANUAL - El script inicia todo automáticamente.

Uso:
    python multiple_instance.py

Requisitos:
    1. Tener Elixir instalado
    2. Estar en el directorio tests/ del proyecto
    3. El proyecto debe tener las dependencias instaladas (mix deps.get)
"""

import os
import sys
import json
import time
import socket
import signal
import subprocess
import threading
import hashlib
import random
import string
import shutil
from pathlib import Path
from datetime import datetime

# Colores para terminal
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def colored(text, color):
    return f"{color}{text}{Colors.ENDC}"

# Configuración de instancias
INSTANCES = [
    {"name": "Alice", "api_port": 5050, "p2p_port": 4040},
    {"name": "Bob", "api_port": 5051, "p2p_port": 4041},
    {"name": "Charlie", "api_port": 5052, "p2p_port": 4042},
]

class ModcastInstance:
    """Maneja una instancia independiente de Modcast"""
    
    def __init__(self, config, test_dir):
        self.name = config["name"]
        self.api_port = config["api_port"]
        self.p2p_port = config["p2p_port"]
        self.process = None
        self.log_file = None
        
        # Directorios únicos para esta instancia
        self.base_dir = test_dir / self.name.lower()
        self.mods_dir = self.base_dir / "mods"
        self.data_dir = self.base_dir / "data"
        
        # Tracking
        self.mod_hashes = []
        self.is_ready = False
    
    def setup(self):
        """Prepara el entorno para esta instancia"""
        print(colored(f"[{self.name}] Preparando entorno...", Colors.OKCYAN))
        
        # Limpiar si existe
        if self.base_dir.exists():
            shutil.rmtree(self.base_dir)
        
        # Crear directorios
        self.mods_dir.mkdir(parents=True, exist_ok=True)
        self.data_dir.mkdir(exist_ok=True)
        
        # Cerrar log file anterior si existe
        if self.log_file and not self.log_file.closed:
            self.log_file.close()
        
        # Archivo de log
        self.log_file = open(self.base_dir / "output.log", "w", buffering=1)
        
        print(colored(f"[{self.name}] ✓ Directorios creados", Colors.OKGREEN))
        print(f"  Mods: {self.mods_dir}")
        print(f"  Data: {self.data_dir}")
        
        return True
    
    def create_test_mod(self, name, size_kb=2):
        """Crea un mod de prueba único"""
        filename = f"{name}.zip"
        filepath = self.mods_dir / filename
        
        # Contenido único (incluye nombre de instancia para garantizar unicidad)
        content = f"MOD:{name}|OWNER:{self.name}|TIMESTAMP:{time.time()}|"
        content += ''.join(random.choices(string.ascii_letters + string.digits, k=size_kb * 1024))
        
        with open(filepath, 'w') as f:
            f.write(content)
        
        # Calcular hash
        with open(filepath, 'rb') as f:
            file_hash = hashlib.md5(f.read()).hexdigest()
        
        self.mod_hashes.append(file_hash)
        
        print(colored(f"[{self.name}] ✓ Mod creado: {filename}", Colors.OKGREEN))
        print(f"  Hash: {file_hash[:16]}...")
        print(f"  Tamaño: {size_kb}KB")
        
        return file_hash
    
    def start(self, project_root):
        """Inicia el proceso Elixir con Modcast"""
        print(colored(f"\n[{self.name}] Iniciando proceso Elixir...", Colors.HEADER))
        
        # Script Elixir completo que inicia Modcast desde cero
        elixir_script = f'''
# Configurar aplicación
Application.put_env(:modcast, :api_port, {self.api_port})
Application.put_env(:modcast, :p2p_port, {self.p2p_port})
Application.put_env(:modcast, :mods_folder, "{str(self.mods_dir.absolute()).replace(chr(92), '/')}")

# Asegurarse de que la aplicación está compilada
unless Code.ensure_loaded?(Modcast.MSAPI) do
  IO.puts("[{self.name}] Compilando aplicación...")
  Mix.Task.run("compile")
end

# Iniciar MSAPI con configuración personalizada
IO.puts("[{self.name}] Iniciando MSAPI en puerto {{api: {self.api_port}, p2p: {self.p2p_port}}}...")

case Modcast.MSAPI.start_link(
  api_port: {self.api_port},
  p2p_port: {self.p2p_port}
) do
  {{:ok, pid}} ->
    IO.puts("[{self.name}] ✓ MSAPI iniciado (PID: #{{inspect(pid)}})")
    IO.puts("[READY:{self.name}]")
  {{:error, {{:already_started, pid}}}} ->
    IO.puts("[{self.name}] ✓ MSAPI ya estaba iniciado (PID: #{{inspect(pid)}})")
    IO.puts("[READY:{self.name}]")
  {{:error, reason}} ->
    IO.puts("[{self.name}] ✗ Error iniciando MSAPI: #{{inspect(reason)}}")
    System.halt(1)
end

# Mantener el proceso vivo
Process.sleep(:infinity)
'''
        
        # Comando para ejecutar
        cmd = [
            "elixir",
            "--no-halt",
            "-S", "mix", "run",
            "--no-start",  # No iniciar aplicación automáticamente
            "-e", elixir_script
        ]
        
        env = os.environ.copy()
        env["MIX_ENV"] = "dev"
        
        # Iniciar proceso
        self.process = subprocess.Popen(
            cmd,
            cwd=str(project_root),
            stdout=self.log_file,
            stderr=subprocess.STDOUT,
            env=env,
            universal_newlines=True,
            bufsize=1
        )
        
        print(f"[{self.name}] PID: {self.process.pid}")
        print(f"[{self.name}] API Port: {self.api_port}")
        print(f"[{self.name}] P2P Port: {self.p2p_port}")
        print(f"[{self.name}] Log: {self.base_dir / 'output.log'}")
        
        # Esperar a que el puerto esté disponible
        if self.wait_for_ready(timeout=45):
            print(colored(f"[{self.name}] ✓ Instancia lista\n", Colors.OKGREEN))
            self.is_ready = True
            return True
        else:
            print(colored(f"[{self.name}] ✗ Timeout esperando inicio\n", Colors.FAIL))
            print(colored(f"[{self.name}] Últimas líneas del log:", Colors.WARNING))
            print(self.get_log_tail(15))
            self.stop()
            return False
    
    def wait_for_ready(self, timeout=45):
        """Espera a que el proceso esté listo"""
        start = time.time()
        log_path = self.base_dir / "output.log"
        
        # Primero esperar a que aparezca el log
        while time.time() - start < 5:
            if log_path.exists():
                break
            time.sleep(0.1)
        
        # Ahora monitorear el log
        last_size = 0
        ready_signals = [
            f"[READY:{self.name}]",
            "Listening for Game Engine",
            "MSAPI iniciado"
        ]
        
        while time.time() - start < timeout:
            # Verificar si el proceso sigue vivo
            if self.process.poll() is not None:
                print(colored(f"[{self.name}] ✗ Proceso terminó inesperadamente", Colors.FAIL))
                return False
            
            # Leer nuevas líneas del log
            if log_path.exists():
                current_size = log_path.stat().st_size
                if current_size > last_size:
                    with open(log_path, 'r') as f:
                        f.seek(last_size)
                        new_content = f.read()
                        last_size = current_size
                        
                        # Buscar señales de ready
                        for signal in ready_signals:
                            if signal in new_content:
                                # Verificar que el puerto esté escuchando
                                time.sleep(1)  # Dar tiempo para que el puerto se abra
                                if self.check_port(self.api_port):
                                    return True
            
            time.sleep(0.5)
        
        return False
    
    def check_port(self, port, timeout=2):
        """Verifica si un puerto está escuchando"""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex(('127.0.0.1', port))
            sock.close()
            return result == 0
        except:
            return False
    
    def stop(self):
        """Detiene el proceso"""
        if self.process and self.process.poll() is None:
            print(colored(f"[{self.name}] Deteniendo...", Colors.WARNING))
            
            # Intentar terminar gracefully
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                # Si no responde, forzar
                self.process.kill()
                self.process.wait()
        
        if self.log_file and not self.log_file.closed:
            self.log_file.close()
        
        self.is_ready = False
    
    def get_log_tail(self, lines=20):
        """Obtiene las últimas líneas del log"""
        log_path = self.base_dir / "output.log"
        if log_path.exists():
            try:
                with open(log_path, 'r') as f:
                    all_lines = f.readlines()
                    return ''.join(all_lines[-lines:])
            except:
                return "(no se pudo leer el log)"
        return "(log no existe)"


class ModcastClient:
    """Cliente para interactuar con una instancia vía MSAPI"""
    
    def __init__(self, instance):
        self.instance = instance
        self.name = instance.name
        self.socket = None
        self.events = []
        self.responses = []
        self.listener_thread = None
        self.running = False
    
    def connect(self, retries=3):
        """Conecta al MSAPI con reintentos"""
        for attempt in range(retries):
            try:
                self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.socket.settimeout(10)
                self.socket.connect(("127.0.0.1", self.instance.api_port))
                
                # Iniciar listener
                self.running = True
                self.listener_thread = threading.Thread(target=self._listen, daemon=True)
                self.listener_thread.start()
                
                print(colored(f"[{self.name}] ✓ Conectado a MSAPI", Colors.OKGREEN))
                return True
            except Exception as e:
                if attempt < retries - 1:
                    print(colored(f"[{self.name}] Reintentando conexión... ({attempt+1}/{retries})", Colors.WARNING))
                    time.sleep(2)
                else:
                    print(colored(f"[{self.name}] ✗ Error conectando: {e}", Colors.FAIL))
                    return False
        return False
    
    def _listen(self):
        """Escucha eventos del servidor"""
        file_obj = self.socket.makefile("r")
        while self.running:
            try:
                line = file_obj.readline()
                if not line:
                    break
                
                data = json.loads(line.strip())
                
                if "event" in data:
                    self.events.append(data)
                    self._handle_event(data["event"], data.get("data", {}))
                elif "response" in data:
                    self.responses.append(data)
            except json.JSONDecodeError:
                pass
            except Exception as e:
                if self.running:
                    print(colored(f"[{self.name}] Error en listener: {e}", Colors.FAIL))
                break
    
    def _handle_event(self, event_type, data):
        """Maneja eventos"""
        icons = {
            "mod_ready": "📦",
            "all_mods_ready": "✅",
            "game_started": "🎮",
            "entity_created": "🚗"
        }
        
        icon = icons.get(event_type, "📡")
        
        if event_type == "mod_ready":
            mod_name = data.get('display_name', 'Unknown')
            hash_short = data.get('hash', '')[:8]
            print(f"  {icon} [{self.name}] Mod descargado: {mod_name} ({hash_short}...)")
        elif event_type == "all_mods_ready":
            print(f"  {icon} [{self.name}] ¡Todos los mods listos!")
        else:
            print(f"  {icon} [{self.name}] {event_type}")
    
    def send_command(self, command):
        """Envía un comando"""
        try:
            msg = json.dumps(command) + "\n"
            self.socket.sendall(msg.encode())
            time.sleep(0.1)
            return True
        except Exception as e:
            print(colored(f"[{self.name}] Error enviando: {e}", Colors.FAIL))
            return False
    
    def get_available_mods(self, timeout=5):
        """Obtiene la lista de mods disponibles según Elixir"""
        # Limpiar respuestas anteriores
        self.responses.clear()
        
        # Dar tiempo para que se procesen mensajes anteriores
        time.sleep(0.5)
        
        # Enviar comando
        self.send_command({"action": "list_available_mods"})
        
        # Esperar respuesta
        start = time.time()
        while time.time() - start < timeout:
            if self.responses:
                response = self.responses[-1]  # Última respuesta
                
                if "response" in response:
                    if response.get("response") == "ok":
                        message = response.get("message")
                        
                        # El mensaje puede ser una lista directamente
                        if isinstance(message, list):
                            if len(message) > 0:
                                print(colored(f"  [{self.name}] ✓ {len(message)} mod(s) escaneado(s)", Colors.OKGREEN))
                            else:
                                print(colored(f"  [{self.name}] ⚠️  0 mods encontrados (carpeta vacía?)", Colors.WARNING))
                            return message
                        elif isinstance(message, str):
                            try:
                                # Intentar parsear como JSON
                                import json
                                parsed = json.loads(message)
                                if isinstance(parsed, list):
                                    print(colored(f"  [{self.name}] ✓ {len(parsed)} mod(s) escaneado(s)", Colors.OKGREEN))
                                    return parsed
                            except:
                                pass
                        
                        # Si no es lista, podría ser un dict con los datos
                        if isinstance(message, dict):
                            if "mods" in message:
                                return message["mods"]
                            if "hashes" in message:
                                return message["hashes"]
                    
            time.sleep(0.2)
        
        print(colored(f"[{self.name}] ⚠️  Timeout esperando list_available_mods", Colors.WARNING))
        return []
    
    def wait_for_event(self, event_type, timeout=10):
        """Espera un evento específico"""
        start = time.time()
        while time.time() - start < timeout:
            for event in self.events:
                if event["event"] == event_type:
                    return event
            time.sleep(0.1)
        return None
    
    def close(self):
        """Cierra la conexión"""
        self.running = False
        if self.socket:
            try:
                self.socket.close()
            except:
                pass


def verify_prerequisites(project_root):
    """Verifica que todo esté listo para ejecutar los tests"""
    print(colored("\n🔍 Verificando prerequisitos...", Colors.HEADER))
    
    checks = []
    
    # Check 1: Elixir instalado
    try:
        result = subprocess.run(["elixir", "--version"], 
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            version = result.stdout.split('\n')[0]
            print(colored(f"  ✓ Elixir: {version}", Colors.OKGREEN))
            checks.append(True)
        else:
            print(colored(f"  ✗ Elixir no responde correctamente", Colors.FAIL))
            checks.append(False)
    except:
        print(colored(f"  ✗ Elixir no encontrado", Colors.FAIL))
        checks.append(False)
    
    # Check 2: Mix disponible
    try:
        result = subprocess.run(["mix", "--version"], 
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            print(colored(f"  ✓ Mix disponible", Colors.OKGREEN))
            checks.append(True)
        else:
            print(colored(f"  ✗ Mix no disponible", Colors.FAIL))
            checks.append(False)
    except:
        print(colored(f"  ✗ Mix no encontrado", Colors.FAIL))
        checks.append(False)
    
    # Check 3: mix.exs existe
    mix_file = project_root / "mix.exs"
    if mix_file.exists():
        print(colored(f"  ✓ mix.exs encontrado", Colors.OKGREEN))
        checks.append(True)
    else:
        print(colored(f"  ✗ mix.exs no encontrado en {project_root}", Colors.FAIL))
        checks.append(False)
    
    # Check 4: Dependencias instaladas
    deps_dir = project_root / "deps"
    if deps_dir.exists() and any(deps_dir.iterdir()):
        print(colored(f"  ✓ Dependencias instaladas", Colors.OKGREEN))
        checks.append(True)
    else:
        print(colored(f"  ⚠️  Dependencias no encontradas, ejecutando mix deps.get...", Colors.WARNING))
        try:
            result = subprocess.run(["mix", "deps.get"], 
                                  cwd=project_root, 
                                  capture_output=True, 
                                  text=True, 
                                  timeout=60)
            if result.returncode == 0:
                print(colored(f"  ✓ Dependencias instaladas correctamente", Colors.OKGREEN))
                checks.append(True)
            else:
                print(colored(f"  ✗ Error instalando dependencias", Colors.FAIL))
                checks.append(False)
        except:
            print(colored(f"  ✗ Error ejecutando mix deps.get", Colors.FAIL))
            checks.append(False)
    
    # Check 5: Código compilado
    build_dir = project_root / "_build"
    print(colored(f"  ℹ️  Compilando proyecto (puede tardar)...", Colors.OKCYAN))
    try:
        result = subprocess.run(["mix", "compile"], 
                              cwd=project_root, 
                              capture_output=True, 
                              text=True, 
                              timeout=120)
        if result.returncode == 0:
            print(colored(f"  ✓ Proyecto compilado", Colors.OKGREEN))
            checks.append(True)
        else:
            print(colored(f"  ✗ Error compilando proyecto", Colors.FAIL))
            print(result.stderr)
            checks.append(False)
    except:
        print(colored(f"  ✗ Timeout compilando proyecto", Colors.FAIL))
        checks.append(False)
    
    all_ok = all(checks)
    
    if all_ok:
        print(colored("\n✓ Todos los prerequisitos OK\n", Colors.OKGREEN))
    else:
        print(colored("\n✗ Algunos prerequisitos fallan\n", Colors.FAIL))
    
    return all_ok


def run_test_scenario_1(instances, project_root):
    """
    Test Scenario 1: Two peers sharing mods - FLUJO CORRECTO
    
    FLUJO IMPLEMENTADO:
    1. Alice crea sword.zip
    2. Bob crea shield.zip
    3. Alice PRE-SELECCIONA sword (antes de iniciar sesión)
    4. Bob PRE-SELECCIONA shield (antes de unirse)
    5. Alice inicia sesión como host
    6. Bob se une a sesión
    7. Se anuncian SOLO los mods seleccionados
    8. Se descargan diferencias automáticamente
    9. Ambos terminan con ambos mods
    """
    print("\n" + "="*70)
    print(colored("TEST SCENARIO 1: Two Peers Sharing Mods (FLUJO CORRECTO)", Colors.HEADER))
    print("="*70 + "\n")
    
    alice_inst = instances[0]
    bob_inst = instances[1]
    
    # Re-setup para evitar problemas con archivos cerrados
    alice_inst.setup()
    bob_inst.setup()
    
    # CORRECCIÓN: Crear mods ANTES de iniciar Elixir
    print(colored("Step 1: Creating unique mods for each peer", Colors.OKBLUE))
    hash_sword = alice_inst.create_test_mod("epic_sword", size_kb=3)
    hash_shield = bob_inst.create_test_mod("divine_shield", size_kb=3)
    
    # Iniciar instancias DESPUÉS de crear los mods
    print(colored("\nStep 2: Starting Modcast instances (will scan existing mods)", Colors.OKBLUE))
    if not alice_inst.start(project_root):
        return False
    if not bob_inst.start(project_root):
        alice_inst.stop()
        return False
    
    # Conectar clientes
    print(colored("\nStep 3: Connecting API clients", Colors.OKBLUE))
    alice_client = ModcastClient(alice_inst)
    bob_client = ModcastClient(bob_inst)
    
    if not alice_client.connect() or not bob_client.connect():
        alice_inst.stop()
        bob_inst.stop()
        return False
    
    try:
        session_id = f"test_session_{int(time.time())}"
        
        # Obtener los hashes REALES según Elixir (no los de Python)
        print(colored("\nStep 4: Getting actual mod hashes from Elixir", Colors.OKBLUE))
        alice_mods = alice_client.get_available_mods()
        bob_mods = bob_client.get_available_mods()
        
        if not alice_mods or not bob_mods:
            print(colored("✗ No se pudieron obtener los mods de Elixir", Colors.FAIL))
            return False
        
        hash_sword = alice_mods[0] if alice_mods else None
        hash_shield = bob_mods[0] if bob_mods else None
        
        print(colored(f"  → Alice's mod hash (from Elixir): {hash_sword[:16]}...", Colors.OKCYAN))
        print(colored(f"  → Bob's mod hash (from Elixir): {hash_shield[:16]}...", Colors.OKCYAN))
        
        # CORRECCIÓN: Pre-seleccionar mods ANTES de iniciar/unirse a sesión
        print(colored("\nStep 5: PRE-SELECTING mods (before joining session)", Colors.OKBLUE))
        print(colored("  → Alice pre-selecciona sword", Colors.OKCYAN))
        alice_client.send_command({
            "action": "select_mods",
            "player": "Alice",
            "hashes": [hash_sword]
        })
        time.sleep(0.5)
        
        print(colored("  → Bob pre-selecciona shield", Colors.OKCYAN))
        bob_client.send_command({
            "action": "select_mods",
            "player": "Bob",
            "hashes": [hash_shield]
        })
        time.sleep(1)
        
        # Alice inicia sesión (DESPUÉS de seleccionar mods)
        print(colored("\nStep 6: Alice starts session as host (WITH pre-selected mods)", Colors.OKBLUE))
        alice_client.send_command({
            "action": "start_session",
            "session": session_id,
            "player": "Alice"
        })
        time.sleep(2)
        
        # Bob se une (DESPUÉS de seleccionar mods)
        print(colored("\nStep 7: Bob joins session (WITH pre-selected mods)", Colors.OKBLUE))
        bob_client.send_command({
            "action": "join_session",
            "session": session_id,
            "player": "Bob",
            "host": "127.0.0.1"
        })
        time.sleep(2)
        
        # Esperar transferencias automáticas
        print(colored("\nStep 8: Waiting for automatic P2P transfers (10s)...", Colors.OKBLUE))
        print(colored("  → Solo se anuncian los mods SELECCIONADOS", Colors.OKCYAN))
        print(colored("  → No se expone toda la carpeta", Colors.OKCYAN))
        time.sleep(10)
        
        # Verificar
        print(colored("\nStep 9: Verifying mod synchronization", Colors.OKBLUE))
        
        alice_mods = list(alice_inst.mods_dir.glob("*.zip"))
        bob_mods = list(bob_inst.mods_dir.glob("*.zip"))
        
        print(f"\n  Alice's mods folder: {len(alice_mods)} files")
        for mod in sorted(alice_mods):
            print(f"    - {mod.name}")
        
        print(f"\n  Bob's mods folder: {len(bob_mods)} files")
        for mod in sorted(bob_mods):
            print(f"    - {mod.name}")
        
        success = len(alice_mods) == 2 and len(bob_mods) == 2
        
        if success:
            print(colored("\n✓ TEST PASSED: Both peers have both mods!", Colors.OKGREEN))
            print(colored("  ✓ Flujo correcto: pre-selección → unirse → anuncio selectivo → descarga", Colors.OKGREEN))
        else:
            print(colored("\n✗ TEST FAILED: Mod synchronization incomplete", Colors.FAIL))
            print("\n  Checking logs for errors...")
            print(f"\n  Alice log tail:")
            print(alice_inst.get_log_tail(10))
            print(f"\n  Bob log tail:")
            print(bob_inst.get_log_tail(10))
        
        return success
        
    finally:
        alice_client.close()
        bob_client.close()
        time.sleep(1)


def run_test_scenario_2(instances, project_root):
    """
    Test Scenario 2: Three peers mesh network - FLUJO CORRECTO
    
    FLUJO IMPLEMENTADO:
    1. Cada peer crea su mod
    2. Cada peer PRE-SELECCIONA su mod (en :idle)
    3. Alice inicia sesión
    4. Bob y Charlie se unen
    5. Solo se anuncian los mods seleccionados
    6. Descargas automáticas
    7. Todos terminan con todos los mods
    """
    print("\n" + "="*70)
    print(colored("TEST SCENARIO 2: Three Peers Mesh Network (FLUJO CORRECTO)", Colors.HEADER))
    print("="*70 + "\n")
    
    alice_inst = instances[0]
    bob_inst = instances[1]
    charlie_inst = instances[2]
    
    # Re-setup para evitar problemas con archivos cerrados
    alice_inst.setup()
    bob_inst.setup()
    charlie_inst.setup()
    
    # CORRECCIÓN: Crear mods ANTES de iniciar Elixir
    print(colored("Step 1: Creating unique mods", Colors.OKBLUE))
    hash_red = alice_inst.create_test_mod("car_red", size_kb=2)
    hash_blue = bob_inst.create_test_mod("car_blue", size_kb=2)
    hash_map = charlie_inst.create_test_mod("map_desert", size_kb=4)
    
    # Iniciar instancias DESPUÉS de crear los mods
    print(colored("\nStep 2: Starting all instances (will scan existing mods)", Colors.OKBLUE))
    if not alice_inst.start(project_root):
        return False
    if not bob_inst.start(project_root):
        alice_inst.stop()
        return False
    if not charlie_inst.start(project_root):
        alice_inst.stop()
        bob_inst.stop()
        return False
    
    # Conectar clientes
    print(colored("\nStep 3: Connecting clients", Colors.OKBLUE))
    alice_client = ModcastClient(alice_inst)
    bob_client = ModcastClient(bob_inst)
    charlie_client = ModcastClient(charlie_inst)
    
    if not all([alice_client.connect(), bob_client.connect(), charlie_client.connect()]):
        alice_inst.stop()
        bob_inst.stop()
        charlie_inst.stop()
        return False
    
    try:
        session_id = f"test_3peers_{int(time.time())}"
        
        # Obtener hashes REALES de Elixir
        print(colored("\nStep 4: Getting actual mod hashes from Elixir", Colors.OKBLUE))
        alice_mods_list = alice_client.get_available_mods()
        bob_mods_list = bob_client.get_available_mods()
        charlie_mods_list = charlie_client.get_available_mods()
        
        if not alice_mods_list or not bob_mods_list or not charlie_mods_list:
            print(colored("✗ No se pudieron obtener los mods de Elixir", Colors.FAIL))
            return False
        
        hash_red = alice_mods_list[0]
        hash_blue = bob_mods_list[0]
        hash_map = charlie_mods_list[0]
        
        print(colored(f"  → Alice: {hash_red[:16]}...", Colors.OKCYAN))
        print(colored(f"  → Bob: {hash_blue[:16]}...", Colors.OKCYAN))
        print(colored(f"  → Charlie: {hash_map[:16]}...", Colors.OKCYAN))
        
        # CORRECCIÓN: Pre-seleccionar mods ANTES de unirse
        print(colored("\nStep 5: PRE-SELECTING mods (in :idle phase)", Colors.OKBLUE))
        print(colored("  → Alice pre-selecciona car_red", Colors.OKCYAN))
        alice_client.send_command({
            "action": "select_mods",
            "player": "Alice",
            "hashes": [hash_red]
        })
        time.sleep(0.5)
        
        print(colored("  → Bob pre-selecciona car_blue", Colors.OKCYAN))
        bob_client.send_command({
            "action": "select_mods",
            "player": "Bob",
            "hashes": [hash_blue]
        })
        time.sleep(0.5)
        
        print(colored("  → Charlie pre-selecciona map_desert", Colors.OKCYAN))
        charlie_client.send_command({
            "action": "select_mods",
            "player": "Charlie",
            "hashes": [hash_map]
        })
        time.sleep(1)
        
        # Conectar todos (DESPUÉS de pre-seleccionar)
        print(colored("\nStep 6: Establishing P2P mesh (with pre-selected mods)", Colors.OKBLUE))
        alice_client.send_command({
            "action": "start_session",
            "session": session_id,
            "player": "Alice"
        })
        time.sleep(2)
        
        bob_client.send_command({
            "action": "join_session",
            "session": session_id,
            "player": "Bob",
            "host": "127.0.0.1"
        })
        time.sleep(2)
        
        charlie_client.send_command({
            "action": "join_session",
            "session": session_id,
            "player": "Charlie",
            "host": "127.0.0.1"
        })
        time.sleep(2)
        
        # Esperar transferencias (anuncio selectivo automático)
        print(colored("\nStep 7: Waiting for mesh transfers (15s)...", Colors.OKBLUE))
        print(colored("  → Solo se anuncian mods seleccionados", Colors.OKCYAN))
        print(colored("  → Descarga automática de diferencias", Colors.OKCYAN))
        time.sleep(15)
        
        # Verificar
        print(colored("\nStep 8: Verifying synchronization", Colors.OKBLUE))
        
        alice_mods = list(alice_inst.mods_dir.glob("*.zip"))
        bob_mods = list(bob_inst.mods_dir.glob("*.zip"))
        charlie_mods = list(charlie_inst.mods_dir.glob("*.zip"))
        
        print(f"\n  Alice: {len(alice_mods)} mods")
        for mod in sorted(alice_mods):
            print(f"    - {mod.name}")
        
        print(f"\n  Bob: {len(bob_mods)} mods")
        for mod in sorted(bob_mods):
            print(f"    - {mod.name}")
        
        print(f"\n  Charlie: {len(charlie_mods)} mods")
        for mod in sorted(charlie_mods):
            print(f"    - {mod.name}")
        
        success = len(alice_mods) == 3 and len(bob_mods) == 3 and len(charlie_mods) == 3
        
        if success:
            print(colored("\n✓ TEST PASSED: All peers have all 3 mods!", Colors.OKGREEN))
            print(colored("  ✓ Flujo correcto implementado exitosamente", Colors.OKGREEN))
        else:
            print(colored("\n✗ TEST FAILED: Synchronization incomplete", Colors.FAIL))
        
        return success
        
    finally:
        alice_client.close()
        bob_client.close()
        charlie_client.close()
        time.sleep(1)


def run_test_scenario_3_selective_sharing(instances, project_root):
    """
    Test Scenario 3: Compartición selectiva - NUEVO TEST
    
    Verifica que SOLO se anuncian los mods seleccionados, no toda la carpeta:
    1. Alice tiene 5 mods en su carpeta
    2. Alice PRE-SELECCIONA solo 2 mods
    3. Bob se une
    4. Bob solo debería ver/descargar los 2 mods seleccionados, no los 5
    """
    print("\n" + "="*70)
    print(colored("TEST SCENARIO 3: Selective Sharing (NUEVA FUNCIONALIDAD)", Colors.HEADER))
    print("="*70 + "\n")
    
    alice_inst = instances[0]
    bob_inst = instances[1]
    
    # Re-setup para evitar problemas con archivos cerrados
    alice_inst.setup()
    bob_inst.setup()
    
    # CORRECCIÓN: Crear mods ANTES de iniciar Elixir
    print(colored("Step 1: Alice creates 5 mods in her folder", Colors.OKBLUE))
    hash1 = alice_inst.create_test_mod("mod1", size_kb=1)
    hash2 = alice_inst.create_test_mod("mod2", size_kb=1)
    hash3 = alice_inst.create_test_mod("mod3", size_kb=1)
    hash4 = alice_inst.create_test_mod("mod4", size_kb=1)
    hash5 = alice_inst.create_test_mod("mod5", size_kb=1)
    
    # Bob crea 1 mod
    hash_bob = bob_inst.create_test_mod("mod_bob", size_kb=1)
    
    # Iniciar instancias DESPUÉS de crear los mods
    print(colored("\nStep 2: Starting instances (will scan existing mods)", Colors.OKBLUE))
    if not alice_inst.start(project_root) or not bob_inst.start(project_root):
        alice_inst.stop()
        bob_inst.stop()
        return False
    
    # Conectar clientes
    print(colored("\nStep 3: Connecting clients", Colors.OKBLUE))
    alice_client = ModcastClient(alice_inst)
    bob_client = ModcastClient(bob_inst)
    
    if not alice_client.connect() or not bob_client.connect():
        alice_inst.stop()
        bob_inst.stop()
        return False
    
    try:
        session_id = f"test_selective_{int(time.time())}"
        
        # Obtener hashes REALES de Elixir
        print(colored("\nStep 4: Getting actual mod hashes from Elixir", Colors.OKBLUE))
        alice_mods_list = alice_client.get_available_mods()
        bob_mods_list = bob_client.get_available_mods()
        
        if not alice_mods_list or not bob_mods_list:
            print(colored("✗ No se pudieron obtener los mods de Elixir", Colors.FAIL))
            return False
        
        if len(alice_mods_list) < 5:
            print(colored(f"✗ Alice debería tener 5 mods, tiene {len(alice_mods_list)}", Colors.FAIL))
            return False
        
        # Usar los hashes reales de Elixir
        hash1, hash2, hash3, hash4, hash5 = alice_mods_list[:5]
        hash_bob = bob_mods_list[0]
        
        print(colored(f"  → Alice tiene 5 mods", Colors.OKCYAN))
        print(colored(f"  → Bob tiene 1 mod", Colors.OKCYAN))
        
        # VERIFICACIÓN CLAVE: Alice PRE-SELECCIONA solo 2 de sus 5 mods
        print(colored("\nStep 5: Alice PRE-SELECTS ONLY 2 of her 5 mods", Colors.OKBLUE))
        print(colored(f"  → Alice tiene: mod1, mod2, mod3, mod4, mod5", Colors.WARNING))
        print(colored(f"  → Alice selecciona: mod1, mod2 (SOLO 2)", Colors.OKCYAN))
        alice_client.send_command({
            "action": "select_mods",
            "player": "Alice",
            "hashes": [hash1, hash2]  # SOLO 2 de 5
        })
        time.sleep(0.5)
        
        print(colored("  → Bob pre-selecciona su mod", Colors.OKCYAN))
        bob_client.send_command({
            "action": "select_mods",
            "player": "Bob",
            "hashes": [hash_bob]
        })
        time.sleep(1)
        
        # Conectar
        print(colored("\nStep 6: Joining session", Colors.OKBLUE))
        alice_client.send_command({
            "action": "start_session",
            "session": session_id,
            "player": "Alice"
        })
        time.sleep(2)
        
        bob_client.send_command({
            "action": "join_session",
            "session": session_id,
            "player": "Bob",
            "host": "127.0.0.1"
        })
        time.sleep(3)
        
        # Verificar
        print(colored("\nStep 7: Verifying selective sharing", Colors.OKBLUE))
        
        alice_mods = list(alice_inst.mods_dir.glob("*.zip"))
        bob_mods = list(bob_inst.mods_dir.glob("*.zip"))
        
        print(f"\n  Alice's folder: {len(alice_mods)} mods (expected: 5)")
        print(f"  Bob's folder: {len(bob_mods)} mods (expected: 3)")
        
        # Bob debería tener: mod1, mod2, mod_bob = 3 mods
        # Bob NO debería tener: mod3, mod4, mod5
        expected_bob = 3  # mod1 + mod2 + mod_bob
        
        if len(bob_mods) == expected_bob and len(alice_mods) == 5:
            print(colored("\n✓ TEST PASSED: Selective sharing works!", Colors.OKGREEN))
            print(colored("  ✓ Bob solo descargó los 2 mods seleccionados por Alice", Colors.OKGREEN))
            print(colored("  ✓ Los otros 3 mods NO fueron expuestos", Colors.OKGREEN))
            return True
        else:
            print(colored("\n✗ TEST FAILED: Selective sharing not working", Colors.FAIL))
            print(f"  Expected Bob to have {expected_bob} mods, got {len(bob_mods)}")
            if len(bob_mods) > expected_bob:
                print(colored("  ✗ Bob recibió mods NO seleccionados (carpeta completa expuesta)", Colors.FAIL))
            return False
        
    finally:
        alice_client.close()
        bob_client.close()
        time.sleep(1)


def cleanup_instances(instances):
    """Limpia todas las instancias"""
    print(colored("\n🧹 Cleaning up instances...", Colors.WARNING))
    for inst in instances:
        if inst.is_ready or (inst.process and inst.process.poll() is None):
            inst.stop()
    time.sleep(1)


def main():
    """Función principal"""
    print(colored("="*70, Colors.HEADER))
    print(colored("MODCAST MULTI-INSTANCE P2P TEST - VERSIÓN CORREGIDA", Colors.HEADER))
    print(colored("="*70, Colors.HEADER))
    
    # Verificar que estamos en el directorio correcto
    current = Path.cwd()
    if current.name != "tests":
        print(colored("\n⚠️  Este script debe ejecutarse desde el directorio tests/", Colors.WARNING))
        print(f"   Directorio actual: {current}")
        print(f"   Cambia a: cd tests/")
        return 1
    
    project_root = current.parent
    
    print(f"\nDirectorio del proyecto: {project_root}")
    print(f"Tests en: {current}")
    
    # Crear directorio de tests
    test_dir = current / "multi_instance_run"
    if test_dir.exists():
        print(colored("\nLimpiando directorio anterior...", Colors.WARNING))
        shutil.rmtree(test_dir)
    
    test_dir.mkdir()
    print(colored(f"✓ Directorio de tests: {test_dir}\n", Colors.OKGREEN))
    
    # Crear instancias
    print(colored("Configurando instancias:", Colors.HEADER))
    instances = []
    for config in INSTANCES:
        inst = ModcastInstance(config, test_dir)
        if inst.setup():
            instances.append(inst)
        else:
            print(colored(f"✗ Error configurando {config['name']}", Colors.FAIL))
            return 1
    
    if len(instances) < 2:
        print(colored("\n✗ Se necesitan al menos 2 instancias", Colors.FAIL))
        return 1
    
    print(colored(f"\n✓ {len(instances)} instancias configuradas\n", Colors.OKGREEN))
    
    # Menú de tests
    while True:
        print("\n" + "="*70)
        print(colored("TEST MENU - FLUJO CORRECTO IMPLEMENTADO", Colors.HEADER))
        print("="*70)
        print("\n1. Test 1: Two peers sharing mods (flujo correcto)")
        print("2. Test 2: Three peers mesh network (flujo correcto)")
        print("3. Test 3: Selective sharing (NUEVO - verifica pre-selección)")
        print("4. Run all tests")
        print("5. Keep instances running (manual testing)")
        print("0. Exit\n")
        
        choice = input(colored("Select option: ", Colors.OKBLUE)).strip()
        
        try:
            if choice == "0":
                break
            elif choice == "1":
                result = run_test_scenario_1(instances[:2], project_root)
                cleanup_instances(instances[:2])
            elif choice == "2":
                result = run_test_scenario_2(instances, project_root)
                cleanup_instances(instances)
            elif choice == "3":
                result = run_test_scenario_3_selective_sharing(instances[:2], project_root)
                cleanup_instances(instances[:2])
            elif choice == "4":
                print(colored("\n🚀 Running all tests...\n", Colors.HEADER))
                
                result1 = run_test_scenario_1(instances[:2], project_root)
                cleanup_instances(instances[:2])
                time.sleep(2)
                
                result2 = run_test_scenario_2(instances, project_root)
                cleanup_instances(instances)
                time.sleep(2)
                
                result3 = run_test_scenario_3_selective_sharing(instances[:2], project_root)
                cleanup_instances(instances[:2])
                
                print("\n" + "="*70)
                print(colored("TEST SUMMARY", Colors.HEADER))
                print("="*70)
                
                if result1:
                    print(colored("✓ Test 1: PASSED (Two peers)", Colors.OKGREEN))
                else:
                    print(colored("✗ Test 1: FAILED", Colors.FAIL))
                
                if result2:
                    print(colored("✓ Test 2: PASSED (Three peers)", Colors.OKGREEN))
                else:
                    print(colored("✗ Test 2: FAILED", Colors.FAIL))
                
                if result3:
                    print(colored("✓ Test 3: PASSED (Selective sharing)", Colors.OKGREEN))
                else:
                    print(colored("✗ Test 3: FAILED", Colors.FAIL))
                
                if result1 and result2 and result3:
                    print(colored("\n🎉 ALL TESTS PASSED! FLUJO CORRECTO VERIFICADO", Colors.OKGREEN))
                else:
                    print(colored("\n⚠️  Some tests failed", Colors.WARNING))
            
            elif choice == "5":
                print(colored("\nStarting instances for manual testing...", Colors.HEADER))
                
                for inst in instances:
                    if not inst.start(project_root):
                        print(colored(f"✗ Failed to start {inst.name}", Colors.FAIL))
                        cleanup_instances(instances)
                        break
                else:
                    print(colored("\n✓ All instances running!", Colors.OKGREEN))
                    print("\nAPI Ports:")
                    for inst in instances:
                        print(f"  {inst.name}: localhost:{inst.api_port}")
                    
                    print("\nP2P Ports:")
                    for inst in instances:
                        print(f"  {inst.name}: localhost:{inst.p2p_port}")
                    
                    print("\nLogs:")
                    for inst in instances:
                        print(f"  {inst.name}: {inst.base_dir / 'output.log'}")
                    
                    print(colored("\n💡 FLUJO CORRECTO:", Colors.OKCYAN))
                    print(colored("  1. select_mods (en :idle)", Colors.OKCYAN))
                    print(colored("  2. start_session o join_session", Colors.OKCYAN))
                    print(colored("  3. Anuncio automático de mods seleccionados", Colors.OKCYAN))
                    print(colored("  4. Descarga automática de diferencias", Colors.OKCYAN))
                    
                    print(colored("\nPress Enter to stop instances...", Colors.WARNING))
                    input()
                    cleanup_instances(instances)
            
        except KeyboardInterrupt:
            print(colored("\n\n⚠️  Interrupted by user", Colors.WARNING))
            cleanup_instances(instances)
            break
        except Exception as e:
            print(colored(f"\n✗ Error: {e}", Colors.FAIL))
            import traceback
            traceback.print_exc()
            cleanup_instances(instances)
    
    print(colored("\n✓ Tests complete\n", Colors.OKGREEN))
    return 0


if __name__ == "__main__":
    sys.exit(main())
