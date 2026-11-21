import XCTest
import SwiftUI
@testable import JapaneseGrammarScanner

/// 复习自评条：三个按钮固定红黄绿三色（不随主题），手感不同的震动。
final class ReviewBarTests: XCTestCase {
    /// Build 16 反馈：「记得」用的是主题色，樱花主题下变成了粉色。三色固定，与任何主题色都无关。
    func testGradeColorsAreFixedAndDistinct() {
        let hex = ReviewBar.colorHex
        XCTAssertEqual(Set(FSRS.Grade.allCases), Set(hex.keys), "每个按钮都要有固定颜色")
        XCTAssertEqual(hex[.again]?.light, 0xB4553F, "忘了：柔和珊瑚红")
        XCTAssertEqual(hex[.hard]?.light, 0x8F6514, "有点模糊：琥珀黄")
        XCTAssertEqual(hex[.good]?.light, 0x4F7236, "记得：抹茶绿")
        XCTAssertEqual(Set(hex.values.map(\.light)).count, 3)
        XCTAssertEqual(Set(hex.values.map(\.dark)).count, 3)

        // 换主题前后颜色不变
        let store = AppearanceStore.shared
        let saved = store.accent
        defer { store.accent = saved }
        let before = FSRS.Grade.allCases.map { UIColor(ReviewBar.color($0)).resolvedColor(with: .init(userInterfaceStyle: .light)) }
        for accent in AppearanceStore.AccentOption.allCases {
            store.accent = accent
            let now = FSRS.Grade.allCases.map { UIColor(ReviewBar.color($0)).resolvedColor(with: .init(userInterfaceStyle: .light)) }
            XCTAssertEqual(now, before, "主题 \(accent) 下评分按钮颜色不应改变")
        }
    }

    /// 浅色 / 深色模式下文字对比度都要够（按钮底是同色 14% 透明度，叠在卡片上；这里按 4.5:1 检查文字对卡片底色）
    func testGradeColorsHaveEnoughContrast() {
        func luminance(_ hex: UInt32) -> Double {
            func ch(_ v: UInt32) -> Double {
                let c = Double(v) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * ch(hex >> 16 & 0xFF) + 0.7152 * ch(hex >> 8 & 0xFF) + 0.0722 * ch(hex & 0xFF)
        }
        func ratio(_ a: UInt32, _ b: UInt32) -> Double {
            let (x, y) = (luminance(a), luminance(b))
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        for (g, c) in ReviewBar.colorHex {
            XCTAssertGreaterThanOrEqual(ratio(c.light, 0xFFFFFF), 4.5, "\(g) 浅色模式对比度不够")
            XCTAssertGreaterThanOrEqual(ratio(c.dark, 0x1D222B), 4.5, "\(g) 深色模式对比度不够")
        }
    }

    /// 点三个按钮有不同的震动
    func testEachGradeHasDistinctHaptic() {
        let haptics = FSRS.Grade.allCases.map(ReviewBar.haptic)
        XCTAssertEqual(haptics.count, 3)
        XCTAssertEqual(ReviewBar.haptic(.good), .success)
        XCTAssertNotEqual(ReviewBar.haptic(.again), ReviewBar.haptic(.hard))
        XCTAssertNotEqual(ReviewBar.haptic(.again), ReviewBar.haptic(.good))
    }
}
