// PenFilter — smoothing and click stabilisation in tablet units (100 units ≈ 1 mm on CTL-470).
// Stands in for the legacy driver's stylus filters (CCT_PressureStylus::InitFilters / DefaultHysteresis)
// and double-click assist (CTransducer::CheckDoubleClickAssist).

import Foundation

/// One Euro filter: heavy smoothing when the pen is slow, little lag when it is fast.
struct OneEuroFilter {
    var minCutoff = 1.0
    var beta = 0.02
    var derivativeCutoff = 1.0
    private var value: Double?
    private var derivative = 0.0
    private var lastTime: TimeInterval = 0

    mutating func reset() { value = nil }

    mutating func filter(_ x: Double, at time: TimeInterval) -> Double {
        guard let previous = value else {
            value = x
            lastTime = time
            return x
        }
        let dt = max(time - lastTime, 1.0 / 1000)
        lastTime = time
        let rawDerivative = (x - previous) / dt
        derivative += Self.alpha(derivativeCutoff, dt) * (rawDerivative - derivative)
        let cutoff = minCutoff + beta * abs(derivative)
        let next = previous + Self.alpha(cutoff, dt) * (x - previous)
        value = next
        return next
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

struct PenFilter {
    /// For this long after touch-down the cursor holds still, so a tap's wobble stays a click...
    var clickSnapDuration: TimeInterval = 0.15
    /// ...unless the pen travels further than this (tablet units), which is clearly a stroke.
    var clickSnapRadius = 250.0
    private var fx = OneEuroFilter()
    private var fy = OneEuroFilter()
    private var anchor: (x: Double, y: Double, time: TimeInterval)?
    private var released = false

    mutating func reset() {
        fx.reset()
        fy.reset()
        anchor = nil
        released = false
    }

    /// Returns the stabilised position in tablet units.
    mutating func position(x: Int, y: Int, tip: Bool, at time: TimeInterval) -> (x: Double, y: Double) {
        let smoothed = (x: fx.filter(Double(x), at: time), y: fy.filter(Double(y), at: time))
        guard tip else {
            anchor = nil
            released = false
            return smoothed
        }
        guard let a = anchor else {
            anchor = (smoothed.x, smoothed.y, time)
            return smoothed
        }
        if !released && time - a.time < clickSnapDuration
            && hypot(smoothed.x - a.x, smoothed.y - a.y) < clickSnapRadius {
            return (a.x, a.y)
        }
        released = true
        return smoothed
    }
}
