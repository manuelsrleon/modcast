#!/usr/bin/env python3
"""
Script para limpiar carpetas de mods de prueba
"""

import os
import shutil
import sys

def cleanup_test_mods(base_folder="test_mods", confirm=True):
    """Limpia todas las carpetas de mods de prueba"""
    
    if not os.path.exists(base_folder):
        print(f"✓ No existe la carpeta {base_folder}, nada que limpiar")
        return
    
    # Contar archivos
    total_files = 0
    total_size = 0
    
    for root, dirs, files in os.walk(base_folder):
        for file in files:
            filepath = os.path.join(root, file)
            total_files += 1
            total_size += os.path.getsize(filepath)
    
    size_mb = total_size / (1024 * 1024)
    
    print(f"\n📁 Carpeta: {base_folder}")
    print(f"📄 Archivos: {total_files}")
    print(f"💾 Tamaño total: {size_mb:.2f} MB")
    
    if confirm:
        response = input("\n¿Eliminar todo? (s/N): ").strip().lower()
        if response != 's':
            print("Cancelado")
            return False
    
    try:
        shutil.rmtree(base_folder)
        print(f"\n✓ Carpeta {base_folder} eliminada correctamente")
        return True
    except Exception as e:
        print(f"\n✗ Error eliminando carpeta: {e}")
        return False


def list_test_sessions(base_folder="test_mods"):
    """Lista todas las sesiones de prueba"""
    
    if not os.path.exists(base_folder):
        print(f"No existe la carpeta {base_folder}")
        return
    
    print(f"\n=== Sesiones de prueba en {base_folder} ===\n")
    
    clients = os.listdir(base_folder)
    
    if not clients:
        print("No hay sesiones de prueba")
        return
    
    for client in sorted(clients):
        client_path = os.path.join(base_folder, client)
        if os.path.isdir(client_path):
            sessions = os.listdir(client_path)
            print(f"📱 Cliente: {client}")
            for session in sorted(sessions):
                session_path = os.path.join(client_path, session)
                if os.path.isdir(session_path):
                    files = os.listdir(session_path)
                    num_mods = len([f for f in files if f.endswith('.zip')])
                    print(f"   └─ Sesión: {session} ({num_mods} mods)")


def cleanup_old_sessions(base_folder="test_mods", keep_recent=0):
    """Limpia sesiones antiguas, manteniendo las N más recientes"""
    
    if not os.path.exists(base_folder):
        print(f"No existe la carpeta {base_folder}")
        return
    
    # Recolectar todas las sesiones con sus tiempos de creación
    sessions = []
    
    for client in os.listdir(base_folder):
        client_path = os.path.join(base_folder, client)
        if os.path.isdir(client_path):
            for session in os.listdir(client_path):
                session_path = os.path.join(client_path, session)
                if os.path.isdir(session_path):
                    mtime = os.path.getmtime(session_path)
                    sessions.append((mtime, session_path, client, session))
    
    # Ordenar por tiempo (más reciente primero)
    sessions.sort(reverse=True)
    
    if len(sessions) <= keep_recent:
        print(f"✓ Solo hay {len(sessions)} sesiones, nada que limpiar")
        return
    
    # Sesiones a eliminar
    to_delete = sessions[keep_recent:]
    
    print(f"\n🗑️  Eliminando {len(to_delete)} sesiones antiguas:")
    for _, path, client, session in to_delete:
        print(f"   - {client}/{session}")
    
    response = input("\n¿Continuar? (s/N): ").strip().lower()
    if response != 's':
        print("Cancelado")
        return
    
    for _, path, _, _ in to_delete:
        try:
            shutil.rmtree(path)
            print(f"✓ Eliminado: {path}")
        except Exception as e:
            print(f"✗ Error eliminando {path}: {e}")


def main():
    """Menú principal"""
    print("=== LIMPIEZA DE MODS DE PRUEBA ===\n")
    print("1. Listar sesiones de prueba")
    print("2. Eliminar todas las sesiones")
    print("3. Eliminar sesiones antiguas (mantener 3 recientes)")
    print("4. Eliminar carpeta test_mods completa")
    print("0. Salir\n")
    
    choice = input("Selecciona opción: ").strip()
    
    if choice == "1":
        list_test_sessions()
    elif choice == "2":
        cleanup_test_mods(confirm=True)
    elif choice == "3":
        cleanup_old_sessions(keep_recent=3)
    elif choice == "4":
        cleanup_test_mods(confirm=True)


if __name__ == "__main__":
    main()
