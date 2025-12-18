extends Node

const CARS_PATH = "res://cars/"
const DEFAULT_CAR = "default_car"

var available_cars: Dictionary = {}
var loaded_models: Dictionary = {}

func _ready() -> void:
	scan_cars_folder()

func scan_cars_folder() -> void:
	available_cars.clear()

	if not DirAccess.dir_exists_absolute(CARS_PATH):
		push_warning("Cars folder not found, creating it")
		DirAccess.make_dir_absolute(CARS_PATH)
		return

	var dir = DirAccess.open(CARS_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			if not dir.current_is_dir():
				if file_name.ends_with(".glb") or file_name.ends_with(".gltf"):
					var car_name = file_name.get_basename()
					var full_path = CARS_PATH + file_name
					available_cars[car_name] = full_path
					print("Found car: ", car_name, " at ", full_path)

			file_name = dir.get_next()

		dir.list_dir_end()

	print("Total cars found: ", available_cars.size())

func get_car_names() -> Array[String]:
	var names: Array[String] = []
	for car_name in available_cars.keys():
		names.append(car_name)
	names.sort()
	return names

func car_exists(car_name: String) -> bool:
	return available_cars.has(car_name)

func get_default_car() -> String:
	if available_cars.has(DEFAULT_CAR):
		return DEFAULT_CAR
	elif available_cars.size() > 0:
		return available_cars.keys()[0]
	return ""

func load_car(car_name: String) -> Node3D:
	if not car_exists(car_name):
		push_error("Car not found: ", car_name)
		return null

	if loaded_models.has(car_name):
		return loaded_models[car_name].instantiate()

	var car_path = available_cars[car_name]
	var loaded_resource = ResourceLoader.load(car_path)

	if loaded_resource == null:
		push_error("Failed to load car model: ", car_path)
		return null

	loaded_models[car_name] = loaded_resource

	return loaded_resource.instantiate()

func refresh_cars() -> void:
	scan_cars_folder()
