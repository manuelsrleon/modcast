extends Node3D

# Preload the multiplayer player scene
var multiplayer_player_scene = preload("res://multiplayer_player.tscn")

# Spawn points for players
@onready var spawn_points: Node3D = $SpawnPoints

# Track spawned remote players
var remote_players: Dictionary = {}  # peer_id -> MultiplayerPlayer node

# Spawn point positions (will be filled from spawn_points children)
var spawn_positions: Array[Vector3] = []

func _ready() -> void:
	# Collect spawn point positions
	if spawn_points:
		for spawn_point in spawn_points.get_children():
			if spawn_point is Node3D:
				spawn_positions.append(spawn_point.position)

	# If no spawn points, create default ones
	if spawn_positions.is_empty():
		spawn_positions = [
			Vector3(0, 1.5, 0),
			Vector3(5, 1.5, 0),
			Vector3(-5, 1.5, 0),
			Vector3(10, 1.5, 0),
			Vector3(-10, 1.5, 0),
			Vector3(0, 1.5, 5),
			Vector3(5, 1.5, 5),
			Vector3(-5, 1.5, 5)
		]

	# Connect to NetworkManager signals
	if NetworkManager:
		NetworkManager.peer_connected.connect(_on_peer_connected)
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
		NetworkManager.game_started.connect(_on_game_started)
		NetworkManager.connection_succeeded.connect(_on_multiplayer_started)
		NetworkManager.player_list_updated.connect(_on_player_list_updated)

		# If multiplayer is already active, setup positions
		if NetworkManager.is_multiplayer_active:
			_setup_local_player_position()
			_spawn_all_existing_players()

func _on_multiplayer_started() -> void:
	print("Main: Multiplayer connection established")
	_setup_local_player_position()

func _setup_local_player_position() -> void:
	# Position local player at their spawn point
	var local_player = get_tree().get_first_node_in_group("player")
	if local_player:
		var my_id = multiplayer.get_unique_id()
		var spawn_index = (my_id - 1) % spawn_positions.size()
		local_player.position = spawn_positions[spawn_index]
		print("Positioned local player at: ", local_player.position)

func _on_peer_connected(peer_id: int) -> void:
	print("Main: Peer connected: ", peer_id)

	# Always spawn remote player for any other peer
	var my_id = multiplayer.get_unique_id()
	if peer_id != my_id:
		# Wait a frame to ensure player data is synced
		await get_tree().process_frame
		_spawn_remote_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("Main: Peer disconnected, despawning player: ", peer_id)
	_despawn_remote_player(peer_id)

func _on_game_started() -> void:
	print("Main: Game started!")
	# Game start logic here (e.g., enable car controls, start countdown, etc.)

func _on_player_list_updated() -> void:
	# Spawn any new players that aren't spawned yet
	var my_id = multiplayer.get_unique_id()
	for peer_id in NetworkManager.connected_peers.keys():
		if peer_id != my_id and not remote_players.has(peer_id):
			_spawn_remote_player(peer_id)

func _spawn_all_existing_players() -> void:
	# Spawn all players that are already in the session
	for peer_id in NetworkManager.connected_peers.keys():
		# Don't spawn ourselves
		if peer_id != multiplayer.get_unique_id():
			_spawn_remote_player(peer_id)

func _spawn_remote_player(peer_id: int) -> void:
	# Check if player already spawned
	if remote_players.has(peer_id):
		push_warning("Player ", peer_id, " already spawned")
		return

	# Get player data from NetworkManager
	var player_data = NetworkManager.get_player_data(peer_id)
	if player_data.is_empty():
		push_error("No player data for peer: ", peer_id)
		return

	# Instantiate multiplayer player
	var remote_player = multiplayer_player_scene.instantiate()
	remote_player.peer_id = peer_id
	remote_player.player_name = player_data.get("player_name", "Player")
	remote_player.car_model = player_data.get("car_model", "")
	remote_player.name = "RemotePlayer_%d" % peer_id

	# Set spawn position (use peer_id to determine spawn point)
	var spawn_index = (peer_id - 1) % spawn_positions.size()
	remote_player.position = spawn_positions[spawn_index]

	# Add to scene
	add_child(remote_player)

	# Load car model
	if not remote_player.car_model.is_empty():
		remote_player.load_car_model(remote_player.car_model)

	# Track spawned player
	remote_players[peer_id] = remote_player

	print("✓ Spawned REMOTE player for peer ", peer_id, " (", remote_player.player_name, ") at position ", remote_player.position)

func _despawn_remote_player(peer_id: int) -> void:
	if not remote_players.has(peer_id):
		return

	var player_node = remote_players[peer_id]
	remote_players.erase(peer_id)

	if is_instance_valid(player_node):
		player_node.queue_free()

	print("Despawned remote player: ", peer_id)

# Called from NetworkManager when a remote player changes car
func update_remote_player_car(peer_id: int, car_model: String) -> void:
	if not remote_players.has(peer_id):
		return

	var remote_player = remote_players[peer_id]
	remote_player.load_car_model(car_model)

# Physics process to update remote player states
func _physics_process(delta: float) -> void:
	if not NetworkManager.is_multiplayer_active:
		return

	# Update remote player states from NetworkManager data
	for peer_id in remote_players.keys():
		var remote_player = remote_players[peer_id]
		var player_data = NetworkManager.get_player_data(peer_id)

		if not player_data.is_empty() and is_instance_valid(remote_player):
			# Update synced properties
			var new_pos = player_data.get("position", remote_player.position)
			remote_player.synced_position = new_pos
			remote_player.synced_rotation = player_data.get("rotation", remote_player.rotation)
			remote_player.synced_speed = player_data.get("current_speed", 0.0)
			remote_player.synced_steering = player_data.get("steering_angle", 0.0)

			# Debug: print occasionally
			if Engine.get_physics_frames() % 60 == 0:  # Every 60 physics frames
				print("Updating remote player ", peer_id, " to position: ", new_pos)
