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


func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Get input from triggers (0 to 1 analog values)
	var accelerate_input = Input.get_action_strength("accelerate")
	var reverse_input = Input.get_action_strength("reverse")
	var steer = Input.get_axis("turn_left", "turn_right")

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
