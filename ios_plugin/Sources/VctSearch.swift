import Foundation

// Port of ai_server/ai/vct_search.py. Extends VCF by also considering
// open-three threats: a move that creates two open threes, or one four
// and one open three, is unstoppable and counts as a win. Mixed four+
// three sequences catch positions VCF misses.
//
// VCF is always tried first inside the recursion — it's strictly faster
// and any VCF line is also a VCT line.

public enum VctSearch {

	/// After placing `player` at (row, col), enumerate directions that
	/// formed an open three (3 consecutive, both ends open). For each,
	/// return the extension cells the attacker would play next to make
	/// a four — these double as the cells the defender must block.
	public static func openThrees(
		board: [Int8], row: Int, col: Int, player: Int8
	) -> [(dir: (Int, Int), extensions: [(row: Int, col: Int)])] {
		var result: [(dir: (Int, Int), extensions: [(row: Int, col: Int)])] = []
		for (dr, dc) in GameLogic.directions {
			let pos = PatternEval.countConsecutive(
				board: board, row: row, col: col,
				dRow: dr, dCol: dc, player: player)
			let neg = PatternEval.countConsecutive(
				board: board, row: row, col: col,
				dRow: -dr, dCol: -dc, player: player)
			let total = 1 + pos.count + neg.count
			let openEnds = pos.isOpen + neg.isOpen
			if total == 3 && openEnds == 2 {
				var ext: [(row: Int, col: Int)] = []
				if pos.isOpen == 1 {
					ext.append((row + (pos.count + 1) * dr,
					            col + (pos.count + 1) * dc))
				}
				if neg.isOpen == 1 {
					ext.append((row - (neg.count + 1) * dr,
					            col - (neg.count + 1) * dc))
				}
				result.append(((dr, dc), ext))
			}
		}
		return result
	}

	private static func defenderHasFive(
		board: [Int8], defender: Int8
	) -> Bool {
		for (r, c) in VcfSearch.candidateMoves(board: board, radius: 1) {
			if board[GameLogic.idx(r, c)] == 0
					&& VcfSearch.makesFive(
						board: board, row: r, col: c, player: defender) {
				return true
			}
		}
		return false
	}

	/// Search for a forced win using fours + threes. Tries VCF first at
	/// every level. Returns (row, col) or nil; mutates+restores `board`.
	public static func findVct(
		board: inout [Int8], attacker: Int8,
		maxDepth: Int = 6, maxBranch: Int = 6
	) -> (row: Int, col: Int)? {
		if let win = VcfSearch.findVcf(
				board: &board, attacker: attacker, maxDepth: maxDepth) {
			return win
		}
		return vctRecurse(board: &board, attacker: attacker,
		                  depth: maxDepth, maxBranch: maxBranch)
	}

	private static func vctRecurse(
		board: inout [Int8], attacker: Int8, depth: Int, maxBranch: Int
	) -> (row: Int, col: Int)? {
		if depth <= 0 { return nil }
		let defender: Int8 = attacker == 1 ? 2 : 1

		if let win = VcfSearch.findVcf(
				board: &board, attacker: attacker, maxDepth: depth) {
			return win
		}

		// Collect moves that create at least one open three, tagged with
		// whether they also create a four.
		var threatMoves: [(priority: Int, row: Int, col: Int,
		                   threes: [(dir: (Int, Int), extensions: [(row: Int, col: Int)])],
		                   hasFour: Bool)] = []
		for (r, c) in VcfSearch.candidateMoves(board: board, radius: 2) {
			if board[GameLogic.idx(r, c)] != 0 { continue }
			board[GameLogic.idx(r, c)] = attacker
			let threes = openThrees(
				board: board, row: r, col: c, player: attacker)
			let fourInfo = VcfSearch.fourInfo(
				board: board, row: r, col: c, player: attacker)
			board[GameLogic.idx(r, c)] = 0

			if threes.isEmpty { continue }

			let hasFour = fourInfo.kind == .openFour || fourInfo.kind == .halfFour
			let priority = threes.count * 10 + (hasFour ? 5 : 0)
			threatMoves.append((priority, r, c, threes, hasFour))
		}

		threatMoves.sort { $0.priority > $1.priority }
		if threatMoves.count > maxBranch {
			threatMoves = Array(threatMoves.prefix(maxBranch))
		}

		for (_, r, c, threes, hasFour) in threatMoves {
			board[GameLogic.idx(r, c)] = attacker

			if defenderHasFive(board: board, defender: defender) {
				board[GameLogic.idx(r, c)] = 0
				continue
			}

			// Double-three or four+three: defender can only block one.
			if threes.count >= 2 || (hasFour && !threes.isEmpty) {
				board[GameLogic.idx(r, c)] = 0
				return (r, c)
			}

			// Single open three — defender must block one of the
			// extension cells; if every block still loses, we win.
			var defenseCells = Set<Int>()
			for (_, exts) in threes {
				for cell in exts {
					if cell.row >= 0 && cell.row < GameLogic.boardSize
							&& cell.col >= 0 && cell.col < GameLogic.boardSize
							&& board[GameLogic.idx(cell.row, cell.col)] == 0 {
						defenseCells.insert(cell.row * GameLogic.boardSize + cell.col)
					}
				}
			}

			if defenseCells.isEmpty {
				board[GameLogic.idx(r, c)] = 0
				continue
			}

			var allWin = true
			for packed in defenseCells.sorted() {
				let defR = packed / GameLogic.boardSize
				let defC = packed % GameLogic.boardSize
				board[GameLogic.idx(defR, defC)] = defender
				let sub = vctRecurse(board: &board, attacker: attacker,
				                     depth: depth - 1, maxBranch: maxBranch)
				board[GameLogic.idx(defR, defC)] = 0
				if sub == nil {
					allWin = false
					break
				}
			}

			board[GameLogic.idx(r, c)] = 0
			if allWin {
				return (r, c)
			}
		}

		return nil
	}
}
