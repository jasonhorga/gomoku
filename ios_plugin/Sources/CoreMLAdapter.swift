import Foundation
import CoreML

// Bridges a compiled CoreML model (GomokuNet.mlmodelc) to MCTSEngine's
// NnModelAdapter protocol. On iOS, L6 uses this to run the same hybrid
// (CNN + pattern) MCTS that Mac's Python onnx_server delivers — the
// whole point of P2+ was keeping iOS strength on par with Mac Python.
//
// The .mlmodelc directory is produced from best_model.pt by:
//   python3 export_coreml.py → .mlpackage
//   xcrun coremlc compile    → .mlmodelc
// Bundled into the iOS .app via a post-Godot-export xcodeproj
// injection (ios.yml). Loading compiled form at runtime skips the
// first-launch compile stall and runs ANE-friendly FP16 math.
//
// Input layout (9, 15, 15), matches ai/game_logic.py:to_tensor_9ch:
//   0: own stones           6: opp open_four mask
//   1: opp stones           7: opp open_three mask
//   2: self five mask       8: last-move indicator
//   3: self open_four mask
//   4: self open_three mask
//   5: opp five mask
//
// Output: log_policy (1, 225), value (1, 1). Policy post-processing
// mirrors onnx_server.py order (exp → mask invalid → normalize) so a
// masked-out invalid move doesn't get non-zero weight from softmax.

public final class CoreMLAdapter: NnModelAdapter {

	private let model: MLModel
	private let inputName: String

	public init?(modelURL: URL) {
		// modelURL is a .mlmodelc directory. If a .mlpackage is passed
		// instead, MLModel will compile on-demand (slower first call).
		do {
			self.model = try MLModel(contentsOf: modelURL)
		} catch {
			NSLog("CoreMLAdapter: failed to load model at %@: %@",
			      modelURL.path, error.localizedDescription)
			return nil
		}

		// Input name from the exported model. export_coreml.py sets it
		// to "board"; read it back so a rename doesn't silently break us.
		guard let name = model.modelDescription.inputDescriptionsByName.keys.first else {
			NSLog("CoreMLAdapter: model has no inputs")
			return nil
		}
		self.inputName = name
	}

	public func predict(game: GameLogic) -> (policy: [Float], value: Double) {
		let planes = Self.makeNineChannelInput(game: game)
		let fallback: (policy: [Float], value: Double) = (
			Array(repeating: 1.0 / 225.0, count: 225), 0.0
		)

		guard let arr = try? MLMultiArray(shape: [1, 9, 15, 15], dataType: .float32) else {
			return fallback
		}

		// MLMultiArray.dataPointer is row-major contiguous for a
		// dense Float32 shape. Bulk-copy instead of NSNumber per cell.
		let ptr = arr.dataPointer.bindMemory(
			to: Float32.self, capacity: planes.count)
		planes.withUnsafeBufferPointer { src in
			ptr.update(from: src.baseAddress!, count: src.count)
		}

		let provider: MLFeatureProvider
		do {
			provider = try MLDictionaryFeatureProvider(
				dictionary: [inputName: MLFeatureValue(multiArray: arr)])
		} catch {
			return fallback
		}

		guard let out = try? model.prediction(from: provider) else {
			return fallback
		}

		// Output names may be "log_policy"/"value" or generic indices
		// depending on how coremltools named them. Pull first two outputs
		// and assume (policy, value) in declaration order.
		let outNames = out.featureNames
		var logPolicyArr: MLMultiArray? = nil
		var valueArr: MLMultiArray? = nil
		for name in outNames {
			guard let feat = out.featureValue(for: name)?.multiArrayValue else { continue }
			if name.contains("policy") || feat.count == 225 {
				logPolicyArr = feat
			} else {
				valueArr = feat
			}
		}
		guard let logPolicy = logPolicyArr, let valueFeature = valueArr else {
			return fallback
		}

		// Python reference (onnx_server.py predict):
		//   policy = exp(log_policy)
		//   policy *= valid_mask
		//   policy /= policy.sum()   (or uniform over valid if sum==0)
		// Mask-before-normalise matters — otherwise an invalid move with
		// high logit pulls probability from real candidates.
		var policy = [Float](repeating: 0, count: 225)
		for i in 0..<225 {
			policy[i] = Foundation.expf(Float(truncating: logPolicy[i]))
		}
		for i in 0..<225 {
			let r = i / 15
			let c = i % 15
			if game.board[GameLogic.idx(r, c)] != 0 {
				policy[i] = 0  // occupied → invalid
			}
		}
		var sum: Float = 0
		for p in policy { sum += p }
		if sum > 0 {
			for i in 0..<225 { policy[i] /= sum }
		} else {
			// All-zero (nothing legal, rare) → uniform over empty cells.
			var emptyCount: Float = 0
			for i in 0..<225 {
				let r = i / 15
				let c = i % 15
				if game.board[GameLogic.idx(r, c)] == 0 { emptyCount += 1 }
			}
			if emptyCount > 0 {
				let u: Float = 1.0 / emptyCount
				for i in 0..<225 {
					let r = i / 15
					let c = i % 15
					policy[i] = game.board[GameLogic.idx(r, c)] == 0 ? u : 0
				}
			}
		}

		let value = Double(truncating: valueFeature[0])
		return (policy, value)
	}

	/// Build the (9, 15, 15) network input as a flat [Float] in
	/// channel-row-col order. Matches ai/game_logic.py:to_tensor_9ch.
	public static func makeNineChannelInput(game: GameLogic) -> [Float] {
		let n = GameLogic.boardSize
		let planeSize = n * n
		let total = 9 * planeSize
		var out = [Float](repeating: 0, count: total)

		let player = game.currentPlayer
		let opp: Int8 = player == 1 ? 2 : 1

		// 0: own, 1: opp — one-hot stone planes.
		for r in 0..<n {
			for c in 0..<n {
				let v = game.board[GameLogic.idx(r, c)]
				if v == player { out[0 * planeSize + r * n + c] = 1 }
				else if v == opp { out[1 * planeSize + r * n + c] = 1 }
			}
		}

		// 2–7: six pattern masks (flat layout, 6 * 225).
		let patternPlanes = PatternEval.makeFeaturePlanes(
			board: game.board, currentPlayer: player)
		for i in 0..<(6 * planeSize) {
			out[2 * planeSize + i] = patternPlanes[i]
		}

		// 8: last-move one-hot.
		if let last = game.moveHistory.last {
			out[8 * planeSize + last.row * n + last.col] = 1
		}

		return out
	}
}
