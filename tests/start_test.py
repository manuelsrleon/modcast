#!/usr/bin/env python3
"""
Script para lanzar múltiples clientes de prueba en diferentes terminales.
"""

import subprocess
import sys
import time
import os

def start_client(name, session="test_session"):
    """Lanza un cliente en una nueva terminal"""
    import platform
    
    cmd = [
        sys.executable, "test_mocks/mock_client.py",
        "--name", name,
        "--session", session
    ]
    
    if platform.system() == "Windows":
        cmd = ["start", "cmd", "/k"] + cmd
    elif platform.system() == "Darwin":  # macOS
        cmd = ["osascript", "-e", f'tell app "Terminal" to do script "{" ".join(cmd)}"']
    else:  # Linux/Unix
        cmd = ["xterm", "-e"] + cmd + ["&"]
    
    print(f"Lanzando cliente: {name}")
    subprocess.Popen(cmd, shell=False)

def main():
    """Menú principal"""
    print("=== Sistema de Prueba Modcast ===")
    print()
    print("1. Lanzar host (jugador 1)")
    print("2. Lanzar cliente 2")
    print("3. Lanzar cliente 3")
    print("4. Lanzar todos los clientes")
    print("5. Limpiar mods descargados")
    print("0. Salir")
    
    while True:
        choice = input("\nSelecciona opción: ").strip()
        
        if choice == "1":
            start_client("Player1")
            print("Host lanzado como Player1")
            
        elif choice == "2":
            start_client("Player2")
            print("Cliente 2 lanzado como Player2")
            
        elif choice == "3":
            start_client("Player3")
            print("Cliente 3 lanzado como Player3")
            
        elif choice == "4":
            start_client("Player1")
            time.sleep(1)
            start_client("Player2")
            time.sleep(1)
            start_client("Player3")
            print("Todos los clientes lanzados")
            
        elif choice == "5":
            import shutil
            if os.path.exists("mods"):
                shutil.rmtree("mods")
                os.makedirs("mods")
                print("Carpeta mods limpiada")
            else:
                print("No existe carpeta mods")
                
        elif choice == "0":
            break
            
        else:
            print("Opción no válida")

if __name__ == "__main__":
    main()
