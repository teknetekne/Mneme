import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif

struct HapticHelper {
    #if os(iOS)
    private static var hapticEngine: CHHapticEngine?
    
    static func checkHapticSupport() -> Bool {
        if #available(iOS 13.0, *) {
            let hapticCapability = CHHapticEngine.capabilitiesForHardware()
            return hapticCapability.supportsHaptics
        }
        return false
    }
    
    static func prepareHapticEngine() {
        guard checkHapticSupport() else { return }
        
        guard hapticEngine == nil else { return }
        
        do {
            let engine = try CHHapticEngine()
            
            engine.stoppedHandler = { _ in
            }
            
            engine.resetHandler = {
                try? engine.start()
            }
            
            try engine.start()
            hapticEngine = engine
        } catch {
        }
    }
    
    static func playSelectionFeedback() {
        guard checkHapticSupport() else { return }
        
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    static func playImpactFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard checkHapticSupport() else { return }
        
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    static func playNotificationFeedback(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard checkHapticSupport() else { return }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
    #else
    static func checkHapticSupport() -> Bool {
        return false
    }
    
    static func prepareHapticEngine() {}
    static func playSelectionFeedback() {}
    static func playImpactFeedback(style: Int = 0) {}
    static func playNotificationFeedback(type: Int = 0) {}
    #endif
}

