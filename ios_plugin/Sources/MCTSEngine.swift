import Foundation

// Port of ai_server/ai/mcts_engine.py.
//
// Scope choices (see /advisor notes for P2e):
//
// - Pattern-only and hybrid (CNN + pattern) modes are both supported;
//   CNN hookup is a protocol that returns (policy, value). Today nnModel
//   is always nil on iOS — P2f will plug a CoreML-backed adapter in.
// - Dirichlet noise is kept in the API but not implemented: iOS is eval
//   play only, so dirichletAlpha defaults to 0 (no noise). Adding it
//   later only needs a PRNG + np.random.dirichlet equivalent.
// - _pick_untried uses random.choice at non-root nodes on Python; we
//   deterministically pick the first untried move instead. Matching
//   Python's Mersenne Twister bit-for-bit would be real work for zero
//   gameplay value — every untried move gets expanded given enough
//   simulations regardless of order.
// - The VCT shortcut in getMoveProbabilities mirrors a Python quirk:
//   max_depth=6 is hard-coded, NOT self.vcf_depth. Preserved so diff
//   tests on shortcut-triggering positions pass.

/// Plugged in for hybrid/CNN MCTS. `policy` is length 225 (row * 15 +
/// col indexing); `value` is in [-1, 1] from the current player's POV.
public protocol NnModelAdapter: AnyObject {
	func predict(game: GameLogic) -> (policy: [Float], value: Double)
}

public final class MCTSNode {
	// Weak so children don't keep parents alive after the root is
	// released. Mirrors the GDScript tree-teardown fix from aadbefd.
	public weak var parent: MCTSNode?
	public var children: [MCTSNode] = []
	public var move: (row: Int, col: Int)?
	public var player: Int8
	public var visits: Int = 0
	public var wins: Double = 0.0
	public var untriedMoves: [(row: Int, col: Int)] = []
	public var prior: Double

	public init(parent: MCTSNode?, move: (row: Int, col: Int)?,
	            player: Int8, prior: Double = 1.0) {
		self.parent = parent
		self.move = move
		self.player = player
		self.prior = prior
	}

	public func puct(cPuct: Double = 1.4) -> Double {
		let q = visits == 0 ? 0.0 : wins / Double(visits)
		guard let parent = parent, parent.visits > 0 else {
			return q + cPuct * prior
		}
		let u = cPuct * prior * sqrt(Double(parent.visits))
			/ (1.0 + Double(visits))
		return q + u
	}

	public func bestChild(cPuct: Double = 1.4) -> MCTSNode {
		var best = children[0]
		var bestScore = best.puct(cPuct: cPuct)
		for i in 1..<children.count {
			let s = children[i].puct(cPuct: cPuct)
			if s > bestScore {
				bestScore = s
				best = children[i]
			}
		}
		return best
	}

	public func mostVisitedChild() -> MCTSNode {
		var best = children[0]
		for i in 1..<children.count where children[i].visits > best.visits {
			best = children[i]
		}
		return best
	}
}

public enum MCTS {

	/// _softmax_prior: max-normalise + scale-by-temperature + softmax.
	/// Inputs: (move, raw score) pairs. Negative scores clamped to 0.
	/// Output: same order as input with probabilities that sum to 1.
	/// Temperature=0.3 is the production value (peaked priors).
	public static func softmaxPrior(
		scores: [(move: (row: Int, col: Int), score: Double)],
		temperature: Double = 1.0
	) -> [(move: (row: Int, col: Int), prob: Double)] {
		if scores.isEmpty { return [] }

		var arr = scores.map { max(0.0, $0.score) }
		let peak = arr.max() ?? 0
		if peak > 0 {
			for i in 0..<arr.count { arr[i] /= peak }
		}
		let t = max(temperature, 1e-6)
		for i in 0..<arr.count { arr[i] /= t }
		let m = arr.max() ?? 0
		for i in 0..<arr.count { arr[i] -= m }

		var exps = arr.map { Foundation.exp($0) }
		var total = exps.reduce(0.0, +)
		if total <= 0 {
			exps = Array(repeating: 1.0, count: exps.count)
			total = Double(exps.count)
		}

		var result: [(move: (row: Int, col: Int), prob: Double)] = []
		result.reserveCapacity(scores.count)
		for i in 0..<scores.count {
			result.append((scores[i].move, exps[i] / total))
		}
		return result
	}
}

public final class MCTSEngine {
	public var simulations: Int
	public var nnModel: NnModelAdapter?
	public var cPuct: Double
	public var usePatternPrior: Bool
	public var dirichletAlpha: Double  // eval mode on iOS: always 0
	public var dirichletEps: Double
	public var vcfDepth: Int
	public var vcfBranch: Int
	public var cnnPriorWeight: Double

	public init(
		simulations: Int = 1000,
		nnModel: NnModelAdapter? = nil,
		cPuct: Double = 1.4,
		usePatternPrior: Bool = true,
		dirichletAlpha: Double = 0.0,
		dirichletEps: Double = 0.25,
		vcfDepth: Int = 10,
		vcfBranch: Int = 8,
		cnnPriorWeight: Double = 0.5
	) {
		self.simulations = simulations
		self.nnModel = nnModel
		self.cPuct = cPuct
		self.usePatternPrior = usePatternPrior
		self.dirichletAlpha = dirichletAlpha
		self.dirichletEps = dirichletEps
		self.vcfDepth = vcfDepth
		self.vcfBranch = vcfBranch
		self.cnnPriorWeight = cnnPriorWeight
	}

	public func chooseMove(game: GameLogic) -> (row: Int, col: Int) {
		let probs = getMoveProbabilities(game: game)
		var best = 0
		for i in 1..<probs.count where probs[i] > probs[best] {
			best = i
		}
		let n = GameLogic.boardSize
		return (best / n, best % n)
	}

	public func getMoveProbabilities(game: GameLogic) -> [Float] {
		let n = GameLogic.boardSize
		var candidates = game.nearbyMoves(radius: 2)
		if candidates.isEmpty {
			return onehot(row: 7, col: 7)
		}

		let player = game.currentPlayer
		let opponent: Int8 = player == 1 ? 2 : 1

		// Immediate win / must-block
		for m in candidates {
			game.setCell(m.row, m.col, player)
			if game.checkWin(at: m.row, col: m.col) {
				game.setCell(m.row, m.col, 0)
				return onehot(row: m.row, col: m.col)
			}
			game.setCell(m.row, m.col, 0)
		}
		for m in candidates {
			game.setCell(m.row, m.col, opponent)
			if game.checkWin(at: m.row, col: m.col) {
				game.setCell(m.row, m.col, 0)
				return onehot(row: m.row, col: m.col)
			}
			game.setCell(m.row, m.col, 0)
		}

		// VCF shortcut (self, then opponent — play opponent's VCF start
		// as our forced block).
		if vcfDepth > 0 {
			var board = game.board
			if let m = VcfSearch.findVcf(
					board: &board, attacker: player,
					maxDepth: vcfDepth, maxBranch: vcfBranch) {
				return onehot(row: m.row, col: m.col)
			}
			var oppBoard = game.board
			if let m = VcfSearch.findVcf(
					board: &oppBoard, attacker: opponent,
					maxDepth: vcfDepth, maxBranch: vcfBranch) {
				return onehot(row: m.row, col: m.col)
			}
		}

		// VCT shortcut — Python hard-codes max_depth=6 here regardless
		// of self.vcf_depth. Mirrored intentionally.
		if vcfDepth > 0 {
			var board = game.board
			if let m = VctSearch.findVct(
					board: &board, attacker: player,
					maxDepth: 6, maxBranch: vcfBranch) {
				return onehot(row: m.row, col: m.col)
			}
			var oppBoard = game.board
			if let m = VctSearch.findVct(
					board: &oppBoard, attacker: opponent,
					maxDepth: 6, maxBranch: vcfBranch) {
				return onehot(row: m.row, col: m.col)
			}
		}

		// Compute priors over candidates (flat 225-length lookup)
		var priors = computePriors(
			game: game, candidates: candidates, player: player)

		// Prune to top-12 by prior
		if candidates.count > 12 {
			let scored = candidates.map { m in
				(m, priors[GameLogic.idx(m.row, m.col)])
			}
			let top = scored.sorted { $0.1 > $1.1 }.prefix(12)
			candidates = top.map { $0.0 }
			var total = 0.0
			for m in candidates { total += priors[GameLogic.idx(m.row, m.col)] }
			if total > 0 {
				for m in candidates {
					priors[GameLogic.idx(m.row, m.col)] /= total
				}
			}
		}

		// Skipped: Dirichlet noise. iOS eval mode → dirichletAlpha=0.

		// MCTS main loop
		let root = MCTSNode(parent: nil, move: nil, player: opponent)
		root.untriedMoves = candidates

		for _ in 0..<simulations {
			let simGame = game.copy()
			var node = root

			// Selection
			while node.untriedMoves.isEmpty && !node.children.isEmpty {
				node = node.bestChild(cPuct: cPuct)
				if let m = node.move {
					_ = simGame.placeStone(m.row, m.col)
				}
			}

			// Expansion
			if !node.untriedMoves.isEmpty && !simGame.gameOver {
				let move = pickUntried(
					node: node, priors: priors, isRoot: node === root)
				if let idx = node.untriedMoves.firstIndex(where: {
					$0.row == move.row && $0.col == move.col
				}) {
					node.untriedMoves.remove(at: idx)
				}
				_ = simGame.placeStone(move.row, move.col)
				let childPrior: Double
				if node === root {
					let p = priors[GameLogic.idx(move.row, move.col)]
					childPrior = p > 0 ? p : 1.0 / Double(max(candidates.count, 1))
				} else {
					childPrior = 0.1
				}
				let child = MCTSNode(
					parent: node, move: move,
					player: simGame.currentPlayer, prior: childPrior)
				if !simGame.gameOver {
					let childCands = simGame.nearbyMoves(radius: 1)
					child.untriedMoves = Array(childCands.prefix(8))
				}
				node.children.append(child)
				node = child
			}

			// Leaf evaluation
			var resultValue: Double = 0
			var intWinner: Int8 = 0
			var valueIsScalar: Bool = true

			if simGame.gameOver {
				if simGame.winner == player {
					resultValue = 1.0
				} else if simGame.winner == 0 {
					resultValue = 0.0
				} else {
					resultValue = -1.0
				}
			} else if let nn = nnModel, !usePatternPrior {
				let (_, v) = nn.predict(game: simGame)
				resultValue = v
			} else if usePatternPrior {
				resultValue = continuousLeafValue(
					game: simGame, perspective: player)
			} else {
				intWinner = staticLeafValue(game: simGame)
				valueIsScalar = false
			}

			backprop(node: node,
			         resultValue: resultValue, intWinner: intWinner,
			         valueIsScalar: valueIsScalar, perspective: player)
		}

		// Extract visit-count policy
		var probs = Array(repeating: Float(0), count: n * n)
		var totalVisits = 0
		for c in root.children { totalVisits += c.visits }
		if totalVisits > 0 {
			for c in root.children {
				if let m = c.move {
					probs[m.row * n + m.col] = Float(c.visits) / Float(totalVisits)
				}
			}
		} else {
			// Fallback: priors directly
			for m in candidates {
				probs[m.row * n + m.col] = Float(priors[GameLogic.idx(m.row, m.col)])
			}
		}
		return probs
	}

	// Public so diff tests can target it directly.
	public func computePriors(
		game: GameLogic,
		candidates: [(row: Int, col: Int)],
		player: Int8
	) -> [Double] {
		let n = GameLogic.boardSize
		var result = Array(repeating: 0.0, count: n * n)

		var nnPriors: [Double]? = nil
		if let nn = nnModel {
			let (policy, _) = nn.predict(game: game)
			var tmp = Array(repeating: 0.0, count: n * n)
			var total = 0.0
			for m in candidates {
				let v = Double(policy[m.row * n + m.col])
				tmp[m.row * n + m.col] = v
				total += v
			}
			if total > 0 {
				for m in candidates {
					tmp[m.row * n + m.col] /= total
				}
				nnPriors = tmp
			}
		}

		var patPriors: [Double]? = nil
		if usePatternPrior {
			let scored = candidates.map { m -> (move: (row: Int, col: Int), score: Double) in
				(m, PatternEval.scoreCell(
					board: game.board, row: m.row, col: m.col, player: player))
			}
			let soft = MCTS.softmaxPrior(scores: scored, temperature: 0.3)
			var tmp = Array(repeating: 0.0, count: n * n)
			for s in soft {
				tmp[s.move.row * n + s.move.col] = s.prob
			}
			patPriors = tmp
		}

		if let nn = nnPriors, let pat = patPriors {
			let w = cnnPriorWeight
			var total = 0.0
			for m in candidates {
				let idx = m.row * n + m.col
				result[idx] = w * nn[idx] + (1 - w) * pat[idx]
				total += result[idx]
			}
			if total > 0 {
				for m in candidates {
					result[m.row * n + m.col] /= total
				}
			}
			return result
		}
		if let nn = nnPriors { return nn }
		if let pat = patPriors { return pat }

		let uniform = 1.0 / Double(candidates.count)
		for m in candidates {
			result[m.row * n + m.col] = uniform
		}
		return result
	}

	public func staticLeafValue(game: GameLogic) -> Int8 {
		if game.gameOver { return game.winner }

		let player = game.currentPlayer
		let opponent: Int8 = player == 1 ? 2 : 1
		let candidates = game.nearbyMoves(radius: 1)
		if candidates.isEmpty { return 0 }

		for m in candidates {
			game.setCell(m.row, m.col, player)
			if game.checkWin(at: m.row, col: m.col) {
				game.setCell(m.row, m.col, 0)
				return player
			}
			game.setCell(m.row, m.col, 0)
		}
		for m in candidates {
			game.setCell(m.row, m.col, opponent)
			if game.checkWin(at: m.row, col: m.col) {
				game.setCell(m.row, m.col, 0)
				return opponent
			}
			game.setCell(m.row, m.col, 0)
		}

		var bestSelf = 0.0
		var bestOpp = 0.0
		let scan = candidates.count <= 10
			? candidates : Array(candidates.prefix(10))
		for m in scan {
			let s = PatternEval.scoreCell(
				board: game.board, row: m.row, col: m.col, player: player)
			if s > bestSelf { bestSelf = s }
			let o = PatternEval.scoreCell(
				board: game.board, row: m.row, col: m.col, player: opponent)
			if o > bestOpp { bestOpp = o }
		}

		if bestOpp > bestSelf * 1.5 && bestOpp >= 1000 { return opponent }
		if bestSelf > bestOpp * 1.5 && bestSelf >= 1000 { return player }
		return 0
	}

	public func continuousLeafValue(
		game: GameLogic, perspective: Int8
	) -> Double {
		if game.gameOver {
			if game.winner == perspective { return 1.0 }
			if game.winner == 0 { return 0.0 }
			return -1.0
		}

		let player = game.currentPlayer
		let opponent: Int8 = player == 1 ? 2 : 1
		let candidates = game.nearbyMoves(radius: 1)
		if candidates.isEmpty { return 0.0 }

		for m in candidates {
			game.setCell(m.row, m.col, player)
			if game.checkWin(at: m.row, col: m.col) {
				game.setCell(m.row, m.col, 0)
				return player == perspective ? 1.0 : -1.0
			}
			game.setCell(m.row, m.col, 0)
		}
		for m in candidates {
			game.setCell(m.row, m.col, opponent)
			if game.checkWin(at: m.row, col: m.col) {
				game.setCell(m.row, m.col, 0)
				return player == perspective ? -0.8 : 0.8
			}
			game.setCell(m.row, m.col, 0)
		}

		let scan = candidates.count <= 12
			? candidates : Array(candidates.prefix(12))
		var myBest = 0.0
		var oppBest = 0.0
		for m in scan {
			let s = PatternEval.scoreCell(
				board: game.board, row: m.row, col: m.col, player: player)
			if s > myBest { myBest = s }
			let o = PatternEval.scoreCell(
				board: game.board, row: m.row, col: m.col, player: opponent)
			if o > oppBest { oppBest = o }
		}

		let diff = myBest - oppBest
		let advantage = tanh(diff / 1000.0) * 0.8
		return player == perspective ? advantage : -advantage
	}

	private func pickUntried(
		node: MCTSNode, priors: [Double], isRoot: Bool
	) -> (row: Int, col: Int) {
		if isRoot {
			// Argmax over priors — deterministic and matches Python's
			// max(..., key=lambda m: root_priors.get(m, 0.0)).
			var best = node.untriedMoves[0]
			var bestP = priors[GameLogic.idx(best.row, best.col)]
			for i in 1..<node.untriedMoves.count {
				let m = node.untriedMoves[i]
				let p = priors[GameLogic.idx(m.row, m.col)]
				if p > bestP {
					bestP = p
					best = m
				}
			}
			return best
		}
		// Non-root: Python uses random.choice; we take index 0 for a
		// deterministic, diff-testable walk. Gameplay impact minimal —
		// every untried move still gets expanded given enough sims.
		return node.untriedMoves[0]
	}

	private func backprop(
		node: MCTSNode, resultValue: Double, intWinner: Int8,
		valueIsScalar: Bool, perspective: Int8
	) {
		var cur: MCTSNode? = node
		while let n = cur {
			n.visits += 1
			if valueIsScalar {
				if n.player == perspective {
					n.wins += (1.0 - resultValue) / 2.0
				} else {
					n.wins += (1.0 + resultValue) / 2.0
				}
			} else {
				if intWinner == n.player {
					n.wins += 1.0
				} else if intWinner == 0 {
					n.wins += 0.5
				}
			}
			cur = n.parent
		}
	}

	private func onehot(row: Int, col: Int) -> [Float] {
		let n = GameLogic.boardSize
		var probs = Array(repeating: Float(0), count: n * n)
		probs[row * n + col] = 1.0
		return probs
	}
}
