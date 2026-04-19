import Foundation
import CoreGraphics

// Swift core exposed to Obj-C++ / Godot. P2c scope: greedy pattern-eval
// move selection — scores every candidate (nearby-of-stones) cell with
// PatternEval.scoreCell, picks the argmax. Weaker than MCTS but proves
// the ported Swift core runs end-to-end on iOS. MCTS (+ CoreML value
// head) stack on top in P2e.
@objc public class GomokuMLCore: NSObject {

	@objc public override init() {
		super.init()
	}

	/// Pick a move using pattern-greedy logic. `board` is a 15-row array
	/// of 15-col arrays of NSNumber (int); `player` is 1 (BLACK) or 2
	/// (WHITE). Returns (row, col) packed as CGPoint. Empty / unreachable
	/// boards default to the center (7, 7).
	@objc public func chooseMove(level: Int, board: [[NSNumber]], player: Int) -> CGPoint {
		let game = GameLogic()
		game.currentPlayer = Int8(player)

		// Unpack the 2D NSNumber array into GameLogic's flat buffer.
		// Defensive: tolerate short rows / columns.
		let size = GameLogic.boardSize
		for r in 0..<min(size, board.count) {
			let row = board[r]
			for c in 0..<min(size, row.count) {
				game.setCell(r, c, Int8(truncatingIfNeeded: row[c].intValue))
			}
		}

		let candidates = game.nearbyMoves(radius: 2)
		if candidates.isEmpty {
			return CGPoint(x: 7, y: 7)
		}

		var bestScore: Double = -Double.infinity
		var bestMove = candidates[0]
		for move in candidates {
			let score = PatternEval.scoreCell(
				board: game.board, row: move.row, col: move.col,
				player: Int8(player))
			if score > bestScore {
				bestScore = score
				bestMove = move
			}
		}
		return CGPoint(x: bestMove.row, y: bestMove.col)
	}

	@objc public func version() -> NSString {
		return "GomokuMLCore P2c (pattern-greedy, no MCTS yet)"
	}
}
