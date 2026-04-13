extends RefCounted

var timestamp: String = ""
var mode: String = ""  # "online", "local_pvp", "vs_ai", "ai_vs_ai"
var black_type: String = ""  # "human", "ai_random", "ai_heuristic", etc.
var white_type: String = ""
var moves: Array = []  # Array of [row, col]
var result: int = 0  # 0=draw, 1=black, 2=white
var total_moves: int = 0


func to_dict() -> Dictionary:
	return {
		"timestamp": timestamp,
		"mode": mode,
		"black": black_type,
		"white": white_type,
		"moves": moves,
		"result": result,
		"total_moves": total_moves,
	}


static func from_dict(d: Dictionary):  # returns GameRecord
	var record = load("res://scripts/data/game_record.gd").new()
	record.timestamp = d.get("timestamp", "")
	record.mode = d.get("mode", "")
	record.black_type = d.get("black", "")
	record.white_type = d.get("white", "")
	record.moves = d.get("moves", [])
	record.result = d.get("result", 0)
	record.total_moves = d.get("total_moves", 0)
	return record


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


static func from_json(text: String):  # returns GameRecord or null
	var json = JSON.new()
	if json.parse(text) != OK:
		return null
	return from_dict(json.data)


static func save_to_file(record, path: String) -> bool:
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(record.to_json())
	return true


static func load_from_file(path: String):  # returns GameRecord or null
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return from_json(file.get_as_text())


static func get_records_dir() -> String:
	return "user://game_records"


static func list_records() -> Array[String]:
	var dir_path = get_records_dir()
	var files: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return files
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and not dir.current_is_dir():
			files.append(dir_path + "/" + file_name)
		file_name = dir.get_next()
	files.sort()
	return files
