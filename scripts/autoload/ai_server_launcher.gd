extends Node

# Automatically launches the bundled AI server on game startup.
# Server binary is embedded inside the .app bundle (macOS) or next to executable (Linux).
# User never sees the server — it starts and stops with the game.

var _pid: int = -1
var server_available: bool = false

const SERVER_NAME = "gomoku_ai_server"
const PORT = 9877


func _ready() -> void:
	var server_path := _find_server()
	if server_path.is_empty():
		print("[AIServer] Not found — Level 6 will use MCTS fallback")
		return

	if _check_port_open():
		server_available = true
		print("[AIServer] Already running on port %d" % PORT)
		return

	# Launch silently in background
	_pid = OS.create_process(server_path, [], false)
	if _pid > 0:
		print("[AIServer] Launched (PID %d)" % _pid)
		# Poll for readiness up to 15s (pyinstaller cold-start + onnxruntime
		# load can take 4-5s on first launch, longer on slower machines).
		var start_ts := Time.get_ticks_msec()
		var deadline := start_ts + 15000
		while Time.get_ticks_msec() < deadline:
			if _check_port_open():
				server_available = true
				print("[AIServer] Ready in %dms" % (Time.get_ticks_msec() - start_ts))
				return
			await get_tree().create_timer(0.5).timeout
		print("[AIServer] Timeout after 15s — Level 6 will use MCTS fallback")
	else:
		print("[AIServer] Failed to launch")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_kill_server()


func _kill_server() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1


func _find_server() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()

	var paths: PackedStringArray = [
		# macOS: inside .app/Contents/MacOS/
		exe_dir.path_join(SERVER_NAME),
		# macOS: could also be in Resources
		exe_dir.path_join("..").path_join("Resources").path_join(SERVER_NAME),
		# Linux: next to executable
		exe_dir.path_join(SERVER_NAME),
	]

	for path in paths:
		if FileAccess.file_exists(path):
			return path

	return ""


func _check_port_open() -> bool:
	var tcp := StreamPeerTCP.new()
	var err := tcp.connect_to_host("127.0.0.1", PORT)
	if err != OK:
		return false
	var start := Time.get_ticks_msec()
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		tcp.poll()
		if Time.get_ticks_msec() - start > 1000:
			tcp.disconnect_from_host()
			return false
		OS.delay_msec(50)
	var ok := tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED
	tcp.disconnect_from_host()
	return ok
