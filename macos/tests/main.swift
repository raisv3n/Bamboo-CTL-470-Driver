// Checks PenSample.decode against shared/testdata/*.decode.expected.jsonl.
// Run: macos/tests/run.sh

import Foundation

func json(_ s: PenSample) -> String {
    // Same key order and spacing as Python's json.dumps(sort_keys=True).
    "{\"distance\": \(s.distance), \"eraser\": \(s.eraser), \"in_range\": \(s.inRange), "
        + "\"lower_button\": \(s.lowerButton), \"pressure\": \(s.pressure), \"proximity\": \(s.inProximity), "
        + "\"ready\": \(s.ready), \"tip\": \(s.tip), \"upper_button\": \(s.upperButton), \"x\": \(s.x), \"y\": \(s.y)}"
}

let testdata = URL(fileURLWithPath: CommandLine.arguments[1])
let captures = try FileManager.default.contentsOfDirectory(at: testdata, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "hex" }
    .sorted { $0.path < $1.path }
var failures = 0
for capture in captures {
    let reports = try String(contentsOf: capture, encoding: .utf8).split(separator: "\n").map {
        $0.split(separator: " ").map { UInt8($0, radix: 16)! }
    }
    let actual = reports.compactMap { PenSample.decode($0, model: supportedModels[0]) }.map(json)
    let golden = capture.deletingPathExtension().appendingPathExtension("decode.expected.jsonl")
    let expected = try String(contentsOf: golden, encoding: .utf8).split(separator: "\n").map(String.init)
    if actual == expected {
        print("ok   \(capture.lastPathComponent) (\(actual.count) samples)")
    } else {
        failures += 1
        let i = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(actual.count, expected.count)
        print("FAIL \(capture.lastPathComponent) at sample \(i)")
    }
}
exit(failures == 0 ? 0 : 1)
