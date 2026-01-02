import Foundation

/// Simple and fast string similarity for music metadata matching
enum StringSimilarity {
    /// Calculate similarity between two strings (0.0 to 1.0)
    /// Uses a simple character-based approach optimized for short music metadata strings
    /// Much faster than Levenshtein (O(n) vs O(n²)) and sufficient for this use case
    static func similarity(_ s1: String, _ s2: String) -> Double {
        // Exact match after normalization
        if s1 == s2 {
            return 1.0
        }
        
        // Empty strings
        if s1.isEmpty || s2.isEmpty {
            return 0.0
        }
        
        // Convert to character sets for comparison
        let chars1 = Set(s1)
        let chars2 = Set(s2)
        
        // Calculate Jaccard similarity (intersection over union)
        let intersection = chars1.intersection(chars2).count
        let union = chars1.union(chars2).count
        
        guard union > 0 else { return 0.0 }
        
        let jaccardScore = Double(intersection) / Double(union)
        
        // Bonus for similar lengths (helps with metadata variations)
        let lengthRatio = Double(min(s1.count, s2.count)) / Double(max(s1.count, s2.count))
        
        // Weighted score: 70% Jaccard, 30% length similarity
        return (jaccardScore * 0.7) + (lengthRatio * 0.3)
    }
}
