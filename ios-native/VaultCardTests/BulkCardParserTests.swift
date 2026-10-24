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

    func testHeaderMappingIgnoresRowLabelsAndTrailingColumns() {
        let rows = BulkCardParser.parse("""
        Row,Card,Month,Date (year),CVV,Balance,Last updated
        1,4111111111111111,09,35,021,48.25,10/24/2026
        2,5555555555554444,11,36,,19.00,10/24/2026
        """)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cardNumber, "4111111111111111")
        XCTAssertEqual(rows[0].expiry, "09/35")
        XCTAssertEqual(rows[0].code, "021")
        XCTAssertEqual(rows[1].cardNumber, "5555555555554444")
        XCTAssertEqual(rows[1].expiry, "11/36")
        XCTAssertEqual(rows[1].code, "")
    }

    func testHeaderWithoutSecurityCodeLeavesCodeEmpty() {
        let rows = BulkCardParser.parse("""
        Card,Month,Date (year),Balance,Last updated
        4111111111111111,9,2035,123,10/24/2026
        """)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].expiry, "09/35")
        XCTAssertEqual(rows[0].code, "")
    }

    func testExpiryMonthAndYearHeadersMapByComponent() {
        let row = BulkCardParser.parse("""
        Card,Expiry Month,Expiry Year,CVV,Balance
        4111111111111111,06,2035,021,123.00
        """).first

        XCTAssertEqual(row?.expiry, "06/35")
        XCTAssertEqual(row?.code, "021")
    }

    func testHeaderlessRowsUseFirstCVVCandidateBeforeTrailingData() {
        let row = BulkCardParser.parse("4111111111111111 09/35 021 48.25 10/24/2026").first

        XCTAssertEqual(row?.cardNumber, "4111111111111111")
        XCTAssertEqual(row?.expiry, "09/35")
        XCTAssertEqual(row?.code, "021")
    }

    func testEmptyCodeCellDoesNotUseLaterNumericColumns() {
        let row = BulkCardParser.parse("4111111111111111,06,35,,123,Jun08").first

        XCTAssertEqual(row?.expiry, "06/35")
        XCTAssertEqual(row?.code, "")
    }

    func testPANCandidateTrimsTrailingOCRPunctuationOnly() {
        let rows = BulkCardParser.parse("4111111111111111. 09/35 021")

        XCTAssertEqual(rows.first?.cardNumber, "4111111111111111")
        XCTAssertEqual(rows.first?.expiry, "09/35")
        XCTAssertEqual(rows.first?.code, "021")
        XCTAssertTrue(BulkCardParser.parse("48.25 06/35 123").isEmpty)
    }

    func testNoisyCVVHeadingDoesNotSelectFilterArrowAsCodeColumn() {
        for heading in ["CVV", "CW", "cWv", "CWY"] {
            var fragments = makeDenseTableFragments(rowCount: 23, omitCodeOn: [])
            let index = fragments.firstIndex { $0.text == "CW" }!
            fragments[index].text = heading
            let rows = BulkCardParser.parseOCRFragments(fragments)
            XCTAssertEqual(rows.count, 23)
            for rowIndex in rows.indices {
                XCTAssertEqual(rows[rowIndex].code, String(format: "%03d", (rowIndex * 7) % 1000))
            }
        }
    }

    func testDenseGeometryTableKeepsColumnsAndRowsAligned() {
        let fragments = makeDenseTableFragments(rowCount: 23, omitCodeOn: [7, 18])
        let rows = BulkCardParser.parseOCRFragments(fragments)

        XCTAssertEqual(rows.count, 23)
        for index in 0..<23 {
            let expectedPAN = String(format: "400000000000%04d", index + 1)
            let expectedExpiry = String(format: "%02d/%02d", index % 12 + 1, 35 + index / 12)
            let expectedCode = [7, 18].contains(index) ? "" : String(format: "%03d", (index * 7) % 1000)
            XCTAssertEqual(rows[index].cardNumber, expectedPAN, "row \(index + 1)")
            XCTAssertEqual(rows[index].expiry, expectedExpiry, "row \(index + 1)")
            XCTAssertEqual(rows[index].code, expectedCode, "row \(index + 1)")
        }
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

    private func makeDenseTableFragments(rowCount: Int, omitCodeOn missingCodeRows: Set<Int>) -> [BulkCardParser.OCRFragment] {
        var fragments: [BulkCardParser.OCRFragment] = []
        func add(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.025) {
            fragments.append(.init(text: text, x: x, maxX: x + width, y: y, height: 0.014))
        }

        let headerY: CGFloat = 0.965
        add("Card", x: 0.135, y: headerY)
        add("~", x: 0.385, y: headerY) // OCR miss for Month
        add("~", x: 0.545, y: headerY) // OCR miss for Date (year)
        add("CW", x: 0.685, y: headerY) // OCR commonly reads CVV this way
        add("Y", x: 0.707, y: headerY, width: 0.01)
        add("Balance", x: 0.805, y: headerY)
        add("Last", x: 0.925, y: headerY)
        add("updated", x: 0.951, y: headerY)

        for index in 0..<rowCount {
            let baseline = CGFloat(0.91 - Double(index) * 0.032)
            func skewedY(_ x: CGFloat) -> CGFloat { baseline + (x - 0.15) * 0.015 }
            add("\(index + 1)", x: 0.018, y: skewedY(0.018), width: 0.01) // spreadsheet row label
            let pan = String(format: "400000000000%04d", index + 1)
            for (groupIndex, start) in stride(from: 0, to: pan.count, by: 4).enumerated() {
                let lower = pan.index(pan.startIndex, offsetBy: start)
                let upper = pan.index(lower, offsetBy: min(4, pan.distance(from: lower, to: pan.endIndex)))
                let x = CGFloat(0.112 + Double(groupIndex) * 0.031)
                add(String(pan[lower..<upper]), x: x, y: skewedY(x), width: 0.027)
            }
            let monthX: CGFloat = 0.393
            let yearX: CGFloat = 0.563
            add(String(format: "%02d", index % 12 + 1), x: monthX, y: skewedY(monthX))
            add(String(2035 + index / 12), x: yearX, y: skewedY(yearX), width: 0.035)
            if !missingCodeRows.contains(index) {
                let codeX: CGFloat = 0.690
                add(String(format: "%03d", (index * 7) % 1000), x: codeX, y: skewedY(codeX))
            }
            let balanceX: CGFloat = 0.807
            add(String(format: "%.2f", Double(index + 1) * 12.5), x: balanceX, y: skewedY(balanceX), width: 0.045)
            let updatedX: CGFloat = 0.925
            add("10/24/2026", x: updatedX, y: skewedY(updatedX), width: 0.055)
        }
        return fragments
    }
}
