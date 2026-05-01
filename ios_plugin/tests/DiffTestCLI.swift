import Foundation

// JSON-in / JSON-out CLI that exposes GameLogic (and eventually
// PatternEval, VCF, VCT, MCTS) operations for the differential tester.
// The Python runner (run_diff_tests.py) generates random states, runs
// the same operation through ai/game_logic.py, invokes this CLI with
// the same input, and fails if outputs diverge.
//
// Protocol:
//   stdin  → one JSON object per invocation
//   stdout → one JSON object response
//
// Example:
//   echo '{"op":"nearby_moves","board":[[0,...],...],"radius":2}'
//     | ./diff_test_cli
//   → {"moves":[[6,6],[6,7],...]}

@main
struct DiffTestCLI {
	static func main() {
		let data = FileHandle.standardInput.readDataToEndOfFile()
		guard let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			emit(["error": "invalid json input"])
			return
		}
		guard let op = req["op"] as? String else {
			emit(["error": "missing op"])
			return
		}

		let game = GameLogic()
		if let board = req["board"] as? [[Int]] {
			loadBoard(game: game, board: board)
		}
		if let player = req["player"] as? Int {
			game.currentPlayer = Int8(player)
		}
		if let history = req["move_history"] as? [[Int]] {
			game.moveHistory = history.compactMap {
				$0.count >= 2 ? Move($0[0], $0[1]) : nil
			}
		}

		let result = dispatch(op: op, req: req, game: game)
		emit(result)
	}

	static func loadBoard(game: GameLogic, board: [[Int]]) {
		for r in 0..<GameLogic.boardSize {
			guard r < board.count, board[r].count == GameLogic.boardSize else {
				continue
			}
			for c in 0..<GameLogic.boardSize {
				game.setCell(r, c, Int8(board[r][c]))
			}
		}
	}

	static func dispatch(op: String, req: [String: Any], game: GameLogic) -> [String: Any] {
		switch op {
		case "check_win":
			guard let row = req["row"] as? Int, let col = req["col"] as? Int else {
				return ["error": "check_win needs row + col"]
			}
			return ["win": game.checkWin(at: row, col: col)]

		case "nearby_moves":
			let radius = req["radius"] as? Int ?? 2
			let moves = game.nearbyMoves(radius: radius)
			return ["moves": moves.map { [$0.row, $0.col] }]

		case "valid_moves":
			let moves = game.validMoves()
			return ["moves": moves.map { [$0.row, $0.col] }]

		case "is_forbidden_black":
			guard let row = req["row"] as? Int, let col = req["col"] as? Int else {
				return ["error": "is_forbidden_black needs row + col"]
			}
			var board = game.board
			return ["forbidden": RenjuForbidden.isForbiddenBlack(board: &board, row: row, col: col)]

		case "place_stone":
			guard let row = req["row"] as? Int, let col = req["col"] as? Int else {
				return ["error": "place_stone needs row + col"]
			}
			let ok = game.placeStone(row, col)
			return [
				"success": ok,
				"winner": Int(game.winner),
				"game_over": game.gameOver,
				"current_player": Int(game.currentPlayer),
			]

		case "count_direction":
			guard let row = req["row"] as? Int,
					let col = req["col"] as? Int,
					let dr = req["dr"] as? Int,
					let dc = req["dc"] as? Int,
					let player = req["cnt_player"] as? Int else {
				return ["error": "count_direction needs row,col,dr,dc,cnt_player"]
			}
			let count = game.countInDirection(
				row: row, col: col, dRow: dr, dCol: dc, player: Int8(player))
			return ["count": count]

		// ---- PatternEval ops ----

		case "score_cell":
			guard let row = req["row"] as? Int,
					let col = req["col"] as? Int,
					let p = req["eval_player"] as? Int else {
				return ["error": "score_cell needs row,col,eval_player"]
			}
			let score = PatternEval.scoreCell(
				board: game.board, row: row, col: col, player: Int8(p))
			return ["score": score]

		case "evaluate_position":
			guard let row = req["row"] as? Int,
					let col = req["col"] as? Int,
					let p = req["eval_player"] as? Int else {
				return ["error": "evaluate_position needs row,col,eval_player"]
			}
			let score = PatternEval.evaluatePosition(
				board: game.board, row: row, col: col, player: Int8(p))
			return ["score": score]

		case "detect_threats":
			guard let row = req["row"] as? Int,
					let col = req["col"] as? Int,
					let p = req["eval_player"] as? Int else {
				return ["error": "detect_threats needs row,col,eval_player"]
			}
			if let t = PatternEval.detectThreats(
					board: game.board, row: row, col: col, player: Int8(p)) {
				return ["threats": [
					"five": t.five,
					"open_four": t.openFour,
					"half_four": t.halfFour,
					"open_three": t.openThree,
					"half_three": t.halfThree,
				] as [String: Any]]
			}
			return ["threats": NSNull()]

		case "make_feature_planes":
			guard let p = req["eval_player"] as? Int else {
				return ["error": "make_feature_planes needs eval_player"]
			}
			let flat = PatternEval.makeFeaturePlanes(
				board: game.board, currentPlayer: Int8(p))
			// Return flat [Float] → JSON array of numbers. Python
			// compares against np.ndarray.flatten().
			return ["planes": flat.map { Double($0) }]

		// ---- VCF / VCT ops ----

		case "vcf_candidates":
			// VCF/VCT's own candidate_moves (not GameLogic.nearbyMoves).
			// Tested separately because its determinism (sorted) is what
			// makes the Python↔Swift diff tests reliable.
			let radius = req["radius"] as? Int ?? 1
			let cands = VcfSearch.candidateMoves(board: game.board, radius: radius)
			return ["moves": cands.map { [$0.row, $0.col] }]

		case "makes_five":
			guard let row = req["row"] as? Int,
					let col = req["col"] as? Int,
					let p = req["player"] as? Int else {
				return ["error": "makes_five needs row,col,player"]
			}
			let hit = VcfSearch.makesFive(
				board: game.board, row: row, col: col, player: Int8(p))
			return ["makes_five": hit]

		case "four_info":
			guard let row = req["row"] as? Int,
					let col = req["col"] as? Int,
					let p = req["player"] as? Int else {
				return ["error": "four_info needs row,col,player"]
			}
			let info = VcfSearch.fourInfo(
				board: game.board, row: row, col: col, player: Int8(p))
			var kind: Any = NSNull()
			if let k = info.kind {
				switch k {
				case .five: kind = "five"
				case .openFour: kind = "open_four"
				case .halfFour: kind = "half_four"
				}
			}
			// Dedupe+sort blocks so order matches Python's set() iteration
			// after our determinism patch.
			let packed = Set(info.blockCells.map {
				$0.row * GameLogic.boardSize + $0.col
			})
			let blocks = packed.sorted().map {
				[$0 / GameLogic.boardSize, $0 % GameLogic.boardSize]
			}
			return ["kind": kind, "blocks": blocks]

		case "find_vcf":
			guard let attacker = req["attacker"] as? Int else {
				return ["error": "find_vcf needs attacker"]
			}
			let depth = req["max_depth"] as? Int ?? 6
			let branch = req["max_branch"] as? Int ?? 8
			let forbiddenEnabled = req["forbidden_enabled"] as? Bool ?? false
			var board = game.board
			let move = VcfSearch.findVcf(
				board: &board, attacker: Int8(attacker),
				maxDepth: depth, maxBranch: branch,
				forbiddenEnabled: forbiddenEnabled)
			if let m = move {
				return ["move": [m.row, m.col]]
			}
			return ["move": NSNull()]

		case "open_threes":
			guard let row = req["row"] as? Int,
					let col = req["col"] as? Int,
					let p = req["player"] as? Int else {
				return ["error": "open_threes needs row,col,player"]
			}
			let threes = VctSearch.openThrees(
				board: game.board, row: row, col: col, player: Int8(p))
			// Encode as a sorted list of directions (dr,dc) for stable
			// comparison. Extension cells also sorted.
			let encoded = threes
				.map { (t: (dir: (Int, Int), extensions: [(row: Int, col: Int)])) -> [String: Any] in
					let exts = t.extensions.map { [$0.row, $0.col] }
						.sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
					return [
						"dir": [t.dir.0, t.dir.1],
						"extensions": exts,
					]
				}
				.sorted { (a, b) -> Bool in
					let ad = a["dir"] as! [Int]
					let bd = b["dir"] as! [Int]
					return (ad[0], ad[1]) < (bd[0], bd[1])
				}
			return ["threes": encoded]

		case "find_vct":
			guard let attacker = req["attacker"] as? Int else {
				return ["error": "find_vct needs attacker"]
			}
			let depth = req["max_depth"] as? Int ?? 4
			let branch = req["max_branch"] as? Int ?? 6
			let forbiddenEnabled = req["forbidden_enabled"] as? Bool ?? false
			var board = game.board
			let move = VctSearch.findVct(
				board: &board, attacker: Int8(attacker),
				maxDepth: depth, maxBranch: branch,
				forbiddenEnabled: forbiddenEnabled)
			if let m = move {
				return ["move": [m.row, m.col]]
			}
			return ["move": NSNull()]

		// ---- MCTSEngine helper ops ----
		// The full MCTS loop is NOT diff-tested: random.choice on the
		// Python side + float cascades across 1000 sims make visit
		// counts non-deterministic across implementations. We test the
		// bit-exact leaves instead (softmax, puct, leaf evals) plus
		// shortcut paths (immediate win/block, VCF, VCT) where both
		// engines take the same deterministic branch.

		case "softmax_prior":
			// Input: {"scored": [[r,c,score], ...], "temperature": float}
			guard let raw = req["scored"] as? [[Double]] else {
				return ["error": "softmax_prior needs scored=[[r,c,score]...]"]
			}
			let temp = req["temperature"] as? Double ?? 1.0
			let scored: [(move: (row: Int, col: Int), score: Double)] =
				raw.compactMap { arr in
					guard arr.count >= 3 else { return nil }
					return ((Int(arr[0]), Int(arr[1])), arr[2])
				}
			let soft = MCTS.softmaxPrior(scores: scored, temperature: temp)
			return ["probs": soft.map {
				[Double($0.move.row), Double($0.move.col), $0.prob]
			}]

		case "puct":
			// Bare PUCT formula on synthetic node counts.
			guard let prior = req["prior"] as? Double,
					let wins = req["wins"] as? Double,
					let visits = req["visits"] as? Int,
					let parentVisits = req["parent_visits"] as? Int else {
				return ["error":
					"puct needs prior,wins,visits,parent_visits"]
			}
			let cPuct = req["c_puct"] as? Double ?? 1.4
			// Build a minimal parent+child pair so we exercise the real
			// puct() method instead of duplicating the formula here.
			let parent = MCTSNode(parent: nil, move: nil, player: 1)
			parent.visits = parentVisits
			let child = MCTSNode(parent: parent, move: (0, 0),
			                     player: 2, prior: prior)
			child.visits = visits
			child.wins = wins
			return ["score": child.puct(cPuct: cPuct)]

		case "static_leaf_value":
			// Integer output; truly bit-exact.
			let engine = MCTSEngine()
			return ["winner": Int(engine.staticLeafValue(game: game))]

		case "continuous_leaf_value":
			guard let persp = req["perspective"] as? Int else {
				return ["error": "continuous_leaf_value needs perspective"]
			}
			let engine = MCTSEngine()
			return ["value": engine.continuousLeafValue(
				game: game, perspective: Int8(persp))]

		case "compute_priors_pattern":
			// Pattern-only priors (nnModel=nil). Returns sparse map
			// keyed by "r,c" for stable comparison.
			let engine = MCTSEngine()
			let cands: [(row: Int, col: Int)] =
				game.nearbyMoves(radius: 2).map { (row: $0.row, col: $0.col) }
			let p = engine.computePriors(
				game: game, candidates: cands, player: game.currentPlayer)
			var map: [String: Double] = [:]
			for c in cands {
				let key = "\(c.row),\(c.col)"
				map[key] = p[GameLogic.idx(c.row, c.col)]
			}
			return ["priors": map]

		case "mcts_choose_move":
			// Only meaningful for shortcut-triggering positions; see
			// run_diff_tests.py for gating. sims=1 keeps the non-shortcut
			// branch cheap since the test ignores that output anyway.
			let sims = req["simulations"] as? Int ?? 1
			let engine = MCTSEngine(
				simulations: sims, nnModel: nil,
				usePatternPrior: true, dirichletAlpha: 0.0,
				vcfDepth: 10, vcfBranch: 8)
			let m = engine.chooseMove(game: game)
			return ["move": [m.row, m.col]]

		case "nine_channel_input":
			// P2h: CoreMLAdapter's 9-plane input tensor. Compares to
			// Python's GameLogic.to_tensor_9ch. This is the bug-prone
			// piece of the CoreML port — if the channel layout or the
			// own/opp split disagree, inference will silently produce
			// garbage policies.
			if let history = req["move_history"] as? [[Int]] {
				game.moveHistory = history.compactMap {
					$0.count >= 2 ? Move($0[0], $0[1]) : nil
				}
			}
			let flat = CoreMLAdapter.makeNineChannelInput(game: game)
			return ["planes": flat.map { Double($0) }]

		default:
			return ["error": "unknown op: \(op)"]
		}
	}

	static func emit(_ obj: [String: Any]) {
		guard let data = try? JSONSerialization.data(
				withJSONObject: obj, options: [.sortedKeys]) else {
			FileHandle.standardError.write(
				"failed to serialize output\n".data(using: .utf8)!)
			exit(2)
		}
		FileHandle.standardOutput.write(data)
		FileHandle.standardOutput.write("\n".data(using: .utf8)!)
	}
}
