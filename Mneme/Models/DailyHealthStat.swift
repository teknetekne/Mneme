import Foundation
import CoreData

@objc(DailyHealthStat)
public class DailyHealthStat: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DailyHealthStat> {
        return NSFetchRequest<DailyHealthStat>(entityName: "DailyHealthStat")
    }

    @NSManaged public var activeEnergyBurned: Double
    @NSManaged public var createdAt: Date?
    @NSManaged public var date: Date?
    @NSManaged public var distanceWalkingRunning: Double
    @NSManaged public var id: UUID?
    @NSManaged public var modifiedAt: Date?
    @NSManaged public var stepCount: Double
}

extension DailyHealthStat: Identifiable {}
