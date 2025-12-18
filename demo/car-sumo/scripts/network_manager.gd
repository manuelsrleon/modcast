extends Node

# Signals
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal game_started()
signal host_migrated(new_host_id: int)
signal connection_succeeded()
signal player_list_updated()

# Network peer (using WebRTC for P2P multiplayer)
var webrtc_peer: WebRTCMultiplayerPeer = null

# Connected players data
var connected_peers: Dictionary = {}  # peer_id -> player_data

# Network state
var is_host: bool = false
var is_multiplayer_active: bool = false
var current_host_id: int = 1
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
	webrtc_peer = WebRTCMultiplayerPeer.new()

	# Create as server
	var err = webrtc_peer.create_server()
	if err != OK:
		push_error("Failed to create WebRTC server: ", err)
		return err

	# Set as multiplayer peer
	multiplayer.multiplayer_peer = webrtc_peer

	is_host = true
	is_multiplayer_active = true
	current_host_id = 1
	local_player_name = player_name

	# Add self to connected peers
	connected_peers[1] = {
		"peer_id": 1,
		"player_name": player_name,
		"car_model": SaveManager.get_saved_car(),
		"is_host": true,
		"is_ready": false,
		"position": Vector3.ZERO,
		"rotation": Vector3.ZERO,
		"velocity": Vector3.ZERO,
		"steering_angle": 0.0,
		"current_speed": 0.0
	}

	print("Hosting game as: ", player_name)
	player_list_updated.emit()

	return OK

# Join a game
func join_game(host_ip: String, player_name: String) -> Error:
	webrtc_peer = WebRTCMultiplayerPeer.new()

	# Create as client - peer_id 1 is reserved for the host
	var err = webrtc_peer.create_client(1)
	if err != OK:
		push_error("Failed to create WebRTC client: ", err)
		return err

	# Add peer connection for the host
	# Note: In a real implementation with signaling, this would be handled differently
	# For now, we'll use a simplified direct connection approach

	# Set as multiplayer peer
	multiplayer.multiplayer_peer = webrtc_peer

	is_host = false
	is_multiplayer_active = true
	current_host_id = 1
	local_player_name = player_name

	print("Attempting to join game as: ", player_name)

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
		webrtc_peer = null

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

# === RPC Methods ===

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
		"is_ready": false,
		"position": Vector3.ZERO,
		"rotation": Vector3.ZERO,
		"velocity": Vector3.ZERO,
		"steering_angle": 0.0,
		"current_speed": 0.0
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

	if is_host:
		# Host broadcasts directly
		rpc("change_car_model", my_id, car_model)
	else:
		# Client requests host to broadcast
		rpc_id(1, "request_car_change", my_id, car_model)

# Client requests car change
@rpc("reliable", "any_peer")
func request_car_change(peer_id: int, car_model: String) -> void:
	if not is_host:
		return

	# Validate car exists
	if not CarManager.car_exists(car_model):
		push_error("Invalid car model: ", car_model)
		return

	# Broadcast to all
	rpc("change_car_model", peer_id, car_model)

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

	# Check if host disconnected
	if peer_id == current_host_id and not is_host:
		print("Host disconnected! Initiating host migration...")
		_initiate_host_migration()

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
	webrtc_peer = null

func _on_server_disconnected() -> void:
	print("Disconnected from server")

	# Host disconnected, initiate migration
	_initiate_host_migration()

# === Host Migration ===

func _initiate_host_migration() -> void:
	if connected_peers.size() <= 1:
		print("No other players, returning to single-player")
		disconnect_from_game()
		return

	# Find player with lowest peer_id (excluding disconnected host)
	var new_host_id = -1
	for peer_id in connected_peers.keys():
		if peer_id != current_host_id:
			if new_host_id == -1 or peer_id < new_host_id:
				new_host_id = peer_id

	if new_host_id == -1:
		push_error("Failed to find new host")
		disconnect_from_game()
		return

	print("New host elected: ", new_host_id)
	current_host_id = new_host_id

	# Check if we're the new host
	if multiplayer.get_unique_id() == new_host_id:
		_become_host()

	# Broadcast host migration
	host_migrated.emit(new_host_id)

func _become_host() -> void:
	print("Becoming new host...")
	is_host = true
	current_host_id = multiplayer.get_unique_id()

	# Update our player data
	if connected_peers.has(current_host_id):
		connected_peers[current_host_id].is_host = true

	# Recreate WebRTC peer as server
	# Note: This is a simplified migration. In production, you'd need more sophisticated handling
	print("Host migration complete")
