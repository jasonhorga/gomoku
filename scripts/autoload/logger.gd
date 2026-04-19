extends Node

# Persistent in-app logger. On iOS where there's no console, this is how
# we see what happened before a crash. File lives at user://gomoku.log —
# exposed to the iOS Files app via user_data/accessible_from_files_app=true
# in export_presets.cfg.
#
# Usage:
#   Log.info("Game", "new game started, level=%d" % level)
#   Log.warn("MCTS", "tree reused=false (position changed)")
#   Log.error("Net", "disconnect, reconnecting")

const LOG_PATH := "user://gomoku.log"
const LOG_ROLLOVER_PATH := "user://gomoku.log.1"
const MAX_LOG_SIZE := 512 * 1024  # 512KB — keep small so iOS Files transfer is fast

var _file: FileAccess = null
var _session_start_ms: int = 0


func _ready() -> void:
	_session_start_ms = Time.get_ticks_msec()
	_rotate_if_needed()
	_file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if _file == null:
		_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file != null:
		_file.seek_end()
	_write_banner()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		info("Logger", "shutdown (session %ds)" % int((Time.get_ticks_msec() - _session_start_ms) / 1000))
		if _file != null:
			_file.flush()
			_file.close()
			_file = null
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		info("Logger", "app paused (backgrounded)")
		if _file != null:
			_file.flush()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		info("Logger", "app resumed")


func _rotate_if_needed() -> void:
	if not FileAccess.file_exists(LOG_PATH):
		return
	var sz := FileAccess.get_file_as_bytes(LOG_PATH).size()
	if sz < MAX_LOG_SIZE:
		return
	var da := DirAccess.open("user://")
	if da == null:
		return
	if da.file_exists(LOG_ROLLOVER_PATH.get_file()):
		da.remove(LOG_ROLLOVER_PATH.get_file())
	da.rename(LOG_PATH.get_file(), LOG_ROLLOVER_PATH.get_file())


func _write_banner() -> void:
	var now := Time.get_datetime_string_from_system(true)
	var os_name := OS.get_name()
	var vers := ProjectSettings.get_setting("application/config/version", "?")
	_write_line("========================================")
	_write_line("[%s] Gomoku boot v%s on %s" % [now, vers, os_name])
	_write_line("========================================")


func info(tag: String, msg: String) -> void:
	_log("INFO", tag, msg)


func warn(tag: String, msg: String) -> void:
	_log("WARN", tag, msg)


func error(tag: String, msg: String) -> void:
	_log("ERROR", tag, msg)


func _log(level: String, tag: String, msg: String) -> void:
	var t := (Time.get_ticks_msec() - _session_start_ms) / 1000.0
	var line := "[%8.2f] %-5s %-10s %s" % [t, level, tag, msg]
	print(line)
	_write_line(line)


func _write_line(line: String) -> void:
	if _file == null:
		return
	_file.store_line(line)
	# Flush every error-level line and every ~50 info lines; iOS can SIGKILL
	# at any time, so we can't trust buffers.
	_file.flush()


func get_log_path_absolute() -> String:
	return ProjectSettings.globalize_path(LOG_PATH)


func read_log_snapshot(max_lines: int = 500) -> String:
	# Read the last N lines of the current log — useful for an in-app viewer.
	if not FileAccess.file_exists(LOG_PATH):
		return "(log empty)"
	var f := FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		return "(log unreadable)"
	var lines: PackedStringArray = []
	while not f.eof_reached():
		lines.append(f.get_line())
	f.close()
	var start := maxi(0, lines.size() - max_lines)
	return "\n".join(lines.slice(start))
