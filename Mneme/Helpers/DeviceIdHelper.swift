import Foundation

enum DeviceIdHelper {
    static func getOrCreateDeviceId() -> UUID {
        let key = "mneme_device_id"
        if let uuidString = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: uuidString) {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: key)
        return uuid
    }
}
