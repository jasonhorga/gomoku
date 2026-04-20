import Foundation
import CoreGraphics

// Swift core exposed to Obj-C++ / Godot.
//
// P2f: MCTSEngine-backed move selection, level-dispatched. L5 gets
// pattern-guided MCTS (matches Fix A defaults on GDScript: 1500 sims,
// VCF 10 / 8, pattern priors). L6 reuses the same engine with a
// heavier sim budget while CoreML hookup is still pending — a hybrid
// adapter lands later and L6 will pick up the extra strength for free.
// L1-L4 stay in GDScript (simple heuristics); the plugin is never
// called for them.
//
// Public @objc surface:
//   chooseMove(level:board:player:) -> CGPoint — the Godot-facing RPC
//   version()                                  — diagnostic string
@objc public class GomokuMLCore: NSObject {

	@objc public override init() {
		super.init()
	}

	/// Pick a move. `board` is a 15-row array of 15 NSNumber columns
	/// (int values 0=empty, 1=BLACK, 2=WHITE). `player` is 1 or 2.
	/// Returns (row, col) packed as CGPoint. Unreachable boards
	/// default to the centre (7, 7).
	@objc public func chooseMove(level: Int, board: [[NSNumber]], player: Int) -> CGPoint {
		let game = GameLogic()
		game.currentPlayer = Int8(player)

		// NSNumber → flat Int8 board. Defensive about short rows/cols
		// so a malformed GDScript call doesn't crash the plugin.
		let size = GameLogic.boardSize
		for r in 0..<min(size, board.count) {
			let row = board[r]
			for c in 0..<min(size, row.count) {
				game.setCell(r, c, Int8(truncatingIfNeeded: row[c].intValue))
			}
		}

		if game.nearbyMoves(radius: 2).isEmpty {
			return CGPoint(x: 7, y: 7)
		}

		// Sim budget per level. 1500 matches scripts/ai/ai_mcts.gd for
		// L5, and L6 gets a ~1.7x uplift on the same pattern-guided
		// engine. These numbers were calibrated on M5 device timing —
		// see the Mac AI-perf plan commit for the rationale.
		let sims: Int
		switch level {
		case 5: sims = 1500
		case 6: sims = 2500
		default: sims = 800  // defensive fallback
		}

		let engine = MCTSEngine(
			simulations: sims,
			nnModel: nil,
			cPuct: 1.4,
			usePatternPrior: true,
			dirichletAlpha: 0.0,
			vcfDepth: 10,
			vcfBranch: 8
		)
		let move = engine.chooseMove(game: game)
		return CGPoint(x: move.row, y: move.col)
	}

	@objc public func version() -> NSString {
		return "GomokuMLCore P2f (pattern-MCTS, L5=1500 L6=2500)"
	}
}
