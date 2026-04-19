import Foundation
import CoreGraphics

// P2b hello plugin: pure Swift class with @objc-exposed API.
// Returns hardcoded center-of-board (7,7) so we can prove the
// Godot → Obj-C++ → Swift chain end-to-end before plugging CoreML
// inference in (that's P2b.5 / folded into P2c).
@objc public class GomokuMLCore: NSObject {

    @objc public override init() {
        super.init()
    }

    /// Returns the move (row, col) packed into a CGPoint.
    /// `level` chooses strength (1-6) — hardcoded hello-world ignores it.
    @objc public func predict(level: Int) -> CGPoint {
        return CGPoint(x: 7, y: 7)
    }

    @objc public func version() -> NSString {
        return "GomokuMLCore P2b hello (hardcoded 7,7)"
    }
}
