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
	# Check if we have local authority
	if NetworkManager.is_multiplayer_active:
		is_local_authority = NetworkManager.is_host

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Get input from triggers (0 to 1 analog values)
	var accelerate_input = Input.get_action_strength("accelerate")
	var reverse_input = Input.get_action_strength("reverse")
	var steer = Input.get_axis("turn_left", "turn_right")

	# Check if multiplayer is active and we're a client
	if NetworkManager.is_multiplayer_active and not is_local_authority:
		# Client: send input to host instead of processing locally
		_send_input_to_host(accelerate_input, reverse_input, steer, delta)
		return  # Don't process physics locally

	# Process physics (single-player or host)
	_process_physics(accelerate_input, reverse_input, steer, delta)

	# If multiplayer host, update NetworkManager with our state
	if NetworkManager.is_multiplayer_active and is_local_authority:
		NetworkManager.update_local_player_data({
			"position": position,
			"rotation": rotation,
			"current_speed": current_speed,
			"steering_angle": steering_angle,
			"velocity": velocity
		})

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

	# Check for events (only if we have authority to avoid duplicates)
	if is_local_authority or not NetworkManager.is_multiplayer_active:
		_check_jump_event()
		_check_collision_events()

# Send input to host (client only)
func _send_input_to_host(accelerate: float, reverse: float, steer: float, delta: float) -> void:
	# Store last input
	last_input = {
		"accelerate": accelerate,
		"reverse": reverse,
		"steer": steer,
		"delta": delta
	}

	# Send to host via RPC (unreliable for frequent updates)
	rpc_id(1, "receive_client_input", accelerate, reverse, steer, delta)

# Host receives client input
@rpc("unreliable", "any_peer")
func receive_client_input(accelerate: float, reverse: float, steer: float, delta: float) -> void:
	# Only host processes this
	if not NetworkManager.is_host:
		return

	# Process physics for this client
	_process_physics(accelerate, reverse, steer, delta)

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
