extends RefCounted

# TCP client for connecting to the Python AI server.
# Uses length-prefixed JSON protocol matching ai_server/protocol.py.

var tcp: StreamPeerTCP = null
var connected: bool = false
var _buffer: PackedByteArray = PackedByteArray()

const DEFAULT_HOST: String = "127.0.0.1"
const DEFAULT_PORT: int = 9877


func connect_to_server(host: String = DEFAULT_HOST, port: int = DEFAULT_PORT) -> bool:
	tcp = StreamPeerTCP.new()
	tcp.set_no_delay(true)
	var err := tcp.connect_to_host(host, port)
	if err != OK:
		tcp = null
		return false

	# Wait for connection (up to 3 seconds)
	var start := Time.get_ticks_msec()
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		tcp.poll()
		if Time.get_ticks_msec() - start > 3000:
			tcp = null
			return false
		OS.delay_msec(50)

	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		tcp = null
		return false

	connected = true
	return true


func disconnect_from_server() -> void:
	if tcp != null:
		tcp.disconnect_from_host()
	tcp = null
	connected = false
	_buffer = PackedByteArray()


func is_connected_to_server() -> bool:
	if tcp == null:
		return false
	tcp.poll()
	return tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


func send_message(msg: Dictionary) -> bool:
	if not is_connected_to_server():
		return false
	var json_str := JSON.stringify(msg)
	var data := json_str.to_utf8_buffer()
	var length := data.size()

	# Send 4-byte big-endian length prefix
	var header := PackedByteArray()
	header.resize(4)
	header[0] = (length >> 24) & 0xFF
	header[1] = (length >> 16) & 0xFF
	header[2] = (length >> 8) & 0xFF
	header[3] = length & 0xFF

	tcp.put_data(header)
	tcp.put_data(data)
	return true


func receive_message() -> Dictionary:
	# Non-blocking: check for available data
	if not is_connected_to_server():
		return {}

	var available := tcp.get_available_bytes()
	if available > 0:
		var result := tcp.get_data(available)
		if result[0] == OK:
			_buffer.append_array(result[1])

	# Try to decode from buffer
	if _buffer.size() < 4:
		return {}

	var length: int = (_buffer[0] << 24) | (_buffer[1] << 16) | (_buffer[2] << 8) | _buffer[3]
	if _buffer.size() < 4 + length:
		return {}

	var json_data := _buffer.slice(4, 4 + length).get_string_from_utf8()
	_buffer = _buffer.slice(4 + length)

	var json := JSON.new()
	if json.parse(json_data) != OK:
		return {}
	return json.data


func request_move(board: Array, current_player: int, last_move = null) -> Dictionary:
	# Blocking: send move request and wait for response (up to 30 seconds)
	# last_move: optional [row, col] — used by v2 9-channel CNN for the
	# "last move played" feature plane. Safe to omit with legacy models.
	var msg := {"cmd": "move", "board": board, "current": current_player}
	if last_move != null:
		msg["last_move"] = last_move
	if not send_message(msg):
		return {}

	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 30000:
		var response := receive_message()
		if not response.is_empty():
			return response
		OS.delay_msec(10)

	return {}


func request_status() -> Dictionary:
	var msg := {"cmd": "status"}
	if not send_message(msg):
		return {}

	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000:
		var response := receive_message()
		if not response.is_empty():
			return response
		OS.delay_msec(10)

	return {}
