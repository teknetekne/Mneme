import Foundation
import EventKit
import SwiftUI

struct ReminderItem: Identifiable, Equatable {
    let id: UUID
    let ekReminder: EKReminder?
    var title: String
    var isCompleted: Bool
    let priority: ReminderPriority
    let dueDate: Date?
    
    init(id: UUID = UUID(), ekReminder: EKReminder? = nil, title: String, isCompleted: Bool = false, priority: ReminderPriority = .none, dueDate: Date? = nil) {
        self.id = id
        self.ekReminder = ekReminder
        self.title = title
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueDate = dueDate
    }
    
    static func stableId(from ekReminder: EKReminder) -> UUID {
        let identifier = ekReminder.calendarItemIdentifier
        if let uuid = UUID(uuidString: identifier) {
            return uuid
        }
        var hasher = Hasher()
        hasher.combine(identifier)
        let hash = hasher.finalize()
        let hashValue = UInt64(bitPattern: Int64(hash))
        let hashBytes = withUnsafeBytes(of: hashValue) { Array($0) }
        
        var secondHasher = Hasher()
        secondHasher.combine(identifier)
        secondHasher.combine("mneme")
        let secondHash = secondHasher.finalize()
        let secondHashValue = UInt64(bitPattern: Int64(secondHash))
        let secondHashBytes = withUnsafeBytes(of: secondHashValue) { Array($0) }
        
        return UUID(uuid: uuid_t(hashBytes[0], hashBytes[1], hashBytes[2], hashBytes[3],
                                  hashBytes[4], hashBytes[5], hashBytes[6], hashBytes[7],
                                  0x80, 0x00,
                                  secondHashBytes[0], secondHashBytes[1],
                                  secondHashBytes[2], secondHashBytes[3],
                                  secondHashBytes[4], secondHashBytes[5]))
    }
    
    static func == (lhs: ReminderItem, rhs: ReminderItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isCompleted == rhs.isCompleted &&
        lhs.priority == rhs.priority &&
        lhs.dueDate == rhs.dueDate &&
        lhs.ekReminder?.calendarItemIdentifier == rhs.ekReminder?.calendarItemIdentifier
    }
}

enum ReminderPriority: Comparable {
    case none
    case low
    case medium
    case high
    
    var color: Color {
        switch self {
        case .none: return .clear
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    // Higher priority is greater
    static func < (lhs: ReminderPriority, rhs: ReminderPriority) -> Bool {
        priorityValue(lhs) < priorityValue(rhs)
    }
    
    private static func priorityValue(_ priority: ReminderPriority) -> Int {
        switch priority {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }
}
