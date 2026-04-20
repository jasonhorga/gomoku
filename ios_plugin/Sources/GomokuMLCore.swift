import Foundation
import CoreGraphics

// Swift core exposed to Obj-C++ / Godot.
//
// P2f: MCTSEngine-backed move selection, level-dispatched.
//   L5 — pattern-guided MCTS, 1500 sims (matches GDScript ai_mcts.gd
//        defaults). No CNN; nothing to load.
//   L6 — hybrid MCTS with CoreML priors from big_iter_1 (66.9% vs
//        bootstrap on Mac Python eval). sims=200 to match the Mac
//        onnx_server default — the CNN contributes most of the strength
//        so we don't need to brute-force simulations.
//   L1–L4 stay in GDScript; the plugin is never called for them.
//
// CoreML loading is lazy: only L6's first chooseMove call triggers it.
// If the .mlmodelc is missing from Bundle.main (e.g. broken packaging),
// L6 gracefully falls through to pattern-only MCTS — still plays, just
// without the CNN uplift, and logs that we degraded.
@objc public class GomokuMLCore: NSObject {

	// Lazy-loaded once per process.
	private var coreMLAdapter: CoreMLAdapter?
	private var coreMLLoadAttempted = false

	@objc public override init() {
		super.init()
	}

	/// Pick a move. `board` is a 15×15 NSNumber array (0=empty, 1=BLACK,
	/// 2=WHITE). `player` is 1 or 2. Returns (row, col) as CGPoint.
	@objc public func chooseMove(level: Int, board: [[NSNumber]], player: Int) -> CGPoint {
		let game = GameLogic()
		game.currentPlayer = Int8(player)

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

		let engine: MCTSEngine
		switch level {
		case 6:
			// CNN disabled: the bench_hybrid_vs_pattern.py diff found
			// best_model.pt (big_iter_1 128f/6b) at cnn_prior_weight=0.5
			// + 100 sims scored 35% against a pure pattern-MCTS baseline
			// — the CNN's noisier priors didn't get enough visits to
			// amplify. This is the same Python code Mac's onnx_server
			// runs, so Mac's L6 was also underperforming; iOS just
			// matched that regression.
			//
			// Fix is inference-time only (no retraining): drop the CNN
			// and compensate with 2× the pattern-MCTS sim budget over
			// L5, plus a longer VCF depth. NnModelAdapter plumbing stays
			// so a future checkpoint can plug back in without more
			// code changes — just flip nnModel back to ensureCoreMLLoaded().
			engine = MCTSEngine(
				simulations: 3000,
				nnModel: nil,
				cPuct: 1.4,
				usePatternPrior: true,
				dirichletAlpha: 0.0,
				vcfDepth: 12,
				vcfBranch: 8
			)
		case 5:
			// Pattern-only MCTS, 1500 sims. No CNN dependency.
			engine = MCTSEngine(
				simulations: 1500,
				nnModel: nil,
				cPuct: 1.4,
				usePatternPrior: true,
				dirichletAlpha: 0.0,
				vcfDepth: 10,
				vcfBranch: 8
			)
		default:
			// Defensive fallback for unexpected levels.
			engine = MCTSEngine(
				simulations: 800,
				nnModel: nil,
				cPuct: 1.4,
				usePatternPrior: true,
				vcfDepth: 10,
				vcfBranch: 8
			)
		}

		let move = engine.chooseMove(game: game)
		return CGPoint(x: move.row, y: move.col)
	}

	@objc public func version() -> NSString {
		// CoreML kept in the pipe for future checkpoints; not exercised
		// by L6 right now (see chooseMove comment). Version string
		// reports what L6 actually runs so the on-device smoke log is
		// unambiguous.
		return NSString(string:
			"GomokuMLCore P2k (pattern-MCTS, L5=1500 L6=3000+VCF12, CNN off)")
	}

	/// Lazy-load big_iter_1 from the app bundle. Nil → L6 falls back to
	/// pattern-only mode (still playable, no crash).
	private func ensureCoreMLLoaded() -> CoreMLAdapter? {
		if coreMLLoadAttempted { return coreMLAdapter }
		coreMLLoadAttempted = true

		// Bundled resource name must match the export step in ios.yml.
		// Compiled form (.mlmodelc, a directory) is faster to load than
		// .mlpackage because it skips on-device compilation.
		guard let url = Bundle.main.url(forResource: "GomokuNet",
		                                 withExtension: "mlmodelc")
			?? Bundle.main.url(forResource: "GomokuNet",
			                   withExtension: "mlpackage") else {
			NSLog("CoreMLAdapter: GomokuNet.{mlmodelc,mlpackage} not in bundle — L6 will degrade to pattern-only")
			return nil
		}
		coreMLAdapter = CoreMLAdapter(modelURL: url)
		return coreMLAdapter
	}
}
