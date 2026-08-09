//
//  CBUSManagerSerialDiscovery.swift
//  ModelRailway
//
//  Created by Phil Diggens on 09/08/2026.
//

import Foundation
#if os(macOS)
import IOKit
import IOKit.serial
import IOKit.usb
#endif

// MARK: Serial port discovery
extension CBUSManager {
    private static let cbusVendorID = 0x04D8       // Microchip Technology
    private static let cbusProductID = 0xF80C      // CANUSB4
    
    // Find the USB serial device matching the CBUS interface's vendor and product IDs,
    // returning its device path (/dev/cu.* on macOS, /dev/tty* on Linux) or nil
    func findCBUSSerialPortName() -> String? {
        #if os(macOS)
        // Search the IO registry for a serial BSD service whose parent USB device matches
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return nil }
        
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            // The vendor and product IDs live on the parent USB device,
            // so search upwards through the registry from the serial service
            let searchOptions = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            guard
                let vendorID = IORegistryEntrySearchCFProperty(service, kIOServicePlane, kUSBVendorID as CFString, kCFAllocatorDefault, searchOptions) as? Int,
                let productID = IORegistryEntrySearchCFProperty(service, kIOServicePlane, kUSBProductID as CFString, kCFAllocatorDefault, searchOptions) as? Int,
                vendorID == Self.cbusVendorID,
                productID == Self.cbusProductID
            else { continue }
            
            if let portName = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                return portName
            }
        }
        
        return nil
        
        #elseif os(Linux)
        // Check each tty device in sysfs for a parent USB device that matches
        let ttyClassPath = "/sys/class/tty"
        guard let ttyNames = try? FileManager.default.contentsOfDirectory(atPath: ttyClassPath) else { return nil }
        
        func hexFileValue(_ url: URL) -> Int? {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Int(contents.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16)
        }
        
        for ttyName in ttyNames {
            // Resolve the tty's device symlink, then walk up the sysfs tree to the
            // USB device directory, which holds the idVendor and idProduct files
            var devicePath = URL(fileURLWithPath: "\(ttyClassPath)/\(ttyName)/device").resolvingSymlinksInPath()
            
            while devicePath.path.count > 1 {       // Stop at the filesystem root
                if let vendorID = hexFileValue(devicePath.appendingPathComponent("idVendor")) {
                    if vendorID == Self.cbusVendorID,
                       hexFileValue(devicePath.appendingPathComponent("idProduct")) == Self.cbusProductID {
                        return "/dev/\(ttyName)"
                    }
                    break       // Reached a USB device directory but the IDs don't match
                }
                devicePath.deleteLastPathComponent()
            }
        }
        
        return nil
        
        #else
        return nil
        #endif
    }
}
