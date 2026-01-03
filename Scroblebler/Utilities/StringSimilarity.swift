import Foundation

struct StringSimilarity {
    /// Calculates Jaccard similarity between two strings based on character sets
    /// Returns |A ∩ B| / |A ∪ B| - intersection over union
    static func jaccardSimilarity(_ s1: String, _ s2: String) -> Double {
        if s1.isEmpty && s2.isEmpty { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }
        
        let set1 = Set(s1)
        let set2 = Set(s2)
        
        let intersection = set1.intersection(set2).count
        let union = set1.union(set2).count
        
        guard union > 0 else { return 0.0 }
        
        // Weight character similarity with length similarity
        let charSimilarity = Double(intersection) / Double(union)
        let lengthSimilarity = 1.0 - abs(Double(s1.count - s2.count)) / Double(max(s1.count, s2.count))
        
        return charSimilarity * 0.7 + lengthSimilarity * 0.3
    }
    
    /// Calculates the Levenshtein distance between two strings
    /// Returns the minimum number of single-character edits (insertions, deletions, or substitutions) required to change one string into the other
    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Len = s1Array.count
        let s2Len = s2Array.count
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Len + 1), count: s1Len + 1)
        
        for i in 0...s1Len {
            matrix[i][0] = i
        }
        
        for j in 0...s2Len {
            matrix[0][j] = j
        }
        
        for i in 1...s1Len {
            for j in 1...s2Len {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[s1Len][s2Len]
    }
    
    /// Calculates similarity score (0.0 to 1.0) using Jaccard similarity
    /// Returns 1.0 for identical strings and 0.0 for completely different strings
    static func similarity(_ s1: String, _ s2: String) -> Double {
        return jaccardSimilarity(s1, s2)
    }
}
