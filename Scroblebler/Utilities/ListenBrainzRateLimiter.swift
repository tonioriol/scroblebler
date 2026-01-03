import Foundation

/// Rate limiter for ListenBrainz API following their recommended headers
actor ListenBrainzRateLimiter {
    private var limit: Int = 100 // Default safe limit
    private var remaining: Int = 100
    private var resetTime: Date = Date()
    private var lastRequestTime: Date = .distantPast
    
    /// Minimum delay between requests (in seconds) to be polite
    private let minimumDelay: TimeInterval = 0.2
    
    /// Wait if needed before making a request
    func waitIfNeeded() async {
        // Check if we're past the reset time
        if Date() >= resetTime {
            Logger.debug("Rate limit reset", log: Logger.network)
            remaining = limit
            resetTime = Date().addingTimeInterval(60) // Reset to 1 minute from now
        }
        
        // If we're close to limit, wait for reset
        if remaining <= 5 {
            let waitTime = max(0, resetTime.timeIntervalSinceNow)
            if waitTime > 0 {
                Logger.info("Rate limit nearly exhausted (\(remaining) remaining), waiting \(Int(waitTime))s for reset", log: Logger.network)
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                remaining = limit
                resetTime = Date().addingTimeInterval(60)
            }
        }
        
        // Enforce minimum delay between requests
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < minimumDelay {
            let delayNeeded = minimumDelay - timeSinceLastRequest
            try? await Task.sleep(nanoseconds: UInt64(delayNeeded * 1_000_000_000))
        }
        
        lastRequestTime = Date()
        remaining = max(0, remaining - 1)
    }
    
    /// Update rate limit info from response headers
    func updateFromHeaders(_ response: HTTPURLResponse) {
        if let limitStr = response.value(forHTTPHeaderField: "X-RateLimit-Limit"),
           let limitValue = Int(limitStr) {
            limit = limitValue
            Logger.debug("Rate limit: \(limit) requests", log: Logger.network)
        }
        
        if let remainingStr = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           let remainingValue = Int(remainingStr) {
            remaining = remainingValue
            Logger.debug("Rate limit remaining: \(remaining) requests", log: Logger.network)
        }
        
        // Prefer X-RateLimit-Reset-In (resilient against clock skew)
        if let resetInStr = response.value(forHTTPHeaderField: "X-RateLimit-Reset-In"),
           let resetInValue = TimeInterval(resetInStr) {
            resetTime = Date().addingTimeInterval(resetInValue)
            Logger.debug("Rate limit resets in: \(Int(resetInValue))s", log: Logger.network)
        } else if let resetStr = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
                  let resetValue = TimeInterval(resetStr) {
            resetTime = Date(timeIntervalSince1970: resetValue)
            let resetIn = resetTime.timeIntervalSinceNow
            Logger.debug("Rate limit resets at: \(resetStr) (\(Int(resetIn))s from now)", log: Logger.network)
        }
    }
    
    /// Handle 429 Too Many Requests response
    func handle429Response(_ response: HTTPURLResponse) async {
        updateFromHeaders(response)
        
        // Calculate backoff time
        let backoffTime = max(resetTime.timeIntervalSinceNow, 5.0) // At least 5 seconds
        Logger.error("Rate limit exceeded (429), backing off for \(Int(backoffTime))s", log: Logger.network)
        
        try? await Task.sleep(nanoseconds: UInt64(backoffTime * 1_000_000_000))
        
        // Reset counters after backoff
        remaining = limit
        resetTime = Date().addingTimeInterval(60)
    }
    
    /// Get current rate limit status for logging
    func getStatus() -> (limit: Int, remaining: Int, resetIn: TimeInterval) {
        return (limit, remaining, resetTime.timeIntervalSinceNow)
    }
}
