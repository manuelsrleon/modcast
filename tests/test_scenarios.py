#!/usr/bin/env python3
"""
Escenarios de prueba automatizados para Modcast.
"""

import time
import json
import socket
import threading

def test_scenario_1():
    """Escenario 1: Sesión básica con transferencia de mods"""
    print("\n=== Escenario 1: Sesión básica ===")
    
    steps = [
        "1. Player1 (host) inicia sesión",
        "2. Player2 se une a la sesión",
        "3. Player1 anuncia mods requeridos: [hash1, hash2]",
        "4. Player2 anuncia mods requeridos: [hash2, hash3]",
        "5. Player1 inicia el juego"
    ]
    
    for step in steps:
        print(step)
        time.sleep(0.5)
    
    print("\nPara ejecutar manualmente:")
    print("1. En terminal 1: python mock_client.py --name Player1")
    print("   Comando: h (hostear)")
    print("2. En terminal 2: python mock_client.py --name Player2")
    print("   Comando: j (unirse) -> IP: 127.0.0.1")
    print("3. En Player1: a -> hashes: hash1,hash2")
    print("4. En Player2: a -> hashes: hash2,hash3")
    print("5. En Player1: start")

def test_scenario_2():
    """Escenario 2: Transferencia de entidades"""
    print("\n=== Escenario 2: Transferencia de entidades ===")
    
    steps = [
        "1. Player1 crea una entidad con un mod",
        "2. Player1 transfiere la entidad a Player2",
        "3. Verificar que Player2 recibe el evento"
    ]
    
    for step in steps:
        print(step)
        time.sleep(0.5)
    
    print("\nPara ejecutar manualmente:")
    print("1. Conectar Player1 y Player2")
    print("2. En Player1: r -> entity: car1, asset: sports_car, hash: test_hash")
    print("3. En Player1: t -> entity: car1, new_player: Player2")

def test_scenario_3():
    """Escenario 3: Mods faltantes"""
    print("\n=== Escenario 3: Mods faltantes ===")
    
    steps = [
        "1. Player1 tiene mods: [hashA, hashB]",
        "2. Player2 anuncia requeridos: [hashB, hashC]",
        "3. Verificar que hashB se transfiere, hashC marca error"
    ]
    
    for step in steps:
        print(step)
        time.sleep(0.5)

def create_test_mods():
    """Crea archivos .zip de prueba y muestra sus hashes"""
    print("\n=== Crear mods de prueba ===")
    
    import hashlib
    import os
    
    os.makedirs("../mods", exist_ok=True)
    
    test_mods = [
        ("car_red.zip", b"red_car_model_data_v1"),
        ("car_blue.zip", b"blue_car_model_data_v1"),
        ("weapon_laser.zip", b"laser_weapon_data_v1"),
    ]
    
    print("Creando mods de prueba...")
    for filename, content in test_mods:
        path = os.path.join("test_mocks/mod_files", filename)
        with open(path, 'wb') as f:
            f.write(content)
        
        # Calcular hash
        file_hash = hashlib.md5(content).hexdigest()
        print(f"  {filename}: {file_hash}")
    
    print("\nUsa estos hashes en los comandos 'announce_required_mods'")

def main():
    """Menú de escenarios de prueba"""
    print("=== Escenarios de Prueba Modcast ===")
    print()
    print("1. Sesión básica con transferencia de mods")
    print("2. Transferencia de entidades")
    print("3. Mods faltantes")
    print("4. Crear mods de prueba con hashes reales")
    print("0. Salir")
    
    while True:
        choice = input("\nSelecciona escenario: ").strip()
        
        if choice == "1":
            test_scenario_1()
        elif choice == "2":
            test_scenario_2()
        elif choice == "3":
            test_scenario_3()
        elif choice == "4":
            create_test_mods()
        elif choice == "0":
            break
        else:
            print("Opción no válida")

if __name__ == "__main__":
    main()
