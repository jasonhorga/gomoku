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
