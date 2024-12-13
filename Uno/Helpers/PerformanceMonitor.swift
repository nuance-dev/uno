import Foundation
import os.signpost
import os.log

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    private let logger = Logger(subsystem: "me.nuanc.Uno", category: "Performance")
    private let signposter = OSSignposter()
    
    func beginTask(_ name: StaticString) -> OSSignpostIntervalState {
        let signpostID = signposter.makeSignpostID()
        return signposter.beginInterval(name, id: signpostID)
    }
    
    func endTask(_ name: StaticString, state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
    
    func logMemoryUsage() {
        let memoryUsage = MemoryManager.shared.currentMemoryUsage()
        logger.debug("Memory usage: \(memoryUsage * 100, privacy: .public)%")
    }
    
    func trackOperation<T>(_ name: StaticString, operation: () -> T) -> T {
        let state = beginTask(name)
        defer { 
            endTask(name, state: state)
            logMemoryUsage()
        }
        return operation()
    }
} 