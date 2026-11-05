import Foundation
import IOKit.hid

enum LidReadError: Error, Equatable, Sendable {
    case notFound
    case openFailed(Int32)
    case readFailed(Int32)
    case invalidReport
}

protocol LidAngleReading: Sendable {
    func read() async -> Result<Double, LidReadError>
    func close() async
}

/// The HID transport is public. The matching tuple and report layout are
/// Apple device details, verified on Mac16,8. Unknown layouts fail closed.
actor HIDLidAngleSource: LidAngleReading {
    private var device: IOHIDDevice?

    func read() -> Result<Double, LidReadError> {
        if let device {
            let result = Self.readReport(device)
            if case .failure = result { close() }
            return result
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let match = [
            kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x8104,
            kIOHIDDeviceUsagePageKey: 0x20, kIOHIDDeviceUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        var failure = LidReadError.notFound
        for candidate in devices {
            guard (IOHIDDeviceGetProperty(candidate, kIOHIDBuiltInKey as CFString) as? Bool) == true else { continue }
            let opened = IOHIDDeviceOpen(candidate, 0)
            guard opened == kIOReturnSuccess else {
                failure = .openFailed(opened)
                continue
            }
            let result = Self.readReport(candidate)
            switch result {
            case .success:
                device = candidate
                return result
            case let .failure(error):
                failure = error
                IOHIDDeviceClose(candidate, 0)
            }
        }
        return .failure(failure)
    }

    func close() {
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil
    }

    private static func readReport(_ device: IOHIDDevice) -> Result<Double, LidReadError> {
        var bytes = [UInt8](repeating: 0, count: 8)
        var count = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &count)
        guard result == kIOReturnSuccess else { return .failure(.readFailed(result)) }
        return decode(bytes.prefix(count))
    }

    static func decode(_ bytes: ArraySlice<UInt8>) -> Result<Double, LidReadError> {
        guard bytes.count == 3, bytes.first == 1 else { return .failure(.invalidReport) }
        let start = bytes.startIndex
        let degrees = Double(UInt16(bytes[start + 1]) | (UInt16(bytes[start + 2]) << 8))
        guard (0...180).contains(degrees) else { return .failure(.invalidReport) }
        return .success(degrees)
    }
}
