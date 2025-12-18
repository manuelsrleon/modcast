extends Node

# Signals
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal game_started()
signal connection_succeeded()
signal player_list_updated()

# Network peer (simple ENet for client-server)
var peer: ENetMultiplayerPeer = null

# Connected players data
var connected_peers: Dictionary = {}  # peer_id -> player_data

# Network state
var is_host: bool = false
var is_multiplayer_active: bool = false
var local_player_name: String = "Player"

# Network settings
const DEFAULT_PORT: int = 7654
const MAX_CLIENTS: int = 8

func _ready() -> void:
	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# Host a game
func host_game(player_name: String) -> Error:
	print(">>> host_game() called for player: ", player_name)

	# Create ENet server
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if err != OK:
		print("ERROR: Failed to create server: ", err)
		connection_failed.emit("Failed to create server")
		return err

	# Set as multiplayer peer
	multiplayer.multiplayer_peer = peer

	is_host = true
	is_multiplayer_active = true
	local_player_name = player_name

	# Add self to connected peers
	connected_peers[1] = {
		"peer_id": 1,
		"player_name": player_name,
		"car_model": SaveManager.get_saved_car(),
		"is_host": true,
		"is_ready": false
	}

	print("✓ Hosting game on port ", DEFAULT_PORT, " as: ", player_name)
	player_list_updated.emit()

	return OK

# Join a game
func join_game(host_ip: String, player_name: String) -> Error:
	print(">>> join_game() called for player: ", player_name, " connecting to: ", host_ip)

	# Create ENet client
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(host_ip, DEFAULT_PORT)
	if err != OK:
		print("ERROR: Failed to create client: ", err)
		connection_failed.emit("Failed to connect to server")
		return err

	# Set as multiplayer peer
	multiplayer.multiplayer_peer = peer

	is_host = false
	is_multiplayer_active = true
	local_player_name = player_name

	print("Attempting to join game at: ", host_ip, ":", DEFAULT_PORT)

	return OK

# Disconnect from current game
func disconnect_from_game() -> void:
	if is_multiplayer_active:
		if is_host:
			# Notify all peers that host is leaving
			rpc("player_left", 1)
		else:
			# Notify host that we're leaving
			rpc_id(1, "player_left", multiplayer.get_unique_id())

		# Clear multiplayer peer
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null

		# Reset state
		connected_peers.clear()
		is_host = false
		is_multiplayer_active = false
		peer = null

		print("Disconnected from game")

# Get player data
func get_player_data(peer_id: int) -> Dictionary:
	return connected_peers.get(peer_id, {})

# Check if current player is host
func is_current_host() -> bool:
	return is_host and is_multiplayer_active

# Update local player data
func update_local_player_data(data: Dictionary) -> void:
	var my_id = multiplayer.get_unique_id()
	if connected_peers.has(my_id):
		for key in data.keys():
			connected_peers[my_id][key] = data[key]

		# Broadcast state to all other players
		rpc("sync_player_state", my_id, data)

# === RPC Methods ===

# Sync player state from any player to all others
@rpc("unreliable", "any_peer")
func sync_player_state(peer_id: int, state: Dictionary) -> void:
	# Update connected peers data
	if connected_peers.has(peer_id):
		for key in state.keys():
			connected_peers[peer_id][key] = state[key]

# Client registers with host when joining
@rpc("reliable", "any_peer")
func register_player(player_name: String, car_model: String) -> void:
	if not is_host:
		return

	var peer_id = multiplayer.get_remote_sender_id()

	# Add player to connected peers
	connected_peers[peer_id] = {
		"peer_id": peer_id,
		"player_name": player_name,
		"car_model": car_model,
		"is_host": false,
		"is_ready": false
	}

	print("Player registered: ", player_name, " (", peer_id, ")")

	# Send current player list to new player
	rpc_id(peer_id, "sync_player_list", connected_peers)

	# Broadcast new player to all other peers
	rpc("player_joined", peer_id, connected_peers[peer_id])

	player_list_updated.emit()

# Broadcast player joined
@rpc("reliable", "call_local")
func player_joined(peer_id: int, player_data: Dictionary) -> void:
	if peer_id == multiplayer.get_unique_id():
		return  # Don't add ourselves

	connected_peers[peer_id] = player_data
	print("Player joined: ", player_data.player_name, " (", peer_id, ")")
	peer_connected.emit(peer_id)
	player_list_updated.emit()

# Broadcast player left
@rpc("reliable", "call_local")
func player_left(peer_id: int) -> void:
	if connected_peers.has(peer_id):
		var player_name = connected_peers[peer_id].player_name
		connected_peers.erase(peer_id)
		print("Player left: ", player_name, " (", peer_id, ")")
		peer_disconnected.emit(peer_id)
		player_list_updated.emit()

# Sync full player list (sent to new joiner)
@rpc("reliable")
func sync_player_list(players: Dictionary) -> void:
	connected_peers = players
	print("Received player list: ", players.size(), " players")
	player_list_updated.emit()

# Car selection sync
@rpc("reliable", "call_local")
func change_car_model(peer_id: int, car_model: String) -> void:
	if connected_peers.has(peer_id):
		connected_peers[peer_id].car_model = car_model
		print("Player ", peer_id, " changed car to: ", car_model)
		player_list_updated.emit()

# Broadcast car change
func broadcast_car_change(car_model: String) -> void:
	if not is_multiplayer_active:
		return

	var my_id = multiplayer.get_unique_id()

	# Update local data
	if connected_peers.has(my_id):
		connected_peers[my_id].car_model = car_model

	# Broadcast to everyone
	rpc("change_car_model", my_id, car_model)

# === Admin Functions (Host Only) ===

# Start the game (host only)
func start_game() -> void:
	if not is_host:
		push_error("Only host can start the game")
		return

	print("Host starting game...")
	rpc("game_started_broadcast")

@rpc("reliable", "call_local")
func game_started_broadcast() -> void:
	print("Game started!")
	game_started.emit()

# Kick a player (host only)
func kick_peer(peer_id: int) -> void:
	if not is_host:
		push_error("Only host can kick players")
		return

	if peer_id == 1:
		push_error("Cannot kick host")
		return

	print("Kicking player: ", peer_id)
	multiplayer.disconnect_peer(peer_id)

# === Signal Handlers ===

func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: ", peer_id)

	# If we're not the host, register with the host
	if not is_host and peer_id == 1:
		# Wait a frame for connection to stabilize
		await get_tree().process_frame
		rpc_id(1, "register_player", local_player_name, SaveManager.get_saved_car())

func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: ", peer_id)

	# Remove from connected peers
	if connected_peers.has(peer_id):
		player_left(peer_id)

func _on_connected_to_server() -> void:
	print("Successfully connected to host!")
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("Failed to connect to host")
	connection_failed.emit("Connection failed")

	# Reset state
	is_multiplayer_active = false
	is_host = false
	peer = null

func _on_server_disconnected() -> void:
	print("Host disconnected!")
	connection_failed.emit("Host disconnected")
	disconnect_from_game()
