extends Node

const _GameLogic = preload("res://scripts/game_logic.gd")
const PORT: int = 9876
const MAX_CLIENTS: int = 1

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var opponent_id: int = -1
var my_player_color: int = -1

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()
signal game_start_ready()
signal move_received(row: int, col: int)
signal reset_requested()
signal reset_accepted()


func host_game() -> bool:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	my_player_color = _GameLogic.BLACK

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return true


func join_game(ip_address: String) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip_address, PORT)
	if error != OK:
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	my_player_color = _GameLogic.WHITE

	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return true


func disconnect_from_game() -> void:
	if peer != null:
		multiplayer.multiplayer_peer = null
		peer = null
	_disconnect_signals()
	is_host = false
	opponent_id = -1
	my_player_color = -1


func send_move(row: int, col: int) -> void:
	_receive_move.rpc(row, col)


func send_reset_request() -> void:
	_receive_reset_request.rpc()


func send_reset_accept() -> void:
	_receive_reset_accept.rpc()


@rpc("any_peer", "reliable")
func _receive_move(row: int, col: int) -> void:
	move_received.emit(row, col)


@rpc("any_peer", "reliable")
func _receive_reset_request() -> void:
	reset_requested.emit()


@rpc("any_peer", "reliable")
func _receive_reset_accept() -> void:
	reset_accepted.emit()


func _on_peer_connected(id: int) -> void:
	opponent_id = id
	player_connected.emit(id)
	game_start_ready.emit()


func _on_peer_disconnected(id: int) -> void:
	opponent_id = -1
	player_disconnected.emit(id)


func _on_connection_succeeded() -> void:
	opponent_id = 1  # server is always peer id 1
	connection_succeeded.emit()
	game_start_ready.emit()


func _on_connection_failed() -> void:
	disconnect_from_game()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	opponent_id = -1
	player_disconnected.emit(-1)


func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connection_succeeded):
		multiplayer.connected_to_server.disconnect(_on_connection_succeeded)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)


func get_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	if addresses.size() > 0:
		return addresses[0]
	return "unknown"
