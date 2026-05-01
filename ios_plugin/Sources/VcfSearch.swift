import Foundation

// Port of ai_server/ai/vcf_search.py. Finds forced-win sequences made
// entirely of four-threats: the opponent is compelled to block (or lose),
// so branching stays ~1-4 and depth-10 search runs in milliseconds.
//
// Shape intentionally mirrors Python so the diff tester can compare
// output directly. Board is passed as `inout [Int8]` (flat row-major
// 15×15) and mutated during recursion, restored before each function
// returns — exactly what the Python code does with 2D lists.

public enum VcfSearch {

	public enum FourKind: Int {
		case five = 3, openFour = 2, halfFour = 1
	}

	public struct FourInfo {
		public let kind: FourKind?
		public let blockCells: [(row: Int, col: Int)]
	}

	/// Does placing `player` at (row, col) complete five in a row?
	public static func makesFive(
		board: [Int8], row: Int, col: Int, player: Int8
	) -> Bool {
		for (dr, dc) in GameLogic.directions {
			let pos = PatternEval.countConsecutive(
				board: board, row: row, col: col,
				dRow: dr, dCol: dc, player: player)
			let neg = PatternEval.countConsecutive(
				board: board, row: row, col: col,
				dRow: -dr, dCol: -dc, player: player)
			if 1 + pos.count + neg.count >= 5 {
				return true
			}
		}
		return false
	}

	/// After placing `player` at (row, col), describe any four-threats it
	/// creates (consecutive open/half fours AND gapped 4+ stones that a
	/// single opponent move must block to prevent a five). block_cells is
	/// the set of cells the defender has to play to stop the five.
	public static func fourInfo(
		board: [Int8], row: Int, col: Int, player: Int8
	) -> FourInfo {
		var bestKind: FourKind? = nil
		var blockCells: [(row: Int, col: Int)] = []

		for (dr, dc) in GameLogic.directions {
			let pos = PatternEval.scanLine(
				board: board, row: row, col: col,
				dRow: dr, dCol: dc, player: player)
			let neg = PatternEval.scanLine(
				board: board, row: row, col: col,
				dRow: -dr, dCol: -dc, player: player)

			// Consecutive patterns
			let total = 1 + pos.consecutive + neg.consecutive
			let openEnds = pos.endOpen + neg.endOpen
			if total >= 5 {
				return FourInfo(kind: .five, blockCells: [])
			}
			if total == 4 {
				var ends: [(row: Int, col: Int)] = []
				if pos.endOpen == 1 {
					ends.append((row + (pos.consecutive + 1) * dr,
					             col + (pos.consecutive + 1) * dc))
				}
				if neg.endOpen == 1 {
					ends.append((row - (neg.consecutive + 1) * dr,
					             col - (neg.consecutive + 1) * dc))
				}
				if openEnds == 2 {
					if bestKind != .five {
						bestKind = .openFour
					}
					blockCells.append(contentsOf: ends)
				} else if openEnds == 1 {
					if bestKind != .five && bestKind != .openFour {
						bestKind = .halfFour
					}
					blockCells.append(contentsOf: ends)
				}
			}

			// Gapped patterns — 4+ stones across one gap, filling the gap
			// makes five. Treated as half_four with the gap as block cell.
			if pos.gapStones > 0, let g = pos.gapCell {
				let gapTotal = 1 + pos.consecutive + neg.consecutive + pos.gapStones
				if gapTotal >= 4 {
					if bestKind != .five && bestKind != .openFour {
						bestKind = .halfFour
					}
					blockCells.append((g.row, g.col))
				}
			}
			if neg.gapStones > 0, let g = neg.gapCell {
				let gapTotal = 1 + pos.consecutive + neg.consecutive + neg.gapStones
				if gapTotal >= 4 {
					if bestKind != .five && bestKind != .openFour {
						bestKind = .halfFour
					}
					blockCells.append((g.row, g.col))
				}
			}
		}

		return FourInfo(kind: bestKind, blockCells: blockCells)
	}

	/// Empty cells within `radius` of any stone on the board. Returns the
	/// list sorted by (row, col) so iteration order matches Python's
	/// sorted(list(set(...))) — diff tests rely on this determinism.
	public static func candidateMoves(
		board: [Int8], radius: Int
	) -> [(row: Int, col: Int)] {
		let n = GameLogic.boardSize
		var packed = Set<Int>()
		var hasStone = false
		for r in 0..<n {
			for c in 0..<n {
				if board[GameLogic.idx(r, c)] != 0 {
					hasStone = true
					for dr in -radius...radius {
						for dc in -radius...radius {
							let nr = r + dr
							let nc = c + dc
							if nr >= 0 && nr < n && nc >= 0 && nc < n
									&& board[GameLogic.idx(nr, nc)] == 0 {
								packed.insert(nr * n + nc)
							}
						}
					}
				}
			}
		}
		if !hasStone {
			return [(n / 2, n / 2)]
		}
		return packed.sorted().map { ($0 / n, $0 % n) }
	}

	/// Search for a forced-win four sequence. Returns the first winning
	/// move (row, col) or nil. `board` is mutated during search but
	/// restored before return. Defaults mirror Python (depth 10, branch 8).
	public static func findVcf(
		board: inout [Int8], attacker: Int8,
		maxDepth: Int = 10, maxBranch: Int = 8,
		forbiddenEnabled: Bool = false
	) -> (row: Int, col: Int)? {
		return vcfRecurse(board: &board, attacker: attacker,
		                  depth: maxDepth, maxBranch: maxBranch,
		                  forbiddenEnabled: forbiddenEnabled)
	}

	static func isLegalMove(
		board: [Int8], row: Int, col: Int, player: Int8, forbiddenEnabled: Bool
	) -> Bool {
		if board[GameLogic.idx(row, col)] != 0 { return false }
		if !forbiddenEnabled || player != Stone.black.rawValue { return true }
		var tmpBoard = board
		return !RenjuForbidden.isForbiddenBlack(board: &tmpBoard, row: row, col: col)
	}

	static func legalFourThreat(
		board: [Int8], kind: FourKind?, blocks: [(row: Int, col: Int)],
		attacker: Int8, forbiddenEnabled: Bool
	) -> (kind: FourKind, blocks: [(row: Int, col: Int)])? {
		guard let threatKind = kind,
				threatKind == .openFour || threatKind == .halfFour else {
			return nil
		}
		if !forbiddenEnabled || attacker != Stone.black.rawValue {
			return (threatKind, blocks)
		}

		let legalBlocks = blocks.filter {
			isLegalMove(
				board: board, row: $0.row, col: $0.col, player: attacker,
				forbiddenEnabled: forbiddenEnabled)
		}
		let uniqueCount = Set(legalBlocks.map {
			$0.row * GameLogic.boardSize + $0.col
		}).count
		if uniqueCount == 0 { return nil }
		if threatKind == .openFour && uniqueCount < 2 {
			return (.halfFour, legalBlocks)
		}
		return (threatKind, legalBlocks)
	}

	private static func vcfRecurse(
		board: inout [Int8], attacker: Int8, depth: Int, maxBranch: Int,
		forbiddenEnabled: Bool
	) -> (row: Int, col: Int)? {
		if depth <= 0 { return nil }
		let defender: Int8 = attacker == 1 ? 2 : 1

		// Immediate five check.
		for (r, c) in candidateMoves(board: board, radius: 1) {
			if !isLegalMove(
					board: board, row: r, col: c, player: attacker,
					forbiddenEnabled: forbiddenEnabled) {
				continue
			}
			if makesFive(board: board, row: r, col: c, player: attacker) {
				return (r, c)
			}
		}

		// Collect four-threat moves, prioritised (open_four first).
		// priority 2 = open_four, 1 = half_four.
		var fourMoves: [(priority: Int, row: Int, col: Int,
		                 kind: FourKind, blocks: [(row: Int, col: Int)])] = []
		for (r, c) in candidateMoves(board: board, radius: 2) {
			if !isLegalMove(
					board: board, row: r, col: c, player: attacker,
					forbiddenEnabled: forbiddenEnabled) {
				continue
			}
			board[GameLogic.idx(r, c)] = attacker
			let info = fourInfo(board: board, row: r, col: c, player: attacker)
			let legalThreat = legalFourThreat(
				board: board, kind: info.kind, blocks: info.blockCells,
				attacker: attacker, forbiddenEnabled: forbiddenEnabled)
			board[GameLogic.idx(r, c)] = 0
			if let threat = legalThreat {
				let prio = threat.kind == .openFour ? 2 : 1
				fourMoves.append((prio, r, c, threat.kind, threat.blocks))
			}
		}

		// Sort desc by priority; stable tiebreak on (r, c) matches Python
		// since candidateMoves is already sorted.
		fourMoves.sort { $0.priority > $1.priority }
		if fourMoves.count > maxBranch {
			fourMoves = Array(fourMoves.prefix(maxBranch))
		}

		for (_, r, c, kind, blocks) in fourMoves {
			board[GameLogic.idx(r, c)] = attacker

			// Skip if defender wins immediately (five in one).
			var defenderWins = false
			for (dr, dc) in candidateMoves(board: board, radius: 1) {
				if !isLegalMove(
						board: board, row: dr, col: dc, player: defender,
						forbiddenEnabled: forbiddenEnabled) {
					continue
				}
				if makesFive(board: board, row: dr, col: dc, player: defender) {
					defenderWins = true
					break
				}
			}
			if defenderWins {
				board[GameLogic.idx(r, c)] = 0
				continue
			}

			if kind == .openFour {
				board[GameLogic.idx(r, c)] = 0
				return (r, c)
			}

			if blocks.isEmpty {
				board[GameLogic.idx(r, c)] = 0
				continue
			}

			// Try each forced block; if ALL recurse to a win, we've won.
			// Deduplicate blocks via packed int for Set semantics.
			var uniqBlocks = Set<Int>()
			for b in blocks { uniqBlocks.insert(b.row * GameLogic.boardSize + b.col) }

			var allBlocked = true
			for packed in uniqBlocks.sorted() {
				let br = packed / GameLogic.boardSize
				let bc = packed % GameLogic.boardSize
				if !isLegalMove(
						board: board, row: br, col: bc, player: defender,
						forbiddenEnabled: forbiddenEnabled) {
					continue
				}
				board[GameLogic.idx(br, bc)] = defender
				let sub = vcfRecurse(board: &board, attacker: attacker,
				                     depth: depth - 1, maxBranch: maxBranch,
				                     forbiddenEnabled: forbiddenEnabled)
				board[GameLogic.idx(br, bc)] = 0
				if sub == nil {
					allBlocked = false
					break
				}
			}

			board[GameLogic.idx(r, c)] = 0
			if allBlocked {
				return (r, c)
			}
		}

		return nil
	}
}
