extends Node

const CARS_PATH = "res://cars/"
const CACHE_PATH = "user://car_cache/"
const DEFAULT_CAR = "default_car"

var available_cars: Dictionary = {}
var loaded_models: Dictionary = {}

func _ready() -> void:
	_ensure_cache_directory()
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
				elif file_name.ends_with(".zip"):
					_extract_and_register_zip(file_name)

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

func _ensure_cache_directory() -> void:
	if not DirAccess.dir_exists_absolute(CACHE_PATH):
		DirAccess.make_dir_absolute(CACHE_PATH)
		print("Created cache directory at: ", CACHE_PATH)

func _extract_and_register_zip(zip_filename: String) -> void:
	var zip_path = CARS_PATH + zip_filename
	var car_name = zip_filename.get_basename()

	print("Processing zip file: ", zip_filename)

	var zip_reader = ZIPReader.new()
	var err = zip_reader.open(zip_path)

	if err != OK:
		push_error("Failed to open zip file: ", zip_path)
		zip_reader.close()
		return

	var files = zip_reader.get_files()
	var cache_dir = CACHE_PATH + car_name + "/"

	DirAccess.make_dir_recursive_absolute(cache_dir)

	for file_path in files:
		if file_path.ends_with("/"):
			continue

		var file_data = zip_reader.read_file(file_path)
		if file_data.size() == 0:
			continue

		var output_path = cache_dir + file_path
		var output_dir = output_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(output_dir)

		var file = FileAccess.open(output_path, FileAccess.WRITE)
		if file:
			file.store_buffer(file_data)
			file.close()

		if file_path.ends_with(".glb") or file_path.ends_with(".gltf"):
			var model_name = car_name + "_" + file_path.get_file().get_basename()
			available_cars[model_name] = output_path
			print("Found car model in zip: ", model_name, " at ", output_path)

	zip_reader.close()
