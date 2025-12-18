extends CanvasLayer

@onready var speed_label = %SpeedLabel
@onready var car_name_label = %CarNameLabel
@onready var instructions_panel = %InstructionsPanel

var player: CharacterBody3D

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	var saved_car = SaveManager.get_saved_car()
	if saved_car != "":
		car_name_label.text = "Car: " + saved_car.capitalize().replace("_", " ")
	else:
		car_name_label.text = "Car: Race"
	
	# Hide instructions after 5 seconds
	await get_tree().create_timer(5.0).timeout
	if instructions_panel:
		var tween = create_tween()
		tween.tween_property(instructions_panel, "modulate:a", 0.0, 0.5)
		tween.tween_callback(instructions_panel.hide)

func _process(_delta: float) -> void:
	if player:
		var speed = abs(player.current_speed)
		var speed_kmh = speed * 10  # Approximate conversion to km/h for display
		speed_label.text = "%d km/h" % speed_kmh
		
		# Color code the speed
		if speed_kmh > 150:
			speed_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))  # Red
		elif speed_kmh > 100:
			speed_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))  # Yellow
		else:
			speed_label.add_theme_color_override("font_color", Color(1, 1, 1))  # White

func update_car_name(car_name: String) -> void:
	car_name_label.text = "Car: " + car_name.capitalize().replace("_", " ")
