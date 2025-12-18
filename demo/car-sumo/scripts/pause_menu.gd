extends CanvasLayer

@onready var car_list = %CarList
@onready var resume_button = %ResumeButton

var current_selected_car: String = ""
var car_buttons: Dictionary = {}

func _ready() -> void:
	visible = false
	populate_car_list()
	resume_button.pressed.connect(_on_resume_pressed)

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
	get_tree().paused = visible

	if visible:
		populate_car_list()

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
		button.custom_minimum_size = Vector2(0, 40)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_on_car_selected.bind(car_name))
		car_list.add_child(button)
		car_buttons[car_name] = button

	update_selection_indicator()

func _on_car_selected(car_name: String) -> void:
	current_selected_car = car_name
	apply_car_selection(car_name, true)
	update_selection_indicator()

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
		
		# Update HUD with new car name
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("update_car_name"):
			hud.update_car_name(car_name)
	else:
		push_error("Failed to load car: ", car_name)

func update_selection_indicator() -> void:
	for car_name in car_buttons.keys():
		var button = car_buttons[car_name]
		if car_name == current_selected_car:
			button.text = "✓ " + car_name.capitalize().replace("_", " ")
			button.add_theme_color_override("font_color", Color(0.4, 1, 0.5))
		else:
			button.text = car_name.capitalize().replace("_", " ")
			button.add_theme_color_override("font_color", Color(1, 1, 1))

func _on_resume_pressed() -> void:
	toggle_pause()
