extends CharacterBody3D

# Car physics constants
const MAX_SPEED = 20.0
const ACCELERATION = 8.0
const DECELERATION = 10.0
const BRAKE_STRENGTH = 15.0
const TURN_SPEED = 4.0
const MIN_TURN_SPEED = 1.0

# Current car state
var current_speed = 0.0
var steering_angle = 0.0

# Multiplayer
var is_local_authority: bool = true
var last_input: Dictionary = {}

# Event tracking
var was_on_floor: bool = false


func _ready() -> void:
	# Everyone has authority over their own player
	is_local_authority = true

	# Set this as the local player's group
	add_to_group("local_player")
	print("Local player ready at position: ", position)

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Get input from triggers (0 to 1 analog values)
	var accelerate_input = Input.get_action_strength("accelerate")
	var reverse_input = Input.get_action_strength("reverse")
	var steer = Input.get_axis("turn_left", "turn_right")

	# ONLY process physics if we have input (local control)
	_process_physics(accelerate_input, reverse_input, steer, delta)

	# If multiplayer active, broadcast our state to everyone
	if NetworkManager.is_multiplayer_active:
		var my_id = multiplayer.get_unique_id()
		NetworkManager.update_local_player_data({
			"position": position,
			"rotation": rotation,
			"current_speed": current_speed,
			"steering_angle": steering_angle,
			"velocity": velocity
		})
		#print("Broadcasting position from peer ", my_id, ": ", position)

# Process physics (used by single-player, host, and host processing client input)
func _process_physics(accelerate_input: float, reverse_input: float, steer: float, delta: float) -> void:
	# Handle acceleration and deceleration
	if accelerate_input > 0:
		# RT trigger pressed - accelerating forward
		current_speed = move_toward(current_speed, MAX_SPEED * accelerate_input, ACCELERATION * delta)
	elif reverse_input > 0:
		# LT trigger pressed - braking or reversing
		if current_speed > 0:
			# Braking
			current_speed = move_toward(current_speed, 0, BRAKE_STRENGTH * reverse_input * delta)
		else:
			# Reversing
			current_speed = move_toward(current_speed, -MAX_SPEED * 0.5 * reverse_input, ACCELERATION * 0.5 * delta)
	else:
		# Natural deceleration when no input
		current_speed = move_toward(current_speed, 0, DECELERATION * delta)

	# Handle steering - only turn when moving
	if abs(current_speed) > MIN_TURN_SPEED:
		steering_angle = -(steer * TURN_SPEED)
		rotate_y(steering_angle * delta * (current_speed / MAX_SPEED))

	# Apply movement in the direction the car is facing
	var forward_direction = transform.basis.z
	velocity.x = forward_direction.x * current_speed
	velocity.z = forward_direction.z * current_speed

	move_and_slide()

	# Check for events
	_check_jump_event()
	_check_collision_events()

# === Game Events ===

# Check for jump (landing detection)
func _check_jump_event() -> void:
	# Detect landing (was in air, now on floor)
	if not was_on_floor and is_on_floor():
		if NetworkManager.is_multiplayer_active:
			rpc("broadcast_jump_event")

	was_on_floor = is_on_floor()

# Check for collisions
func _check_collision_events() -> void:
	# Check if we collided with something
	if get_slide_collision_count() > 0:
		var collision = get_slide_collision(0)
		if NetworkManager.is_multiplayer_active and collision:
			var collision_point = collision.get_position()
			var collision_normal = collision.get_normal()
			rpc("broadcast_collision_event", collision_point, collision_normal)

# Broadcast jump event to all players
@rpc("reliable", "call_local")
func broadcast_jump_event() -> void:
	# Play jump effect (can be extended with particles, sounds, etc.)
	print("Player jumped!")
	# TODO: Add visual/audio effects

# Broadcast collision event to all players
@rpc("reliable", "call_local")
func broadcast_collision_event(collision_point: Vector3, collision_normal: Vector3) -> void:
	# Play collision effect (can be extended with particles, sounds, etc.)
	print("Player collided at: ", collision_point, " with normal: ", collision_normal)
	# TODO: Add visual/audio effects
