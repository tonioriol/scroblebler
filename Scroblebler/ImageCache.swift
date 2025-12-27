import Foundation
import AppKit

@MainActor
class ImageCache: ObservableObject {
    static let shared = ImageCache()
    
    private var cache: [String: Data] = [:]
    private let maxCacheSize = 100
    private var accessOrder: [String] = []
    
    private init() {}
    
    func get(_ url: String) -> Data? {
        guard let data = cache[url] else { return nil }
        
        // Update access order (LRU)
        if let index = accessOrder.firstIndex(of: url) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(url)
        
        return data
    }
    
    func set(_ url: String, data: Data) {
        // Evict oldest if cache is full
        if cache.count >= maxCacheSize, let oldestUrl = accessOrder.first {
            cache.removeValue(forKey: oldestUrl)
            accessOrder.removeFirst()
        }
        
        cache[url] = data
        accessOrder.append(url)
    }
    
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}
