extends CanvasLayer

@onready var car_list = %CarList
@onready var resume_button = %ResumeButton

# Multiplayer UI elements
@onready var host_button = %HostButton
@onready var join_button = %JoinButton
@onready var connection_panel = %ConnectionPanel
@onready var ip_line_edit = %IPLineEdit
@onready var connect_button = %ConnectButton
@onready var lobby_panel = %LobbyPanel
@onready var player_list_container = %PlayerList
@onready var admin_controls = %AdminControls
@onready var start_game_button = %StartGameButton
@onready var disconnect_button = %DisconnectButton
@onready var status_label = %StatusLabel

var current_selected_car: String = ""
var car_buttons: Dictionary = {}

func _ready() -> void:
	visible = false
	populate_car_list()
	resume_button.pressed.connect(_on_resume_pressed)

	# Connect multiplayer button signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	connect_button.pressed.connect(_on_connect_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)

	# Connect NetworkManager signals
	NetworkManager.peer_connected.connect(_on_peer_joined)
	NetworkManager.peer_disconnected.connect(_on_peer_left)
	NetworkManager.player_list_updated.connect(_update_player_list)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.game_started.connect(_on_game_started)

	var saved_car = SaveManager.get_saved_car()
	if saved_car != "" and CarManager.car_exists(saved_car):
		current_selected_car = saved_car
		apply_car_selection(saved_car, false)
	else:
		var default_car = CarManager.get_default_car()
		if default_car != "":
			current_selected_car = default_car
			apply_car_selection(default_car, false)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()

func toggle_pause() -> void:
	visible = !visible

	# NEVER pause tree in multiplayer
	get_tree().paused = false

	if visible:
		populate_car_list()
		_update_multiplayer_ui()

func populate_car_list() -> void:
	for child in car_list.get_children():
		child.queue_free()
	car_buttons.clear()

	var car_names = CarManager.get_car_names()

	if car_names.is_empty():
		var label = Label.new()
		label.text = "No cars found in /cars folder"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		car_list.add_child(label)
		return

	for car_name in car_names:
		var button = Button.new()
		button.text = car_name.capitalize().replace("_", " ")
		button.pressed.connect(_on_car_selected.bind(car_name))
		car_list.add_child(button)
		car_buttons[car_name] = button

	update_selection_indicator()

func _on_car_selected(car_name: String) -> void:
	current_selected_car = car_name
	apply_car_selection(car_name, true)
	update_selection_indicator()

	# Sync car selection in multiplayer
	if NetworkManager.is_multiplayer_active:
		NetworkManager.broadcast_car_change(car_name)

func apply_car_selection(car_name: String, should_save: bool) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		push_error("Player node not found")
		return

	var car_node = player.get_node_or_null("Node3D/Car")
	if not car_node:
		push_error("Car node not found at Player/Node3D/Car")
		return

	for child in car_node.get_children():
		child.queue_free()

	var new_car = CarManager.load_car(car_name)
	if new_car:
		car_node.add_child(new_car)
		print("Car swapped to: ", car_name)

		if should_save:
			SaveManager.save_car_preference(car_name)
	else:
		push_error("Failed to load car: ", car_name)

func update_selection_indicator() -> void:
	for car_name in car_buttons.keys():
		var button = car_buttons[car_name]
		if car_name == current_selected_car:
			button.text = "✓ " + car_name.capitalize().replace("_", " ")
		else:
			button.text = car_name.capitalize().replace("_", " ")

func _on_resume_pressed() -> void:
	toggle_pause()

# === Multiplayer Functions ===

func _on_host_pressed() -> void:
	var player_name = "Player"  # Could get from settings
	status_label.text = "Creating server..."
	var result = await NetworkManager.host_game(player_name)

	if result == OK:
		status_label.text = "Hosting on port " + str(NetworkManager.DEFAULT_PORT) + ". Share your IP with players!"
		lobby_panel.visible = true
		admin_controls.visible = true
		host_button.disabled = true
		join_button.disabled = true
		_update_player_list()
	else:
		status_label.text = "Failed to host game"

func _on_join_pressed() -> void:
	connection_panel.visible = true
	status_label.text = "Enter host IP address"

func _on_connect_pressed() -> void:
	var host_ip = ip_line_edit.text.strip_edges()

	if host_ip.is_empty():
		status_label.text = "Please enter host IP"
		return

	var player_name = "Player"  # Could get from settings
	var result = await NetworkManager.join_game(host_ip, player_name)

	if result == OK:
		status_label.text = "Connecting to host..."
		connection_panel.visible = false
	else:
		status_label.text = "Failed to connect"

func _on_start_game_pressed() -> void:
	if not NetworkManager.is_host:
		return

	NetworkManager.start_game()
	status_label.text = "Starting game..."

func _on_disconnect_pressed() -> void:
	NetworkManager.disconnect_from_game()
	_reset_multiplayer_ui()
	status_label.text = "Disconnected"

func _on_peer_joined(peer_id: int) -> void:
	print("Peer joined UI update: ", peer_id)
	_update_player_list()

func _on_peer_left(peer_id: int) -> void:
	print("Peer left UI update: ", peer_id)
	_update_player_list()

func _on_connection_succeeded() -> void:
	status_label.text = "Connected!"
	lobby_panel.visible = true
	admin_controls.visible = false
	host_button.disabled = true
	join_button.disabled = true
	_update_player_list()

func _on_connection_failed(reason: String) -> void:
	status_label.text = "Connection failed: " + reason
	_reset_multiplayer_ui()

func _on_game_started() -> void:
	status_label.text = "Game started!"
	# Hide pause menu when game starts
	toggle_pause()

func _update_multiplayer_ui() -> void:
	if not NetworkManager.is_multiplayer_active:
		lobby_panel.visible = false
		connection_panel.visible = false
		host_button.disabled = false
		join_button.disabled = false
		status_label.text = ""
		return

	# Update based on connection state
	_update_player_list()

func _update_player_list() -> void:
	# Clear existing player list
	for child in player_list_container.get_children():
		child.queue_free()

	# Populate with connected players
	for peer_id in NetworkManager.connected_peers:
		var player_data = NetworkManager.get_player_data(peer_id)
		var label = Label.new()

		var player_text = player_data.get("player_name", "Unknown")
		var car_text = player_data.get("car_model", "No car")
		var is_host_text = " (Host)" if player_data.get("is_host", false) else ""

		label.text = "%s - %s%s" % [player_text, car_text, is_host_text]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_list_container.add_child(label)

func _reset_multiplayer_ui() -> void:
	lobby_panel.visible = false
	connection_panel.visible = false
	admin_controls.visible = false
	host_button.disabled = false
	join_button.disabled = false
	status_label.text = ""

	# Clear player list
	for child in player_list_container.get_children():
		child.queue_free()
