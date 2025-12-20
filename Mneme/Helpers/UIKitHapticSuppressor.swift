import Foundation
#if os(iOS)
import UIKit

struct UIKitHapticSuppressor {
    static func disableKeyboardHaptics() {
        // Disable UIKit keyboard haptic feedback in simulator
        // This prevents UIKit's internal haptic feedback errors
        #if targetEnvironment(simulator)
        // Use UserDefaults setting to disable UIKit's internal haptic feedback
        // (to prevent these errors)
        UserDefaults.standard.set(false, forKey: "UIKeyboardHapticFeedbackEnabled")
        
        // Also, we can use environment variable to completely disable UIKit's haptic feedback
        // (if UIKit supports this)
        setenv("UIKeyboardHapticFeedbackEnabled", "0", 1)
        #endif
    }
}
#endif

