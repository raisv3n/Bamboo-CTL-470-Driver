// Tablet — owns the CTL-470 over IOHIDManager: switches it to Wacom mode and decodes pen reports.
//
// Protocol (docs/findings/02, 03):
//   mode switch: SET_REPORT feature 0x02 = {02 02} (Wacom), {02 01} (HID mouse)
//   pen report 0x02, 10 bytes:
//     [1] 0x80 in range, 0x40 proximity (x/y valid), 0x20 ready (pressure/buttons valid),
//         0x08 eraser, 0x04 upper side switch, 0x02 lower side switch, 0x01 tip
//     [2..3] x LE, [4..5] y LE, [6..7] pressure LE (10-bit), [8] distance

import Foundation
import IOKit.hid

struct PenSample {
    var inRange = false
    var inProximity = false
    /// Close enough for pressure/buttons; coordinates from far hover (prox without ready) are coarse.
    var ready = false
    var eraser = false
    var tip = false
    var lowerButton = false
    var upperButton = false
    var x = 0
    var y = 0
    var pressure = 0
    var distance = 0
}

struct TabletModel {
    let name: String
    let productID: Int
    let maxX: Int
    let maxY: Int
    let maxPressure: Int
}

let supportedModels: [TabletModel] = [
    TabletModel(name: "CTL-470", productID: 0x00DD, maxX: 14720, maxY: 9200, maxPressure: 1023),
]

final class Tablet {
    static let vendorID = 0x056A
    private static let penReportID: UInt8 = 0x02
    private static let modeFeatureID: UInt8 = 0x02
    private static let wacomMode: UInt8 = 0x02
    private static let hidMode: UInt8 = 0x01

    var onSample: ((PenSample, TabletModel) -> Void)?
    var onConnectionChange: ((TabletModel?) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var penInterface: IOHIDDevice?
    private var model: TabletModel?
    private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    func start() {
        let matches = supportedModels.map {
            [kIOHIDVendorIDKey: Tablet.vendorID, kIOHIDProductIDKey: $0.productID,
             kIOHIDPrimaryUsagePageKey: 0x01] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<Tablet>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<Tablet>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Re-sends the mode switch; the tablet falls back to mouse mode after USB reset or sleep.
    func reassertWacomMode() {
        guard let device = penInterface else { return }
        setMode(device, Tablet.wacomMode)
    }

    /// Leaves the tablet usable as a plain mouse once the driver is gone.
    func stop() {
        if let device = penInterface { setMode(device, Tablet.hidMode) }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ device: IOHIDDevice) {
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int
        guard let model = supportedModels.first(where: { $0.productID == productID }) else { return }
        penInterface = device
        self.model = model
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, 64, { context, _, _, _, reportID, report, length in
            Unmanaged<Tablet>.fromOpaque(context!).takeUnretainedValue().handle(reportID, report, length)
        }, context)
        setMode(device, Tablet.wacomMode)
        onConnectionChange?(model)
    }

    private func detach(_ device: IOHIDDevice) {
        guard device == penInterface else { return }
        penInterface = nil
        model = nil
        onConnectionChange?(nil)
    }

    private func setMode(_ device: IOHIDDevice, _ mode: UInt8) {
        // The original driver retries up to 6 times (CUSBCommInterface::SetToWacomMode).
        let report: [UInt8] = [Tablet.modeFeatureID, mode]
        for _ in 0..<6 {
            if IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(Tablet.modeFeatureID),
                                    report, report.count) == kIOReturnSuccess { return }
            usleep(50_000)
        }
        NSLog("BambooDriver: failed to set tablet mode %d", mode)
    }

    private func handle(_ reportID: UInt32, _ data: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        guard reportID == Tablet.penReportID, let model,
              let sample = PenSample.decode(Array(UnsafeBufferPointer(start: data, count: length)), model: model)
        else { return }
        onSample?(sample, model)
    }
}

extension PenSample {
    /// Decodes pen report 0x02; mirrors shared/reference/bamboo_reference.py `decode`.
    static func decode(_ data: [UInt8], model: TabletModel) -> PenSample? {
        guard data.count >= 9, data[0] == 0x02 else { return nil }
        let flags = data[1]
        var sample = PenSample()
        sample.inRange = flags & 0x80 != 0
        sample.inProximity = flags & 0x40 != 0
        if sample.inProximity {
            sample.x = Int(data[2]) | Int(data[3]) << 8
            sample.y = Int(data[4]) | Int(data[5]) << 8
            sample.eraser = flags & 0x08 != 0
        }
        sample.ready = flags & 0x20 != 0
        if sample.ready {
            sample.pressure = min(Int(data[6]) | Int(data[7] & 0x03) << 8, model.maxPressure)
            sample.tip = flags & 0x01 != 0
            sample.lowerButton = flags & 0x02 != 0
            sample.upperButton = flags & 0x04 != 0
        }
        sample.distance = Int(data[8])
        return sample
    }
}
