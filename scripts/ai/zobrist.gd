extends RefCounted

# Zobrist hashing for transposition table in Minimax search.
# Pre-generates random numbers for each (row, col, piece) combination.
# Board hash is XOR of all cell values — incremental updates are O(1).

const BOARD_SIZE: int = 15

var table: Array = []  # [15][15][3] of int
var current_hash: int = 0


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42  # deterministic for reproducibility
	table.resize(BOARD_SIZE)
	for r in range(BOARD_SIZE):
		table[r] = []
		table[r].resize(BOARD_SIZE)
		for c in range(BOARD_SIZE):
			table[r][c] = [rng.randi(), rng.randi(), rng.randi()]


func reset() -> void:
	current_hash = 0


func update(row: int, col: int, piece: int) -> void:
	current_hash ^= table[row][col][piece]


func get_hash() -> int:
	return current_hash
