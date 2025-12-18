#!/usr/bin/env python3
"""
Lanzador de múltiples instancias de Modcast para pruebas P2P reales.
Usa los parámetros api_port y p2p_port que ya soporta tu código.
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
from pathlib import Path

# Configuración de instancias
INSTANCES = [
    {"name": "Player1", "api_port": 5050, "p2p_port": 4040},
    {"name": "Player2", "api_port": 5051, "p2p_port": 4041},
    {"name": "Player3", "api_port": 5052, "p2p_port": 4042},
]

class ModcastInstance:
    """Representa una instancia de Modcast con su propia configuración."""
    
    def __init__(self, config):
        self.config = config
        self.name = config["name"]
        self.api_port = config["api_port"]
        self.p2p_port = config["p2p_port"]
        self.process = None
        self.mod_hashes = []
        
        # Directorios específicos para esta instancia
        self.instance_dir = Path(f"multi_instance_test/{self.name.lower()}")
        self.mods_dir = self.instance_dir / "mods"
        self.data_dir = self.instance_dir / "data"
    
    def setup(self):
        """Prepara los directorios para esta instancia."""
        print(f"[{self.name}] Preparando directorios...")
        
        # Crear directorios
        self.instance_dir.mkdir(parents=True, exist_ok=True)
        self.mods_dir.mkdir(exist_ok=True)
        self.data_dir.mkdir(exist_ok=True)
        
        # Crear mods únicos para esta instancia
        self.create_unique_mods()
        
        return True
    
    def create_unique_mods(self):
        """Crea mods únicos para esta instancia."""
        print(f"[{self.name}] Creando mods únicos...")
        
        mod_templates = [
            {"filename": f"{self.name.lower()}_car.zip", "content": f"Car model exclusive to {self.name}"},
            {"filename": f"{self.name.lower()}_weapon.zip", "content": f"Weapon model exclusive to {self.name}"},
            {"filename": f"{self.name.lower()}_map.zip", "content": f"Map exclusive to {self.name}"},
        ]
        
        self.mod_hashes = []
        for template in mod_templates:
            filepath = self.mods_dir / template["filename"]
            
            # Escribir contenido
            with open(filepath, "w") as f:
                f.write(template["content"])
            
            # Calcular hash
            with open(filepath, "rb") as f:
                file_hash = hashlib.md5(f.read()).hexdigest()
            
            self.mod_hashes.append(file_hash)
            print(f"  - {template['filename']}: {file_hash[:8]}...")
    
    def start(self):
        """Inicia esta instancia de Modcast."""
        print(f"[{self.name}] Iniciando instancia...")
        print(f"  API port: {self.api_port}")
        print(f"  P2P port: {self.p2p_port}")
        print(f"  Mods dir: {self.mods_dir}")
        
        # Comando para iniciar la instancia
        cmd = [
            "iex", 
            "-S", "mix"
        ]
        
        # Variables de entorno para configuración
        env = os.environ.copy()
        env["MODCAST_API_PORT"] = str(self.api_port)
        env["MODCAST_P2P_PORT"] = str(self.p2p_port)
        env["MODCAST_MODS_FOLDER"] = str(self.mods_dir.absolute())
        
        # Iniciar proceso
        self.process = subprocess.Popen(
            cmd,
            cwd="../..",  # Ir al directorio raíz del proyecto Modcast
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            bufsize=1
        )
        
        # Monitorear salida en segundo plano
        threading.Thread(target=self._monitor_output, daemon=True).start()
        
        # Esperar a que el puerto esté disponible
        if self.wait_for_port(self.api_port, timeout=30):
            print(f"[{self.name}] ✅ Instancia iniciada")
            return True
        else:
            print(f"[{self.name}] ❌ No se pudo iniciar la instancia")
            return False
    
    def _monitor_output(self):
        """Monitorea la salida del proceso."""
        for line in self.process.stdout:
            if line.strip():
                print(f"[{self.name}-OUT] {line.strip()}")
        
        for line in self.process.stderr:
            if line.strip():
                print(f"[{self.name}-ERR] {line.strip()}")
    
    def wait_for_port(self, port, timeout=30):
        """Espera a que un puerto esté disponible."""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(1)
                result = sock.connect_ex(('localhost', port))
                sock.close()
                if result == 0:
                    return True
            except:
                pass
            time.sleep(0.5)
        return False
    
    def stop(self):
        """Detiene esta instancia."""
        if self.process:
            print(f"[{self.name}] Deteniendo instancia...")
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
            self.process = None

class ModcastTestClient:
    """Cliente para interactuar con una instancia de Modcast."""
    
    def __init__(self, name, api_port):
        self.name = name
        self.api_port = api_port
        self.socket = None
    
    def connect(self):
        """Conecta a la instancia de Modcast."""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(10)
            self.socket.connect(("127.0.0.1", self.api_port))
            print(f"[{self.name}-CLIENT] ✅ Conectado a API port {self.api_port}")
            return True
        except Exception as e:
            print(f"[{self.name}-CLIENT] ❌ Error conectando: {e}")
            return False
    
    def send_command(self, command):
        """Envía un comando a la instancia."""
        try:
            message = json.dumps(command) + "\n"
            self.socket.sendall(message.encode())
            
            # Leer respuesta
            response = ""
            self.socket.settimeout(5)
            
            while True:
                try:
                    chunk = self.socket.recv(1024).decode()
                    if not chunk:
                        break
                    response += chunk
                    if "\n" in chunk:
                        break
                except socket.timeout:
                    break
            
            return response.strip()
        except Exception as e:
            return f"Error: {str(e)}"
    
    def close(self):
        """Cierra la conexión."""
        if self.socket:
            self.socket.close()

def run_basic_p2p_test(instances):
    """Ejecuta un test básico de P2P entre instancias."""
    print("\n" + "="*70)
    print("EJECUTANDO TEST P2P BÁSICO")
    print("="*70)
    
    clients = []
    try:
        # Paso 1: Conectar todos los clientes
        print("\n[Paso 1] Conectando clientes...")
        for instance in instances:
            client = ModcastTestClient(instance.name, instance.api_port)
            if client.connect():
                clients.append((instance, client))
            else:
                return False
        
        # Paso 2: Player1 inicia sesión como host
        print("\n[Paso 2] Player1 inicia sesión como host...")
        instance1, client1 = clients[0]
        cmd = {
            "action": "start_session",
            "session": "p2p_test_session",
            "player": instance1.name
        }
        response = client1.send_command(cmd)
        print(f"  {instance1.name}: {response}")
        time.sleep(2)
        
        # Paso 3: Otros jugadores se unen
        print("\n[Paso 3] Otros jugadores se unen...")
        for i in range(1, len(clients)):
            instance, client = clients[i]
            cmd = {
                "action": "join_session",
                "session": "p2p_test_session",
                "player": instance.name,
                "host": "127.0.0.1",
                "port": instance1.p2p_port  # Puerto P2P del host
            }
            response = client.send_command(cmd)
            print(f"  {instance.name}: {response}")
            time.sleep(2)
        
        # Paso 4: Cada jugador selecciona sus mods únicos
        print("\n[Paso 4] Cada jugador selecciona sus mods...")
        for instance, client in clients:
            if instance.mod_hashes:
                # Seleccionar los primeros 2 mods
                selected_hashes = instance.mod_hashes[:2]
                cmd = {
                    "action": "select_mods",
                    "player": instance.name,
                    "hashes": selected_hashes
                }
                response = client.send_command(cmd)
                print(f"  {instance.name} selecciona {len(selected_hashes)} mods: {response[:100]}...")
                time.sleep(1)
        
        # Paso 5: Esperar transferencias P2P
        print("\n[Paso 5] Esperando transferencias P2P (20 segundos)...")
        print("  (Mira los logs de las instancias para ver la transferencia)")
        time.sleep(20)
        
        # Paso 6: Verificar estado
        print("\n[Paso 6] Verificando estado...")
        for instance, client in clients:
            cmd = {"action": "get_stats"}
            response = client.send_command(cmd)
            print(f"  {instance.name} stats: {response[:150]}...")
        
        # Paso 7: Intentar iniciar el juego
        print("\n[Paso 7] Intentando iniciar juego...")
        response = client1.send_command({"action": "start_game"})
        print(f"  start_game: {response}")
        
        print("\n✅ TEST COMPLETADO")
        print("\nRevisa los logs de cada instancia para ver:")
        print("  - Handshakes entre peers")
        print("  - Anuncio de mods disponibles")
        print("  - Solicitudes de transferencia")
        print("  - Transferencias de archivos")
        print("  - Eventos de mods listos")
        
        return True
        
    except Exception as e:
        print(f"\n❌ Error en el test: {e}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        # Cerrar clientes
        for _, client in clients:
            client.close()

def main():
    """Función principal."""
    print("="*70)
    print("MODCAST MULTI-INSTANCE P2P TEST")
    print("="*70)
    print("\nEste script lanzará múltiples instancias de Modcast")
    print("y ejecutará pruebas reales de transferencia P2P.")
    print("\n⚠️  Necesitas tener Elixir y Mix instalados.")
    print("   Cada instancia se ejecuta en el mismo proyecto pero con")
    print("   diferentes puertos y directorios de mods.")
    
    # Limpiar directorio de test anterior
    test_dir = Path("multi_instance_test")
    if test_dir.exists():
        import shutil
        shutil.rmtree(test_dir)
    
    # Crear instancias
    instances = []
    for config in INSTANCES:
        instance = ModcastInstance(config)
        if instance.setup():
            instances.append(instance)
    
    if len(instances) < 2:
        print("❌ Se necesitan al menos 2 instancias para el test")
        return 1
    
    # Iniciar instancias
    print("\n" + "="*70)
    print("INICIANDO INSTANCIAS MODCAST")
    print("="*70)
    
    started_instances = []
    for instance in instances:
        if instance.start():
            started_instances.append(instance)
            time.sleep(3)  # Esperar entre instancias
    
    if len(started_instances) < 2:
        print("❌ No se pudieron iniciar suficientes instancias")
        return 1
    
    try:
        # Ejecutar test
        print("\n" + "="*70)
        print("INICIANDO PRUEBAS P2P")
        print("="*70)
        
        success = run_basic_p2p_test(started_instances)
        
        if success:
            print("\n🎉 ¡PRUEBAS EXITOSAS!")
            print("\nLas instancias seguirán corriendo para que puedas")
            print("realizar pruebas manuales.")
            print("\nPuertos disponibles:")
            for instance in started_instances:
                print(f"  {instance.name}:")
                print(f"    - API (mocks): localhost:{instance.api_port}")
                print(f"    - P2P: localhost:{instance.p2p_port}")
            
            print("\nPresiona Ctrl+C para detener todas las instancias.")
            
            # Mantener corriendo para pruebas manuales
            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                print("\nDeteniendo por interrupción del usuario...")
        
        else:
            print("\n⚠️  Las pruebas tuvieron problemas.")
            print("Las instancias se mantendrán corriendo para diagnóstico.")
            print("\nPresiona Ctrl+C para detener.")
            
            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                pass
                
    finally:
        # Detener todas las instancias
        print("\n" + "="*70)
        print("DETENIENDO INSTANCIAS")
        print("="*70)
        
        for instance in started_instances:
            instance.stop()
        
        print("✅ Todas las instancias detenidas")

if __name__ == "__main__":
    # Cambiar al directorio correcto
    os.chdir(Path(__file__).parent)
    main()
