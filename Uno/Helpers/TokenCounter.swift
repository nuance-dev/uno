import Foundation

class TokenCounter {
    static func estimateTokenCount(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token on average
        return Int(Double(text.count) / 4.0)
    }
    
    static func formatTokenCount(_ count: Int) -> String {
        if count < 1000 {
            return "\(count)"
        } else if count < 1_000_000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
    }
} 