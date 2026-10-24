// PenEventPoster — turns decoded pen samples into macOS tablet-aware pointer events.
// Apps that read NSEvent pressure/proximity (Photoshop, Krita, Affinity, Preview markup) see a real pen.

import AppKit
import CoreGraphics

enum MappingArea: String, CaseIterable {
    case allDisplays = "All Displays"
    case mainDisplay = "Main Display"
}

final class PenEventPoster {
    var mappingArea: MappingArea = .allDisplays
    /// Map a centred region of the tablet with the screen's aspect ratio, so circles stay round.
    var keepProportions = true
    /// Raw pressure a stroke must exceed before it counts as a click; filters a resting tip.
    var tipThreshold = 8
    /// Taps closer than this (tablet units, ~3 mm) count toward a double-click.
    var doubleClickDistance = 300.0

    private let debugLogging = ProcessInfo.processInfo.environment["BAMBOO_DEBUG"] != nil
    private let source = CGEventSource(stateID: .hidSystemState)
    private var filter = PenFilter()
    private var inProximity = false
    private var tipDown = false
    private var lowerDown = false
    private var upperDown = false
    private var lastPoint = CGPoint.zero
    private var lastClickTime: TimeInterval = 0
    private var lastClickTabletPoint = (x: 0.0, y: 0.0)
    private var clickCount: Int64 = 1
    private let deviceID: Int64 = 1

    func post(_ sample: PenSample, model: TabletModel) {
        // Far hover (proximity without ready) reports coarse coordinates that make the cursor jump,
        // so the pen only counts as present once it is ready.
        let present = sample.inProximity && sample.ready
        if present != inProximity {
            if !present {
                releaseAll(model: model)
                filter.reset()
            }
            postProximity(entering: present, eraser: sample.eraser, model: model)
            inProximity = present
        }
        guard present else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let tip = sample.tip && sample.pressure > tipThreshold
        let tabletPoint = filter.position(x: sample.x, y: sample.y, tip: tip, at: now)
        let point = screenPoint(for: tabletPoint, model: model)
        lastPoint = point
        if debugLogging {
            print(String(format: "raw %5d,%5d p%4d tip%d -> screen %.0f,%.0f", sample.x, sample.y,
                         sample.pressure, tip ? 1 : 0, point.x, point.y))
        }
        let pressure = Double(sample.pressure) / Double(model.maxPressure)

        if tip != tipDown {
            if tip { updateClickCount(at: tabletPoint, time: now) }
            tipDown = tip
            postMouse(tip ? .leftMouseDown : .leftMouseUp, button: .left, at: point,
                      pressure: tip ? pressure : 0, sample: sample)
        } else if sample.lowerButton != lowerDown {
            lowerDown = sample.lowerButton
            postMouse(lowerDown ? .rightMouseDown : .rightMouseUp, button: .right, at: point,
                      pressure: pressure, sample: sample)
        } else if sample.upperButton != upperDown {
            upperDown = sample.upperButton
            postMouse(upperDown ? .otherMouseDown : .otherMouseUp, button: .center, at: point,
                      pressure: pressure, sample: sample)
        } else {
            let type: CGEventType = tipDown ? .leftMouseDragged
                : lowerDown ? .rightMouseDragged
                : upperDown ? .otherMouseDragged : .mouseMoved
            postMouse(type, button: tipDown ? .left : lowerDown ? .right : .center, at: point,
                      pressure: tipDown ? pressure : 0, sample: sample)
        }
    }

    private func releaseAll(model: TabletModel) {
        let blank = PenSample()
        if tipDown {
            tipDown = false
            postMouse(.leftMouseUp, button: .left, at: lastPoint, pressure: 0, sample: blank)
        }
        if lowerDown {
            lowerDown = false
            postMouse(.rightMouseUp, button: .right, at: lastPoint, pressure: 0, sample: blank)
        }
        if upperDown {
            upperDown = false
            postMouse(.otherMouseUp, button: .center, at: lastPoint, pressure: 0, sample: blank)
        }
    }

    private func mappedBounds() -> CGRect {
        switch mappingArea {
        case .mainDisplay:
            return CGDisplayBounds(CGMainDisplayID())
        case .allDisplays:
            var count: UInt32 = 0
            CGGetActiveDisplayList(0, nil, &count)
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
            CGGetActiveDisplayList(count, &displays, &count)
            return displays.map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
        }
    }

    /// Tablet region (in tablet units) that maps onto the screen bounds.
    private func activeRegion(model: TabletModel, screen: CGRect) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: model.maxX, height: model.maxY)
        guard keepProportions, screen.width > 0, screen.height > 0 else { return full }
        let screenAspect = screen.width / screen.height
        if full.width / full.height > screenAspect {
            let width = full.height * screenAspect
            return CGRect(x: (full.width - width) / 2, y: 0, width: width, height: full.height)
        }
        let height = full.width / screenAspect
        return CGRect(x: 0, y: (full.height - height) / 2, width: full.width, height: height)
    }

    private func screenPoint(for tabletPoint: (x: Double, y: Double), model: TabletModel) -> CGPoint {
        let bounds = mappedBounds()
        let region = activeRegion(model: model, screen: bounds)
        let fx = min(max((tabletPoint.x - region.minX) / region.width, 0), 1)
        let fy = min(max((tabletPoint.y - region.minY) / region.height, 0), 1)
        return CGPoint(x: bounds.minX + fx * (bounds.width - 1), y: bounds.minY + fy * (bounds.height - 1))
    }

    private func updateClickCount(at tabletPoint: (x: Double, y: Double), time: TimeInterval) {
        let near = hypot(tabletPoint.x - lastClickTabletPoint.x,
                         tabletPoint.y - lastClickTabletPoint.y) < doubleClickDistance
        clickCount = (time - lastClickTime < NSEvent.doubleClickInterval && near) ? clickCount + 1 : 1
        lastClickTime = time
        lastClickTabletPoint = tabletPoint
    }

    private func postProximity(entering: Bool, eraser: Bool, model: TabletModel) {
        guard let event = CGEvent(source: source) else { return }
        event.type = .tabletProximity
        event.setIntegerValueField(.tabletProximityEventVendorID, value: Int64(Tablet.vendorID))
        event.setIntegerValueField(.tabletProximityEventTabletID, value: Int64(model.productID))
        event.setIntegerValueField(.tabletProximityEventDeviceID, value: deviceID)
        event.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 1)
        event.setIntegerValueField(.tabletProximityEventPointerID, value: 0)
        // NSPointingDeviceType: 1 pen, 3 eraser
        event.setIntegerValueField(.tabletProximityEventPointerType, value: eraser ? 3 : 1)
        // capability mask: absolute x/y, buttons, pressure
        event.setIntegerValueField(.tabletProximityEventCapabilityMask, value: 0x0001 | 0x0002 | 0x0040 | 0x0400)
        event.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        event.post(tap: .cghidEventTap)
    }

    /// Button state fields reflect the state after this event (tipDown etc. are updated first).
    private func postMouse(_ type: CGEventType, button: CGMouseButton, at point: CGPoint,
                           pressure: Double, sample: PenSample) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventSubtype, value: 1) // NSEventSubtypeTabletPoint
        event.setDoubleValueField(.mouseEventPressure, value: pressure)
        event.setIntegerValueField(.mouseEventClickState, value: type == .mouseMoved ? 0 : clickCount)
        event.setIntegerValueField(.tabletEventPointX, value: Int64(sample.x))
        event.setIntegerValueField(.tabletEventPointY, value: Int64(sample.y))
        event.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        event.setIntegerValueField(.tabletEventDeviceID, value: deviceID)
        var buttons: Int64 = 0
        if tipDown { buttons |= 1 }
        if lowerDown { buttons |= 2 }
        if upperDown { buttons |= 4 }
        event.setIntegerValueField(.tabletEventPointButtons, value: buttons)
        event.post(tap: .cghidEventTap)
    }
}
