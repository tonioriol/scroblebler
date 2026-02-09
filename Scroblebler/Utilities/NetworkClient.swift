import Foundation

/// Reusable network client with exponential backoff retry logic
enum NetworkClient {
    enum RetryError: Error {
        case maxRetriesExceeded
    }

    /// Execute a network request with exponential backoff retry logic
    /// - Parameters:
    ///   - maxRetries: Maximum number of retry attempts (default: 3)
    ///   - shouldRetry: Optional closure to determine if an error is retryable (default: retry all errors)
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: The last error encountered if all retries fail
    static func executeWithRetry<T>(
        maxRetries: Int = 3,
        shouldRetry: ((Error) -> Bool)? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                // If the task was cancelled, don't retry.
                if Task.isCancelled {
                    throw error
                }

                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    throw error
                }

                // Check if we should retry this error
                if let shouldRetry = shouldRetry, !shouldRetry(error) {
                    throw error
                }

                // If this was the last attempt, throw the error
                if attempt == maxRetries - 1 {
                    throw error
                }

                // Exponential backoff: 2^attempt seconds
                let delay = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)
                Logger.info("Network request failed (attempt \(attempt + 1)/\(maxRetries)), retrying in \(pow(2.0, Double(attempt)))s", log: Logger.network)
                try await Task.sleep(nanoseconds: delay)
            }
        }

        throw RetryError.maxRetriesExceeded
    }
}
