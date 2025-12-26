import Foundation

struct StringSimilarity {
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
    
    /// Calculates similarity score (0.0 to 1.0) based on Levenshtein distance
    /// Returns 1.0 for identical strings and 0.0 for completely different strings
    static func similarity(_ s1: String, _ s2: String) -> Double {
        if s1.isEmpty && s2.isEmpty { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }
        
        let distance = levenshteinDistance(s1, s2)
        let maxLen = max(s1.count, s2.count)
        return 1.0 - (Double(distance) / Double(maxLen))
    }
}
