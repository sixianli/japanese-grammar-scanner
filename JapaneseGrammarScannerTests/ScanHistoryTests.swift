import UIKit
import XCTest
@testable import JapaneseGrammarScanner

@MainActor
final class ScanHistoryTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults = UserDefaults(suiteName: UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func photo(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testRecordedScanIsListedBeforeItsImageIsWritten() {
        let store = HistoryStore(defaults: defaults, directory: directory)

        let id = store.recordScan(image: photo(width: 3000, height: 4000), grammarIDs: ["n5-kara"])

        XCTAssertEqual(store.scans.map(\.id), [id])
        XCTAssertEqual(store.scans.first?.grammarIDs, ["n5-kara"])
    }

    func testRecordedScanSurvivesRelaunchWithItsPhoto() async {
        let store = HistoryStore(defaults: defaults, directory: directory)
        let id = store.recordScan(image: photo(width: 3000, height: 4000), grammarIDs: ["n5-kara"])
        await store.waitForPendingWrites()

        let reopened = HistoryStore(defaults: defaults, directory: directory)

        XCTAssertEqual(reopened.scans.map(\.id), [id])
        let saved = reopened.image(for: reopened.scans[0])
        XCTAssertEqual(saved.map { max($0.size.width * $0.scale, $0.size.height * $0.scale) }, 2000)
    }

    func testThumbnailIsSmallAndKeepsAspect() async {
        let store = HistoryStore(defaults: defaults, directory: directory)
        store.recordScan(image: photo(width: 3000, height: 4000), grammarIDs: [])
        await store.waitForPendingWrites()

        let thumb = store.thumbnail(for: store.scans[0])

        XCTAssertEqual(thumb?.cgImage?.height, 320)
        XCTAssertEqual(thumb?.cgImage?.width, 240)
    }

    func testThumbnailOfMissingPhotoIsNil() {
        let store = HistoryStore(defaults: defaults, directory: directory)
        let record = HistoryStore.ScanRecord(id: UUID(), date: Date(), grammarIDs: [], imageFile: "missing.jpg")

        XCTAssertNil(store.thumbnail(for: record))
    }
}
