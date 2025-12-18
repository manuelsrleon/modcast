extends Node

const SAVE_FILE = "user://game_data.save"
const SAVE_VERSION = "1.0"

func save_game(data: Dictionary) -> void:
	data["version"] = SAVE_VERSION
	var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if file:
		file.store_var(data)
		file.close()
		print("Game saved successfully")
	else:
		push_error("Failed to save game")

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_FILE):
		print("No save file found, using defaults")
		return {}

	var file = FileAccess.open(SAVE_FILE, FileAccess.READ)
	if file:
		var data = file.get_var()
		file.close()
		print("Game loaded successfully")
		return data
	else:
		push_error("Failed to load game")
		return {}

func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_FILE)

func get_saved_car() -> String:
	var data = load_game()
	return data.get("selected_car", "")

func save_car_preference(car_name: String) -> void:
	var data = load_game()
	data["selected_car"] = car_name
	save_game(data)
