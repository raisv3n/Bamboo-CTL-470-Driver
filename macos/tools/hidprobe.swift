// hidprobe — read-only probe for the Wacom CTL-470 (056A:00DD).
// Dumps feature reports (GET only) and, with --listen <seconds>, logs raw input reports.
// Build: swiftc -O hidprobe.swift -o hidprobe

import Foundation
import IOKit.hid

let vendorID = 0x056A
let productID = 0x00DD
let featureIDs: [UInt8] = [0x02, 0x03, 0x04, 0x05, 0x10, 0x11, 0x13, 0x14, 0x20, 0x21, 0x30, 0x31]

func hex(_ bytes: UnsafePointer<UInt8>, _ count: Int) -> String {
    (0..<count).map { String(format: "%02x", bytes[$0]) }.joined(separator: " ")
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID] as CFDictionary)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    print("IOHIDManagerOpen failed: 0x\(String(openResult, radix: 16)) (Input Monitoring permission?)")
    exit(1)
}
guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
    print("CTL-470 not found")
    exit(1)
}

for device in devices {
    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
    print(String(format: "== interface usagePage 0x%04x usage 0x%02x", usagePage, usage))
    guard usagePage == 0x01 else { continue }
    for id in featureIDs {
        var buffer = [UInt8](repeating: 0, count: 64)
        var length = buffer.count
        let r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &buffer, &length)
        if r == kIOReturnSuccess {
            print(String(format: "feature 0x%02x [%d]: ", id, length) + hex(buffer, length))
        } else {
            print(String(format: "feature 0x%02x: error 0x%08x", id, r))
        }
    }
}

// --wacom-mode: SET_REPORT feature 0x02 = {02 02} (CUSBCommInterface::SetToWacomMode);
// restores {02 01} (SetToHIDMode) on exit.
let wacomMode = CommandLine.arguments.contains("--wacom-mode")
let mouseInterface = devices.first {
    IOHIDDeviceGetProperty($0, kIOHIDPrimaryUsagePageKey as CFString) as? Int == 0x01
}
func setMode(_ mode: UInt8) {
    guard let device = mouseInterface else { return }
    let report: [UInt8] = [0x02, mode]
    let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0x02, report, report.count)
    print(String(format: "set feature 0x02 = 02 %02x: 0x%08x", mode, r))
}
if wacomMode { setMode(0x02) }

if let i = CommandLine.arguments.firstIndex(of: "--listen"), i + 1 < CommandLine.arguments.count,
   let seconds = Double(CommandLine.arguments[i + 1]) {
    for device in devices {
        let size = 128
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, size, { _, _, _, _, reportID, report, length in
            print(String(format: "in 0x%02x [%d]: ", reportID, length) + hex(report, length))
        }, nil)
    }
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    print("listening \(seconds)s — move the pen")
    CFRunLoopRunInMode(.defaultMode, seconds, false)
}

if wacomMode { setMode(0x01) }
