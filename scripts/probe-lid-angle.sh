#!/bin/bash
# Read-only probe using the same HID source as the app.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/insomnia-lid-probe.XXXXXX")
trap 'rm -rf -- "$probe_dir"' EXIT

cat > "$probe_dir/main.swift" <<'SWIFT'
import Foundation

let duration = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 10
guard CommandLine.arguments.count <= 2,
      CommandLine.arguments.count == 1 || Double(CommandLine.arguments[1]) != nil,
      (1...3600).contains(duration) else {
    fputs("Usage: scripts/probe-lid-angle.sh [seconds, 1–3600]\n", stderr)
    exit(2)
}
let source: any LidAngleReading = HIDLidAngleSource()
let clock = ProcessInfo.processInfo
let start = clock.systemUptime
var reads = 0
var changes = 0
var errors = 0
var lastAngle: Double?
var lastError: LidReadError?
while clock.systemUptime - start < duration {
    let result = await source.read()
    let elapsed = clock.systemUptime - start
    let prefix = String(format: "%8.3fs", elapsed)
    switch result {
    case let .success(angle):
        reads += 1
        if lastAngle != angle {
            if lastAngle != nil { changes += 1 }
            print("\(prefix)  \(Int(angle))°")
        }
        lastAngle = angle
        lastError = nil
        try await Task.sleep(for: .milliseconds(25))
    case let .failure(error):
        errors += 1
        if lastError != error { print("\(prefix)  \(error)") }
        lastAngle = nil
        lastError = error
        try await Task.sleep(for: .seconds(2))
    }
}
await source.close()
let elapsed = clock.systemUptime - start
print(String(format: "%d reads, %d changes, %d errors in %.2fs (%.1f reads/s, %.1f changes/s)",
             reads, changes, errors, elapsed, Double(reads) / elapsed, Double(changes) / elapsed))
exit(reads == 0 ? 1 : 0)
SWIFT

swiftc -O "$repo/Sources/Insomnia/System/HIDLidAngleSource.swift" "$probe_dir/main.swift" -o "$probe_dir/probe"
"$probe_dir/probe" "$@"
