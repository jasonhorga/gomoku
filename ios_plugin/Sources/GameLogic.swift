import Foundation

// Swift port of ai/game_logic.py. Kept as close to the Python shape as
// possible to simplify the differential tester — same method signatures
// (naming adjusted to Swift idiom), same board representation, same
// semantics for every operation that matters for play.
//
// Design notes:
//   - Board is a flat [Int8] of size 225 (row-major). Using a flat
//     buffer instead of [[Int8]] simplifies tensor packing later and
//     avoids per-row allocations.
//   - Move history is [(row, col)] — matches Python's list-of-tuples.
//   - Methods are designed to be callable both from MCTSEngine (later)
//     and from DiffTestCLI, hence the explicit mutation API.

public enum Stone: Int8 {
	case empty = 0
	case black = 1
	case white = 2
}

public struct Move: Equatable, Hashable, Codable {
	public let row: Int
	public let col: Int
	public init(_ row: Int, _ col: Int) {
		self.row = row
		self.col = col
	}
}

public final class GameLogic {
	public static let boardSize = 15

	// Index helpers — use these everywhere so a future switch to 2D
	// array or contiguous Int16 buffer doesn't require chasing math.
	@inlinable public static func idx(_ row: Int, _ col: Int) -> Int {
		return row * boardSize + col
	}

	// 4 line directions for win / pattern checks. Each direction is
	// traversed both forward and backward.
	public static let directions: [(dr: Int, dc: Int)] = [
		(0, 1), (1, 0), (1, 1), (1, -1),
	]

	public var board: [Int8]
	public var currentPlayer: Int8
	public var moveHistory: [Move]
	public var gameOver: Bool
	public var winner: Int8

	public init() {
		board = Array(repeating: 0, count: Self.boardSize * Self.boardSize)
		currentPlayer = Stone.black.rawValue
		moveHistory = []
		gameOver = false
		winner = Stone.empty.rawValue
	}

	public func reset() {
		for i in 0..<board.count {
			board[i] = 0
		}
		currentPlayer = Stone.black.rawValue
		moveHistory.removeAll()
		gameOver = false
		winner = Stone.empty.rawValue
	}

	@inlinable
	public func cell(_ row: Int, _ col: Int) -> Int8 {
		return board[Self.idx(row, col)]
	}

	@inlinable
	public func setCell(_ row: Int, _ col: Int, _ value: Int8) {
		board[Self.idx(row, col)] = value
	}

	@discardableResult
	public func placeStone(_ row: Int, _ col: Int) -> Bool {
		if gameOver { return false }
		if row < 0 || row >= Self.boardSize || col < 0 || col >= Self.boardSize {
			return false
		}
		let i = Self.idx(row, col)
		if board[i] != 0 { return false }

		board[i] = currentPlayer
		moveHistory.append(Move(row, col))

		if checkWin(at: row, col: col) {
			gameOver = true
			winner = currentPlayer
		} else if moveHistory.count >= Self.boardSize * Self.boardSize {
			gameOver = true
			winner = Stone.empty.rawValue
		}

		currentPlayer = (currentPlayer == Stone.black.rawValue)
			? Stone.white.rawValue
			: Stone.black.rawValue
		return true
	}

	public func checkWin(at row: Int, col: Int) -> Bool {
		let player = cell(row, col)
		if player == Stone.empty.rawValue { return false }
		for (dr, dc) in Self.directions {
			var count = 1
			count += countInDirection(row: row, col: col, dRow: dr, dCol: dc, player: player)
			count += countInDirection(row: row, col: col, dRow: -dr, dCol: -dc, player: player)
			if count >= 5 { return true }
		}
		return false
	}

	@inlinable
	public func countInDirection(row: Int, col: Int, dRow: Int, dCol: Int, player: Int8) -> Int {
		var count = 0
		var r = row + dRow
		var c = col + dCol
		while r >= 0 && r < Self.boardSize && c >= 0 && c < Self.boardSize
				&& board[Self.idx(r, c)] == player {
			count += 1
			r += dRow
			c += dCol
		}
		return count
	}

	public func copy() -> GameLogic {
		let g = GameLogic()
		g.board = board
		g.currentPlayer = currentPlayer
		g.moveHistory = moveHistory
		g.gameOver = gameOver
		g.winner = winner
		return g
	}

	public func validMoves() -> [Move] {
		var moves: [Move] = []
		for r in 0..<Self.boardSize {
			for c in 0..<Self.boardSize {
				if board[Self.idx(r, c)] == 0 {
					moves.append(Move(r, c))
				}
			}
		}
		return moves
	}

	/// Empty cells within `radius` of any placed stone. If the board is
	/// empty, seeds the center (7,7) like the Python version.
	public func nearbyMoves(radius: Int = 2) -> [Move] {
		var present = Array(repeating: false, count: Self.boardSize * Self.boardSize)
		var anyStone = false
		for r in 0..<Self.boardSize {
			for c in 0..<Self.boardSize {
				if board[Self.idx(r, c)] == 0 { continue }
				anyStone = true
				let rMin = max(0, r - radius)
				let rMax = min(Self.boardSize - 1, r + radius)
				let cMin = max(0, c - radius)
				let cMax = min(Self.boardSize - 1, c + radius)
				for nr in rMin...rMax {
					for nc in cMin...cMax {
						if board[Self.idx(nr, nc)] == 0 {
							present[Self.idx(nr, nc)] = true
						}
					}
				}
			}
		}
		var moves: [Move] = []
		// Iterate in (r, c) row-major order for deterministic output
		// so diff tests can sort and compare cleanly.
		for r in 0..<Self.boardSize {
			for c in 0..<Self.boardSize {
				if present[Self.idx(r, c)] {
					moves.append(Move(r, c))
				}
			}
		}
		if !anyStone && moves.isEmpty {
			moves.append(Move(7, 7))
		}
		return moves
	}
}
