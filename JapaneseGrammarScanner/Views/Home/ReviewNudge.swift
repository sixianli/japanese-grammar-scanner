import SwiftUI

enum ReviewNudge {
    static let rollDuration: Double = 0.8
    static let glowHold: Double = 0.7
    static let glowDuration: Double = 2.0

    struct Plan: Equatable {
        var haptic: Bool
        var motion: Bool
    }

    static func plan(reduceMotion: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> Plan {
        Plan(haptic: true, motion: DecorativeMotion.enabled(reduceMotion: reduceMotion, arguments: arguments))
    }

    static func shownCount(target: Int, elapsed: Double) -> Int {
        guard elapsed >= 0 else { return 0 }
        guard elapsed < rollDuration else { return target }
        let p = elapsed / rollDuration
        let eased = 1 - pow(1 - p, 3)
        return Int((Double(target) * eased).rounded())
    }

    static func glowOpacity(elapsed: Double) -> Double {
        guard elapsed >= 0, elapsed < glowDuration else { return 0 }
        guard elapsed > glowHold else { return 1 }
        return 1 - (elapsed - glowHold) / (glowDuration - glowHold)
    }
}

final class ReviewNudgeSchedule {
    static let shared = ReviewNudgeSchedule()
    static let awayThreshold: TimeInterval = 30 * 60

    private var pending = true
    private var backgroundedAt: Date?

    func sceneChanged(to phase: ScenePhase, now: Date = Date()) {
        switch phase {
        case .background:
            if backgroundedAt == nil { backgroundedAt = now }
        case .active:
            if let left = backgroundedAt, now.timeIntervalSince(left) >= Self.awayThreshold { pending = true }
            backgroundedAt = nil
        default:
            break
        }
    }

    func takeTurn() -> Bool {
        defer { pending = false }
        return pending
    }
}
