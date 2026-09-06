import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Centralized haptic feedback for critical safety events and user actions.
enum HapticManager {
    enum Feedback {
        case light
        case medium
        case heavy
        case success
        case warning
        case error
        case selection
    }

    static func trigger(_ feedback: Feedback) {
        #if os(iOS)
        switch feedback {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }

    /// Strong feedback for critical / high risk transitions.
    static func criticalAlert() {
        #if os(iOS)
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.prepare()
        heavy.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        }
        #endif
    }

    static func riskLevelChanged(to level: RiskLevel) {
        switch level {
        case .critical:
            criticalAlert()
        case .high:
            trigger(.warning)
        case .moderate:
            trigger(.medium)
        case .safe:
            trigger(.success)
        }
    }
}
