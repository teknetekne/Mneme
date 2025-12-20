import Foundation

/// Handler for journal/mood entries
/// Handles mood emoji + journal text without complex parsing
final class JournalHandler: IntentHandler {
    
    func handle(
        result: ParsedResult,
        text: String,
        lineId: UUID
    ) async -> [ParsingResultItem] {
        var items: [ParsingResultItem] = []
        
        // 1. Add Intent
        items.append(ParsingResultItem(
            field: "Intent",
            value: NotepadFormatter.formatIntentForDisplay("journal"),
            isValid: true,
            errorMessage: nil,
            confidence: 1.0
        ))
        
        // 2. Extract mood emoji (first character if it's an emoji)
        let moodEmojis = ["😢", "😕", "😐", "🙂", "😊"]
        var moodEmoji: String? = nil
        var journalText = text
        
        for emoji in moodEmojis {
            if text.hasPrefix(emoji) {
                moodEmoji = emoji
                journalText = String(text.dropFirst(emoji.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        // 3. Add mood if present
        if let emoji = moodEmoji {
            items.append(ParsingResultItem(
                field: "Mood",
                value: emoji,
                isValid: true,
                errorMessage: nil,
                rawValue: emoji,
                confidence: 1.0
            ))
        }
        
        // 4. Add journal entry text
        if !journalText.isEmpty {
            items.append(ParsingResultItem(
                field: "Subject",
                value: journalText,
                isValid: true,
                errorMessage: nil,
                rawValue: journalText,
                confidence: 1.0
            ))
        } else if let obj = result.object?.value, !obj.isEmpty {
            // Fallback to parsed object if no text after emoji
            items.append(ParsingResultItem(
                field: "Subject",
                value: obj.replacingOccurrences(of: "_", with: " ").capitalized,
                isValid: true,
                errorMessage: nil,
                rawValue: obj,
                confidence: result.object?.confidence
            ))
        }
        
        return items
    }
}
