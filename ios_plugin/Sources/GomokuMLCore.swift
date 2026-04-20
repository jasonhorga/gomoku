import Foundation
import CoreGraphics

// Swift core exposed to Obj-C++ / Godot.
//
// P2f: MCTSEngine-backed move selection, level-dispatched.
//   L5 — pattern-guided MCTS, 1500 sims (matches GDScript ai_mcts.gd
//        defaults). No CNN; nothing to load.
//   L6 — hybrid MCTS mirroring the Mac onnx_server production config
//        exactly: 200 sims, CoreML CNN priors blended 50/50 with pattern
//        priors, VCF depth 10, VCT via MCTSEngine internals. The
//        weight/sim pair was tuned twice — docs/ai_journey.md §9.1
//        (training-time sweep picked 0.5; 0.3 and 0.75 both collapsed
//        below 32%) and §14.2 (sims raised 80→200 after users beat L6
//        with double-threat combinations that 80 sims couldn't see).
//        Do not "bench-tune" this off 100 sims — at 100 sims the CNN
//        prior noise dominates, which is why an earlier P2k regression
//        disabled the CNN and shipped a worse AI. 200 is the tested
//        production budget.
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
			// Hybrid MCTS: CoreML CNN priors blended 50/50 with pattern
			// priors, same configuration as Mac onnx_server.py
			// OnnxServer.__init__ (and docs §14.6). Deliberately does
			// not "compensate" with more sims — 200 is the tested
			// budget above which per-move latency becomes user-visible.
			let adapter = ensureCoreMLLoaded()
			engine = MCTSEngine(
				simulations: 200,
				nnModel: adapter,
				cPuct: 1.4,
				usePatternPrior: true,
				dirichletAlpha: 0.0,
				vcfDepth: 10,
				vcfBranch: 8,
				cnnPriorWeight: 0.5
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
		let ml = coreMLLoadAttempted
			? (coreMLAdapter != nil ? "CoreML" : "pattern-only")
			: "CoreML-lazy"
		return NSString(string:
			"GomokuMLCore P2l (MCTS, L5=1500 L6=200+CNN50/50+VCF+VCT, nn=\(ml))")
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
