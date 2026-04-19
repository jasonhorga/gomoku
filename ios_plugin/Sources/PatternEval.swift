import Foundation

// Swift port of ai/pattern_eval.py. Pure functions over GameLogic's
// flat [Int8] board — no shared state, deterministic. Every method's
// output is checked cell-by-cell against the Python reference in
// ios_plugin/tests/run_diff_tests.py.

public struct Threats: Equatable {
	public var five: Bool = false
	public var openFour: Bool = false
	public var halfFour: Bool = false
	public var openThree: Bool = false
	public var halfThree: Bool = false
}

public enum PatternEval {

	public struct Weights {
		public let five: Double
		public let openFour: Double
		public let halfFour: Double
		public let openThree: Double
		public let halfThree: Double
		public let openTwo: Double
		public let halfTwo: Double

		public init(
			five: Double, openFour: Double, halfFour: Double,
			openThree: Double, halfThree: Double,
			openTwo: Double, halfTwo: Double
		) {
			self.five = five
			self.openFour = openFour
			self.halfFour = halfFour
			self.openThree = openThree
			self.halfThree = halfThree
			self.openTwo = openTwo
			self.halfTwo = halfTwo
		}

		public static let `default` = Weights(
			five: 100000.0,
			openFour: 10000.0,
			halfFour: 1000.0,
			openThree: 1000.0,
			halfThree: 100.0,
			openTwo: 100.0,
			halfTwo: 10.0
		)
	}

	// v2 tuning — matches ai/pattern_eval.py constants.
	public static let defenseWeight: Double = 0.8
	public static let doubleThreatBonus: Double = 3.0
	public static let strongPatternThreshold: Double = 900.0

	// MARK: - Primitives

	/// Returns (count, isOpen) — `count` consecutive `player` stones
	/// starting one step past (row, col) in the direction, `isOpen=1`
	/// if the cell immediately after those stones is empty (else 0).
	@inlinable
	public static func countConsecutive(
		board: [Int8], row: Int, col: Int,
		dRow: Int, dCol: Int, player: Int8
	) -> (count: Int, isOpen: Int) {
		var count = 0
		var r = row + dRow
		var c = col + dCol
		while r >= 0 && r < GameLogic.boardSize
				&& c >= 0 && c < GameLogic.boardSize
				&& board[GameLogic.idx(r, c)] == player {
			count += 1
			r += dRow
			c += dCol
		}
		var isOpen = 0
		if r >= 0 && r < GameLogic.boardSize
				&& c >= 0 && c < GameLogic.boardSize
				&& board[GameLogic.idx(r, c)] == 0 {
			isOpen = 1
		}
		return (count, isOpen)
	}

	public struct ScanResult {
		public let consecutive: Int
		public let gapStones: Int
		public let endOpen: Int
		public let gapCell: (row: Int, col: Int)?
	}

	/// Scan one direction for consecutive stones + an optional gap +
	/// stones beyond the gap. Used for split-three / split-four detection.
	public static func scanLine(
		board: [Int8], row: Int, col: Int,
		dRow: Int, dCol: Int, player: Int8
	) -> ScanResult {
		var cons = 0
		var r = row + dRow
		var c = col + dCol
		while r >= 0 && r < GameLogic.boardSize
				&& c >= 0 && c < GameLogic.boardSize
				&& board[GameLogic.idx(r, c)] == player {
			cons += 1
			r += dRow
			c += dCol
		}

		var endOpen = 0
		var gapStones = 0
		var gapCell: (Int, Int)? = nil

		if r >= 0 && r < GameLogic.boardSize
				&& c >= 0 && c < GameLogic.boardSize
				&& board[GameLogic.idx(r, c)] == 0 {
			endOpen = 1
			var nr = r + dRow
			var nc = c + dCol
			if nr >= 0 && nr < GameLogic.boardSize
					&& nc >= 0 && nc < GameLogic.boardSize
					&& board[GameLogic.idx(nr, nc)] == player {
				gapCell = (r, c)
				while nr >= 0 && nr < GameLogic.boardSize
						&& nc >= 0 && nc < GameLogic.boardSize
						&& board[GameLogic.idx(nr, nc)] == player {
					gapStones += 1
					nr += dRow
					nc += dCol
				}
			}
		}

		return ScanResult(consecutive: cons, gapStones: gapStones, endOpen: endOpen, gapCell: gapCell)
	}

	// MARK: - Scoring

	@inlinable
	public static func gappedScore(totalWithGap: Int, weights: Weights = .default) -> Double {
		if totalWithGap >= 4 { return weights.halfFour }
		if totalWithGap == 3 { return weights.halfThree }
		return 0.0
	}

	@inlinable
	public static func patternScore(count: Int, openEnds: Int, weights: Weights = .default) -> Double {
		if count >= 5 { return weights.five }
		if openEnds == 0 { return 0.0 }
		if count == 4 { return openEnds == 2 ? weights.openFour : weights.halfFour }
		if count == 3 { return openEnds == 2 ? weights.openThree : weights.halfThree }
		if count == 2 { return openEnds == 2 ? weights.openTwo : weights.halfTwo }
		if count == 1 { return 1.0 }
		return 0.0
	}

	/// Score that would be produced by placing `player` at (row, col),
	/// summing per-direction contributions and applying the
	/// double-threat multiplier.
	public static func evaluatePosition(
		board: [Int8], row: Int, col: Int, player: Int8,
		weights: Weights = .default
	) -> Double {
		var perDir: [Double] = []
		perDir.reserveCapacity(GameLogic.directions.count)

		for (dr, dc) in GameLogic.directions {
			let pos = scanLine(board: board, row: row, col: col, dRow: dr, dCol: dc, player: player)
			let neg = scanLine(board: board, row: row, col: col, dRow: -dr, dCol: -dc, player: player)

			let conTotal = 1 + pos.consecutive + neg.consecutive
			let conScore = patternScore(count: conTotal, openEnds: pos.endOpen + neg.endOpen, weights: weights)

			var gapScore: Double = 0.0
			if pos.gapStones > 0 {
				gapScore = max(gapScore, gappedScore(totalWithGap: 1 + pos.consecutive + neg.consecutive + pos.gapStones, weights: weights))
			}
			if neg.gapStones > 0 {
				gapScore = max(gapScore, gappedScore(totalWithGap: 1 + pos.consecutive + neg.consecutive + neg.gapStones, weights: weights))
			}

			perDir.append(max(conScore, gapScore))
		}

		var total = perDir.reduce(0.0, +)
		let strongCount = perDir.reduce(0) { $0 + ($1 >= strongPatternThreshold ? 1 : 0) }
		if strongCount >= 2 {
			total *= doubleThreatBonus
		}
		return total
	}

	/// Offense + defense blend for an empty cell, with forced-block and
	/// forced-win escalation matching Python.
	public static func scoreCell(
		board: [Int8], row: Int, col: Int, player: Int8,
		weights: Weights = .default
	) -> Double {
		if board[GameLogic.idx(row, col)] != 0 { return 0.0 }
		let opponent: Int8 = (player == Stone.black.rawValue)
			? Stone.white.rawValue
			: Stone.black.rawValue
		let attack = evaluatePosition(board: board, row: row, col: col, player: player, weights: weights)
		let defend = evaluatePosition(board: board, row: row, col: col, player: opponent, weights: weights)

		if defend >= weights.openFour {
			return defend * 2.0 + attack
		}
		if attack >= weights.openFour {
			return attack * 2.0 + defend
		}
		return attack + defend * defenseWeight
	}

	/// Returns nil if (row, col) is occupied; otherwise a struct of
	/// which pattern types would be created by placing `player` there.
	public static func detectThreats(
		board: [Int8], row: Int, col: Int, player: Int8
	) -> Threats? {
		if board[GameLogic.idx(row, col)] != 0 { return nil }

		var result = Threats()
		for (dr, dc) in GameLogic.directions {
			let pos = scanLine(board: board, row: row, col: col, dRow: dr, dCol: dc, player: player)
			let neg = scanLine(board: board, row: row, col: col, dRow: -dr, dCol: -dc, player: player)

			let count = 1 + pos.consecutive + neg.consecutive
			let openEnds = pos.endOpen + neg.endOpen

			if count >= 5 {
				result.five = true
			} else if count == 4 {
				if openEnds == 2 { result.openFour = true }
				else if openEnds == 1 { result.halfFour = true }
			} else if count == 3 {
				if openEnds == 2 { result.openThree = true }
				else if openEnds == 1 { result.halfThree = true }
			}

			for gap in [pos.gapStones, neg.gapStones] {
				if gap > 0 {
					let gapTotal = 1 + pos.consecutive + neg.consecutive + gap
					if gapTotal >= 4 { result.halfFour = true }
					else if gapTotal == 3 { result.halfThree = true }
				}
			}
		}
		return result
	}

	/// Build the 6-channel pattern feature tensor for the CNN input.
	/// Layout: channel-major, row-major within each channel; flat size
	/// 6 * 15 * 15 = 1350 Floats.
	///
	///   0: self can make five
	///   1: self can make open_four
	///   2: self can make open_three
	///   3: opponent can make five
	///   4: opponent can make open_four
	///   5: opponent can make open_three
	public static func makeFeaturePlanes(board: [Int8], currentPlayer: Int8) -> [Float] {
		let size = GameLogic.boardSize
		let opponent: Int8 = (currentPlayer == Stone.black.rawValue)
			? Stone.white.rawValue
			: Stone.black.rawValue
		var planes = [Float](repeating: 0, count: 6 * size * size)

		for r in 0..<size {
			for c in 0..<size {
				if board[GameLogic.idx(r, c)] != 0 { continue }
				if let selfT = detectThreats(board: board, row: r, col: c, player: currentPlayer) {
					if selfT.five { planes[0 * size * size + r * size + c] = 1 }
					if selfT.openFour { planes[1 * size * size + r * size + c] = 1 }
					if selfT.openThree { planes[2 * size * size + r * size + c] = 1 }
				}
				if let oppT = detectThreats(board: board, row: r, col: c, player: opponent) {
					if oppT.five { planes[3 * size * size + r * size + c] = 1 }
					if oppT.openFour { planes[4 * size * size + r * size + c] = 1 }
					if oppT.openThree { planes[5 * size * size + r * size + c] = 1 }
				}
			}
		}
		return planes
	}
}
