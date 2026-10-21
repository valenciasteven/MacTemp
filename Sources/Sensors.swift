import Foundation
import IOKit

// Reads the CPU/SoC temperature without sudo.
// Apple Silicon: private IOHIDEventSystemClient API (loaded at runtime with dlsym).
// Intel: the SMC keys TC0P / TC0D.
enum Sensors {
    static func cpuTemperature() -> Double? {
        #if arch(arm64)
        return AppleSiliconHID.cpuTemperature()
        #else
        return IntelSMC.cpuTemperature()
        #endif
    }
}

// MARK: - Apple Silicon

enum AppleSiliconHID {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private static let kIOHIDEventTypeTemperature: Int64 = 15

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private static let create = sym("IOHIDEventSystemClientCreate", CreateFn.self)
    private static let setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatchingFn.self)
    private static let copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServicesFn.self)
    private static let copyProperty = sym("IOHIDServiceClientCopyProperty", CopyPropertyFn.self)
    private static let copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEventFn.self)
    private static let getFloat = sym("IOHIDEventGetFloatValue", GetFloatFn.self)

    // One client, created once and reused every refresh.
    private static let client: AnyObject? = {
        guard let create, let setMatching,
              let c = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(c, matching)
        return c
    }()

    /// All temperature sensors as (name, °C).
    static func allSensors() -> [(String, Double)] {
        guard let client, let copyServices, let copyProperty, let copyEvent, let getFloat,
              let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else { return [] }
        var result: [(String, Double)] = []
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = copyEvent(service, kIOHIDEventTypeTemperature, 0, 0)?.takeRetainedValue() else { continue }
            let value = getFloat(event, Int32(kIOHIDEventTypeTemperature << 16))
            if value > 0 && value < 150 { result.append((name, value)) }
        }
        return result
    }

    static func cpuTemperature() -> Double? {
        let sensors = allSensors()
        // CPU/SoC die sensors; names differ between chip generations.
        let dieSensors = sensors.filter { name, _ in
            name.hasPrefix("PMU tdie") || name.hasPrefix("PMU2 tdie") ||
            name.contains("ACC MTR Temp") || name.contains("SOC MTR Temp")
        }
        let chosen = dieSensors.isEmpty ? sensors.filter { $0.0.hasPrefix("PMU") } : dieSensors
        guard !chosen.isEmpty else { return nil }
        return chosen.map(\.1).reduce(0, +) / Double(chosen.count)
    }
}

// MARK: - Intel

enum IntelSMC {
    private struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    private struct KeyData {
        var key: UInt32 = 0
        var vers = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt16(0))
        var pLimitData = (UInt16(0), UInt16(0), UInt32(0), UInt32(0), UInt32(0))
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private static let connection: io_connect_t? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        return IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess ? conn : nil
    }()

    private static func call(_ input: inout KeyData) -> KeyData? {
        guard let connection else { return nil }
        var output = KeyData()
        var outSize = MemoryLayout<KeyData>.stride
        let r = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<KeyData>.stride, &output, &outSize)
        return r == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private static func read(_ key: String) -> Double? {
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        var input = KeyData(); input.key = code; input.data8 = 9          // read key info
        guard let info = call(&input) else { return nil }
        input.keyInfo.dataSize = info.keyInfo.dataSize; input.data8 = 5    // read bytes
        guard let out = call(&input) else { return nil }
        let value = Double(Int16(bitPattern: UInt16(out.bytes.0) << 8 | UInt16(out.bytes.1))) / 256  // sp78
        return value > 0 && value < 150 ? value : nil
    }

    static func cpuTemperature() -> Double? { read("TC0P") ?? read("TC0D") }
}
