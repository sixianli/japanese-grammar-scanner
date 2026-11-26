import UIKit
import XCTest

final class HomeScreenNameProbeTests: XCTestCase {
    let candidates = [
        "日语语法速查", "日语语法", "日语语法扫描", "日语语法拍照", "拍日语语法", "日语语法拍查",
        "日語語法速查", "日語文法速查", "日語文法", "日文文法", "日檢文法", "日文文法掃描",
        "JP Grammar", "Japanese Grammar", "JP Grammar Scan", "Grammar Scan", "JLPT Grammar", "Grammar Lens",
        "일본어 문법", "일본어 문법 스캔", "일어 문법", "일본어문법",
        "Gramática JP", "Gramática japonesa", "Japonés", "Gramática",
        "Ngữ Pháp JP", "Ngữ pháp tiếng Nhật", "Ngữ Pháp Nhật", "Ngữ pháp",
        "ဂျပန်သဒ္ဒါ",
        "JapaneseGrammarScannerUITests-Runner",
    ]

    func testCaptureHomeScreenLabels() {
        let app = XCUIApplication()
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        sleep(3)
        XCUIDevice.shared.press(.home)
        sleep(2)

        let scale = UIScreen.main.scale
        print("PROBE screen=\(UIScreen.main.bounds.size) scale=\(scale)")
        for style in [UIFont.TextStyle.caption1, .caption2, .footnote] {
            let f = UIFont.preferredFont(forTextStyle: style)
            print("PROBE style=\(style.rawValue) font=\(f.fontName) size=\(f.pointSize)")
        }
        for size in [CGFloat(11), 12, 13] {
            for weight in [UIFont.Weight.regular, .medium] {
                let font = UIFont.systemFont(ofSize: size, weight: weight)
                for name in candidates {
                    let w = (name as NSString).size(withAttributes: [.font: font]).width
                    print(String(format: "PROBE width size=%.0f weight=%@ w=%.2f name=%@",
                                 size, weight == .regular ? "regular" : "medium", w, name))
                }
            }
        }

        for page in 0..<5 {
            for icon in springboard.icons.allElementsBoundByIndex where icon.isHittable || icon.frame.minX >= 0 {
                print("PROBE page=\(page) icon label=\(icon.label) frame=\(icon.frame)")
            }
            let shot = XCUIScreen.main.screenshot()
            let a = XCTAttachment(screenshot: shot)
            a.name = "homescreen-page\(page)"
            a.lifetime = .keepAlways
            add(a)
            springboard.swipeLeft()
            sleep(2)
        }
        XCTFail("PROBE done: failing on purpose so CI exports the screenshots")
    }
}
