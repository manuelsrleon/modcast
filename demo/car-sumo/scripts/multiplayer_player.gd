extends CharacterBody3D

# Player identification
var peer_id: int = -1
var player_name: String = ""
var car_model: String = ""

# Car physics state (synced from host)
var current_speed: float = 0.0
var steering_angle: float = 0.0

# Synced properties (managed by MultiplayerSynchronizer)
@export var synced_position: Vector3 = Vector3.ZERO
@export var synced_rotation: Vector3 = Vector3.ZERO
@export var synced_speed: float = 0.0
@export var synced_steering: float = 0.0

# References
@onready var car_node: Node3D = $Node3D/Car
@onready var name_label: Label3D = $NameLabel

# Interpolation settings
const INTERPOLATION_SPEED: float = 0.3

func _ready() -> void:
	# Set player name label
	if name_label:
		name_label.text = player_name

	# Set multiplayer authority to the peer that owns this player
	if peer_id > 0:
		set_multiplayer_authority(peer_id)

# Load car model for this player
func load_car_model(model_name: String) -> void:
	# Clear existing car
	for child in car_node.get_children():
		child.queue_free()

	# Load new car from CarManager
	var new_car = CarManager.load_car(model_name)
	if new_car:
		car_node.add_child(new_car)
		car_model = model_name
		print("Loaded car model for player ", player_name, ": ", model_name)
	else:
		push_error("Failed to load car model: ", model_name)

# Apply state from network sync
func apply_state(state: Dictionary) -> void:
	if state.has("position"):
		synced_position = state.position
	if state.has("rotation"):
		synced_rotation = state.rotation
	if state.has("current_speed"):
		synced_speed = state.current_speed
	if state.has("steering_angle"):
		synced_steering = state.steering_angle

# Physics process - interpolate to synced state
func _physics_process(delta: float) -> void:
	# Remote player - always interpolate to synced state
	# Interpolate position and rotation smoothly
	position = position.lerp(synced_position, INTERPOLATION_SPEED)
	rotation = rotation.lerp(synced_rotation, INTERPOLATION_SPEED)

	# Update local state
	current_speed = lerpf(current_speed, synced_speed, INTERPOLATION_SPEED)
	steering_angle = lerpf(steering_angle, synced_steering, INTERPOLATION_SPEED)

# Update synced properties (called by host)
func update_sync_properties(pos: Vector3, rot: Vector3, speed: float, steer: float) -> void:
	synced_position = pos
	synced_rotation = rot
	synced_speed = speed
	synced_steering = steer

# Play collision effect
func play_collision_effect(collision_point: Vector3, collision_normal: Vector3) -> void:
	# TODO: Add visual/audio effects for collision
	print("Player ", player_name, " collided at ", collision_point)

# Play jump effect
func play_jump_effect() -> void:
	# TODO: Add visual/audio effects for jump
	print("Player ", player_name, " jumped")
