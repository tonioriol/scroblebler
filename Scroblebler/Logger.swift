import Foundation
import os.log

enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.tonioriol.scroblebler"
    
    // Category loggers
    static let scrobbling = OSLog(subsystem: subsystem, category: "Scrobbling")
    static let network = OSLog(subsystem: subsystem, category: "Network")
    static let merge = OSLog(subsystem: subsystem, category: "Merge")
    static let cache = OSLog(subsystem: subsystem, category: "Cache")
    static let ui = OSLog(subsystem: subsystem, category: "UI")
    
    // Convenience methods
    static func debug(_ message: String, log: OSLog = .default) {
        os_log("%{public}@", log: log, type: .debug, message)
    }
    
    static func info(_ message: String, log: OSLog = .default) {
        os_log("%{public}@", log: log, type: .info, message)
    }
    
    static func error(_ message: String, log: OSLog = .default) {
        os_log("%{public}@", log: log, type: .error, message)
    }
    
    static func fault(_ message: String, log: OSLog = .default) {
        os_log("%{public}@", log: log, type: .fault, message)
    }
}
