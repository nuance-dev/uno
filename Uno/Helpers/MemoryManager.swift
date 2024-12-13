import Foundation
import os.log

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "MemoryManager")

class MemoryManager {
    static let shared = MemoryManager()
    
    private let memoryWarningThreshold: Double = 0.8 // 80% memory usage
    private(set) var isMemoryIntensiveTaskRunning = false
    
    var recommendedChunkSize: Int {
        let memoryUsage = currentMemoryUsage()
        return memoryUsage > memoryWarningThreshold ? 5 : 10
    }
    
    func beginMemoryIntensiveTask() {
        isMemoryIntensiveTaskRunning = true
        cleanupMemory()
    }
    
    func endMemoryIntensiveTask() {
        isMemoryIntensiveTaskRunning = false
        cleanupMemory()
    }
    
    func cleanupIfNeeded() {
        if currentMemoryUsage() > memoryWarningThreshold {
            cleanupMemory()
        }
    }
    
    private func cleanupMemory() {
        autoreleasepool {
            // Suggest memory cleanup to the system
            #if DEBUG
            logger.debug("Requesting memory cleanup")
            #endif
            Bundle.main.unload()
            URLCache.shared.removeAllCachedResponses()
        }
    }
    
    func currentMemoryUsage() -> Double {
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
            return Double(info.resident_size) / Double(ProcessInfo.processInfo.physicalMemory)
        }
        
        return 0.0
    }
} 