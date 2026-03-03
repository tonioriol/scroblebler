import Foundation
import CryptoKit

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let lock = NSLock()
    private var memory: [String: Data] = [:]
    private var failedURLs = Set<String>()
    private let diskDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        diskDir = appSupport.appendingPathComponent("Scroblebler/ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    func get(_ url: String) -> Data? {
        lock.lock()
        if let data = memory[url] {
            lock.unlock()
            return data
        }
        lock.unlock()

        // Try disk
        let path = diskPath(for: url)
        guard let data = try? Data(contentsOf: path) else { return nil }
        lock.lock()
        memory[url] = data
        lock.unlock()
        return data
    }

    func set(_ url: String, data: Data) {
        lock.lock()
        memory[url] = data
        lock.unlock()
        // Write to disk in background
        let path = diskPath(for: url)
        DispatchQueue.global(qos: .utility).async {
            try? data.write(to: path, options: .atomic)
        }
    }

    func isFailed(_ url: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return failedURLs.contains(url)
    }

    func markFailed(_ url: String) {
        lock.lock()
        defer { lock.unlock() }
        failedURLs.insert(url)
    }

    private func diskPath(for url: String) -> URL {
        let hash = SHA256.hash(data: Data(url.utf8))
        let name = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskDir.appendingPathComponent(name)
    }
}
