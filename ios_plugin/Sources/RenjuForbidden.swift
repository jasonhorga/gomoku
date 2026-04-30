import Foundation

public enum RenjuForbidden {
	public static let boardSize = 15
	public static let empty: Int8 = 0
	public static let black: Int8 = 1
	public static let directions: [(dr: Int, dc: Int)] = [
		(0, 1), (1, 0), (1, 1), (1, -1),
	]

	public static func isForbiddenBlack(board: inout [Int8], row: Int, col: Int) -> Bool {
		if !isInside(row, col) { return false }
		let idx = index(row, col)
		if board[idx] != empty { return false }

		board[idx] = black
		let exactFive = hasExactFive(board: board, row: row, col: col)
		let overline = hasOverline(board: board, row: row, col: col)
		var openThreeCount = 0
		var fourCount = 0

		if !exactFive {
			for dir in directions {
				if lineHasFour(board: &board, row: row, col: col, dir: dir) {
					fourCount += 1
				}
				if lineHasOpenThree(board: &board, row: row, col: col, dir: dir) {
					openThreeCount += 1
				}
			}
		}

		board[idx] = empty

		if exactFive { return false }
		if overline { return true }
		if fourCount >= 2 { return true }
		return openThreeCount >= 2
	}

	public static func isExactFiveForBlack(board: [Int8], row: Int, col: Int) -> Bool {
		if !isInside(row, col) { return false }
		if board[index(row, col)] != black { return false }
		return hasExactFive(board: board, row: row, col: col)
	}

	private static func hasExactFive(board: [Int8], row: Int, col: Int) -> Bool {
		for dir in directions {
			if countLine(board: board, row: row, col: col, dir: dir, player: black) == 5 {
				return true
			}
		}
		return false
	}

	private static func hasOverline(board: [Int8], row: Int, col: Int) -> Bool {
		for dir in directions {
			if countLine(board: board, row: row, col: col, dir: dir, player: black) >= 6 {
				return true
			}
		}
		return false
	}

	private static func countLine(
		board: [Int8], row: Int, col: Int, dir: (dr: Int, dc: Int), player: Int8
	) -> Int {
		var count = 1
		count += countDir(board: board, row: row, col: col, dr: dir.dr, dc: dir.dc, player: player)
		count += countDir(board: board, row: row, col: col, dr: -dir.dr, dc: -dir.dc, player: player)
		return count
	}

	private static func countDir(
		board: [Int8], row: Int, col: Int, dr: Int, dc: Int, player: Int8
	) -> Int {
		var count = 0
		var r = row + dr
		var c = col + dc
		while isInside(r, c) && board[index(r, c)] == player {
			count += 1
			r += dr
			c += dc
		}
		return count
	}

	private static func lineHasFour(
		board: inout [Int8], row: Int, col: Int, dir: (dr: Int, dc: Int)
	) -> Bool {
		let empties = windowEmptyCells(board: board, row: row, col: col, dir: dir)
		for p in empties {
			let idx = index(p.row, p.col)
			board[idx] = black
			let makesFive = countLine(board: board, row: p.row, col: p.col, dir: dir, player: black) == 5
			board[idx] = empty
			if makesFive { return true }
		}
		return false
	}

	private static func lineHasOpenThree(
		board: inout [Int8], row: Int, col: Int, dir: (dr: Int, dc: Int)
	) -> Bool {
		let empties = windowEmptyCells(board: board, row: row, col: col, dir: dir)
		for p in empties {
			let idx = index(p.row, p.col)
			board[idx] = black
			let createsOpenFour = lineHasStraightOpenFour(board: &board, row: p.row, col: p.col, dir: dir)
			board[idx] = empty
			if createsOpenFour { return true }
		}
		return false
	}

	private static func lineHasStraightOpenFour(
		board: inout [Int8], row: Int, col: Int, dir: (dr: Int, dc: Int)
	) -> Bool {
		var runStart = (row: row, col: col)
		while isInside(runStart.row - dir.dr, runStart.col - dir.dc)
				&& board[index(runStart.row - dir.dr, runStart.col - dir.dc)] == black {
			runStart = (runStart.row - dir.dr, runStart.col - dir.dc)
		}

		var runEnd = (row: row, col: col)
		while isInside(runEnd.row + dir.dr, runEnd.col + dir.dc)
				&& board[index(runEnd.row + dir.dr, runEnd.col + dir.dc)] == black {
			runEnd = (runEnd.row + dir.dr, runEnd.col + dir.dc)
		}

		var length = 1
		var cur = runStart
		while cur.row != runEnd.row || cur.col != runEnd.col {
			length += 1
			cur = (cur.row + dir.dr, cur.col + dir.dc)
		}

		if length != 4 { return false }

		let before = (row: runStart.row - dir.dr, col: runStart.col - dir.dc)
		let after = (row: runEnd.row + dir.dr, col: runEnd.col + dir.dc)
		if !isInside(before.row, before.col) || !isInside(after.row, after.col) {
			return false
		}
		if board[index(before.row, before.col)] != empty || board[index(after.row, after.col)] != empty {
			return false
		}

		board[index(before.row, before.col)] = black
		let beforeExact = countLine(board: board, row: before.row, col: before.col, dir: dir, player: black) == 5
		board[index(before.row, before.col)] = empty

		board[index(after.row, after.col)] = black
		let afterExact = countLine(board: board, row: after.row, col: after.col, dir: dir, player: black) == 5
		board[index(after.row, after.col)] = empty

		return beforeExact && afterExact
	}

	private static func windowEmptyCells(
		board: [Int8], row: Int, col: Int, dir: (dr: Int, dc: Int)
	) -> [(row: Int, col: Int)] {
		var result: [(row: Int, col: Int)] = []
		for offset in -4...4 {
			let r = row + dir.dr * offset
			let c = col + dir.dc * offset
			if isInside(r, c) && board[index(r, c)] == empty {
				result.append((r, c))
			}
		}
		return result
	}

	private static func index(_ row: Int, _ col: Int) -> Int {
		return row * boardSize + col
	}

	private static func isInside(_ row: Int, _ col: Int) -> Bool {
		return row >= 0 && row < boardSize && col >= 0 && col < boardSize
	}
}
