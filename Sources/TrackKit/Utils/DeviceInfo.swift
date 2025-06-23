import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WatchKit)
import WatchKit
#endif

/// Utility class for collecting device information
public struct DeviceInfo {
    
    /// Current device information as a dictionary
    public static var current: [String: Any] {
        var info: [String: Any] = [:]
        
        #if os(iOS) || os(tvOS)
        let device = UIDevice.current
        info["model"] = deviceModel
        info["name"] = device.name
        info["system_name"] = device.systemName
        info["system_version"] = device.systemVersion
        info["identifier_for_vendor"] = device.identifierForVendor?.uuidString
        info["user_interface_idiom"] = userInterfaceIdiom
        
        if #available(iOS 11.0, tvOS 11.0, *) {
            info["battery_level"] = device.batteryLevel
            info["battery_state"] = batteryState
        }
        
        // Screen information
        let screen = UIScreen.main
        info["screen_bounds"] = NSStringFromCGRect(screen.bounds)
        info["screen_scale"] = screen.scale
        
        #elseif os(watchOS)
        let device = WKInterfaceDevice.current()
        info["model"] = deviceModel
        info["name"] = device.name
        info["system_name"] = device.systemName
        info["system_version"] = device.systemVersion
        
        let screen = WKInterfaceDevice.current().screenBounds
        info["screen_bounds"] = NSStringFromCGRect(screen)
        info["screen_scale"] = WKInterfaceDevice.current().screenScale
        
        #elseif os(macOS)
        info["model"] = deviceModel
        info["system_name"] = "macOS"
        info["system_version"] = ProcessInfo.processInfo.operatingSystemVersionString
        
        if let screen = NSScreen.main {
            info["screen_bounds"] = NSStringFromRect(screen.frame)
            info["screen_scale"] = screen.backingScaleFactor
        }
        #endif
        
        // Common information
        info["locale"] = Locale.current.identifier
        info["timezone"] = TimeZone.current.identifier
        info["cpu_count"] = ProcessInfo.processInfo.processorCount
        info["memory"] = ProcessInfo.processInfo.physicalMemory
        
        return info
    }
    
    /// Device model identifier
    public static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value))!)
        }
        return identifier
    }
    
    #if os(iOS) || os(tvOS)
    /// User interface idiom string
    private static var userInterfaceIdiom: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return "phone"
        case .pad:
            return "pad"
        case .tv:
            return "tv"
        case .carPlay:
            return "carPlay"
        case .mac:
            return "mac"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }
    
    /// Battery state string
    private static var batteryState: String {
        switch UIDevice.current.batteryState {
        case .unknown:
            return "unknown"
        case .unplugged:
            return "unplugged"
        case .charging:
            return "charging"
        case .full:
            return "full"
        @unknown default:
            return "unknown"
        }
    }
    #endif
    
    /// Network connectivity type
    public static var networkType: String {
        // This would require network reachability framework
        // For simplicity, returning "unknown" here
        // In production, you might want to use a reachability library
        return "unknown"
    }
    
    /// Check if device is jailbroken/rooted (basic check)
    public static var isJailbroken: Bool {
        #if os(iOS)
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/private/var/lib/cydia",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist",
            "/usr/libexec/cydia/firmware.sh"
        ]
        
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check if we can write to system directories
        let testPath = "/private/test.txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
    
    /// Available disk space in bytes
    public static var availableDiskSpace: Int64 {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    /// Total disk space in bytes
    public static var totalDiskSpace: Int64 {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return attributes[.systemSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    /// Current memory usage in bytes
    public static var memoryUsage: Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }
} 