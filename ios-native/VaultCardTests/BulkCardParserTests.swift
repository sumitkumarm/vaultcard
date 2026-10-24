import UIKit
import XCTest
@testable import VaultCard

@MainActor
final class BulkCardParserTests: XCTestCase {
    func testRequestedMonthAndYearVariants() {
        for month in ["May", "may", "Aug", "August", "august", "08", "8"] {
            for year in ["26", "'26", "’26", "2026"] {
                let expected = month.lowercased().hasPrefix("may") ? "05/26" : "08/26"
                for grid in ["4111 1111 1111 1111,\(month),\(year),123",
                             "4111111111111111|\(month) \(year)|",
                             "4111 1111 1111 1111 \(month) \(year) 123"] {
                    let row = BulkCardParser.parse(grid).first
                    XCTAssertEqual(row?.expiry, expected, "\(month) \(year)")
                    XCTAssertEqual(row?.cardNumber, "4111111111111111")
                    XCTAssertNil(row?.issue)
                }
            }
        }
    }

    func testQuotedCSVAndOmittedCode() {
        let rows = BulkCardParser.parse(#""4111 1111 1111 1111","May","'26","012""#)
        XCTAssertEqual(rows.first?.expiry, "05/26")
        XCTAssertEqual(rows.first?.code, "012")
        XCTAssertNil(rows.first?.issue)
        let missing = BulkCardParser.parse("4111111111111111,May,2026,")
        XCTAssertEqual(missing.first?.code, "")
        XCTAssertNil(missing.first?.issue)
    }

    func testParsesDelimitedCombinedAndSplitExpiryColumns() {
        let rows = BulkCardParser.parse("""
        Card Number | Expiry | CVV
        4111 1111 1111 1111 | September 2026 | 123
        5555555555554444, 9, '27, 987
        """)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cardNumber, "4111111111111111")
        XCTAssertEqual(rows[0].expiry, "09/26")
        XCTAssertEqual(rows[0].code, "123")
        XCTAssertEqual(rows[1].cardNumber, "5555555555554444")
        XCTAssertEqual(rows[1].expiry, "09/27")
        XCTAssertEqual(rows[1].code, "987")
        XCTAssertEqual(rows[0].sourceRow, 2)
    }

    func testKeepsEmptyDelimitedColumnsAndReassemblesPANFragments() {
        let rows = BulkCardParser.parse("""
        4111\t1111\t1111\t1111\t09/29\t123
        5555555555554444,,987
        """)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cardNumber, "4111111111111111")
        XCTAssertEqual(rows[0].expiry, "09/29")
        XCTAssertEqual(rows[0].code, "123")
        XCTAssertEqual(rows[1].cardNumber, "5555555555554444")
        XCTAssertEqual(rows[1].expiry, "")
        XCTAssertEqual(rows[1].code, "987")
    }

    func testParsesWhitespaceSeparatedMonthAndYearInsideDelimitedExpiryCell() {
        let rows = BulkCardParser.parse("4111111111111111|8 2026|123")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].expiry, "08/26")
        XCTAssertEqual(rows[0].code, "123")
    }

    func testParsesWhitespaceOCRRowsAndOptionalCode() {
        let rows = BulkCardParser.parse("""
        4111 1111 1111 1111 Sep 2028 123
        5555 5555 5555 4444 01/29
        """)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].expiry, "09/28")
        XCTAssertEqual(rows[0].code, "123")
        XCTAssertNil(rows[0].issue)
        XCTAssertEqual(rows[1].expiry, "01/29")
        XCTAssertEqual(rows[1].code, "")
        XCTAssertNil(rows[1].issue)
    }

    func testKeepsMalformedCandidateRowsForReview() {
        let rows = BulkCardParser.parse("4111111111111112 13/29 12")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cardNumber, "4111111111111112")
        XCTAssertEqual(rows[0].expiry, "13/29")
        XCTAssertEqual(rows[0].code, "12")
        XCTAssertNotNil(rows[0].issue)
    }

    func testPINHeaderMarksCodeAsPINAndInputMapsItToPIN() {
        let rows = BulkCardParser.parse("""
        Card Number,Expiry,PIN
        4111111111111111,12/28,1234
        """)

        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].codeIsPIN)
        XCTAssertEqual(rows[0].input.pin, "1234")
        XCTAssertEqual(rows[0].input.cvv, "")
        XCTAssertNil(rows[0].issue)
    }

    func testRowsDoNotShareColumnsAcrossLineBoundaries() {
        let rows = BulkCardParser.parse("""
        4111111111111111 09/29
        5555555555554444 10/30 987
        """)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].expiry, "09/29")
        XCTAssertEqual(rows[0].code, "")
        XCTAssertEqual(rows[1].expiry, "10/30")
        XCTAssertEqual(rows[1].code, "987")
    }

    func testVisionRecognizesTwoSyntheticGridRowsWithoutCrossPairing() async throws {
        let image = makeGridImage()
        let rows = try await BulkCardParser.recognize(image)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.cardNumber), ["4111111111111111", "5555555555554444"])
        XCTAssertEqual(rows.map(\.expiry), ["09/29", "10/30"])
        XCTAssertEqual(rows.map(\.code), ["123", "987"])
    }

    private func makeGridImage() -> UIImage {
        let size = CGSize(width: 1400, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 38, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            let rows = [
                ("4111111111111111", "09/29", "123", CGFloat(45)),
                ("5555555555554444", "10/30", "987", CGFloat(190))
            ]
            for (pan, expiry, code, top) in rows {
                pan.draw(at: CGPoint(x: 32, y: top), withAttributes: attributes)
                expiry.draw(at: CGPoint(x: 650, y: top), withAttributes: attributes)
                code.draw(at: CGPoint(x: 900, y: top), withAttributes: attributes)
            }
        }
    }
}
