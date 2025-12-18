No se prueban realmente las transferencias reales de archivos con los tests que hay ya que estan los dos clientes 
compartiendo la misma carpeta de mods. Habría que hacer algo como esto para poder generar diferentes instancias
y carpetas

# 1. Múltiples instancias de Modcast
cd modcast
MODCAST_P2P_PORT=4040 iex -S mix  # Terminal 1: Player1
MODCAST_P2P_PORT=4041 iex -S mix  # Terminal 2: Player2

# 2. Múltiples carpetas de mods
mkdir -p mods_player1 mods_player2
# Copiar mods diferentes a cada carpeta

# 3. Conectar mocks a diferentes puertos
python test.py --name Player1 --port 5050
python test.py --name Player2 --port 5051
