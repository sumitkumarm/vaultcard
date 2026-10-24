import Foundation
import ImageIO
import UIKit
import Vision

struct BulkCardRow: Identifiable {
    var id = UUID()
    var cardNumber: String
    var expiry: String
    var code: String
    var codeIsPIN: Bool
    var sourceRow: Int

    var issue: String? {
        var problems: [String] = []
        if !CardRules.isValidCardNumber(cardNumber) {
            problems.append("Card number is invalid")
        }
        if !CardRules.validateExpiry(expiry) {
            problems.append("Expiry must use MM/YY")
        }
        if !code.isEmpty {
            let validCode = codeIsPIN
                ? code.range(of: #"^\d{4}$"#, options: .regularExpression) != nil
                : CardRules.validateCVV(code)
            if !validCode {
                problems.append(codeIsPIN ? "PIN must contain 4 digits" : "CVV must contain 3 or 4 digits")
            }
        }
        return problems.isEmpty ? nil : problems.joined(separator: "; ")
    }

    var input: CardInput {
        CardInput(
            cardNumber: cardNumber,
            expiry: expiry,
            cvv: codeIsPIN ? "" : code,
            pin: codeIsPIN ? code : ""
        )
    }
}

enum BulkCardParser {
    private struct OCRFragment {
        var text: String
        var x: CGFloat
        var maxX: CGFloat
        var y: CGFloat
        var height: CGFloat
    }

    private struct ExpiryMatch {
        var value: String
        var tokenCount: Int
    }

    static func parse(_ text: String) -> [BulkCardRow] {
        let lines = text.components(separatedBy: .newlines)
        let pinHeaders = lines.contains { isHeader($0) && headerHasPIN($0) }

        return lines.enumerated().compactMap { index, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !isHeader(line) else { return nil }
            return parseRow(line, sourceRow: index + 1, codeIsPIN: pinHeaders)
        }
    }

    static func recognize(_ image: UIImage) async throws -> [BulkCardRow] {
        let orientation = cgImageOrientation(image.imageOrientation)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    request.recognitionLanguages = ["en-US"]

                    let handler: VNImageRequestHandler
                    if let cgImage = image.cgImage {
                        handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                    } else if let ciImage = image.ciImage {
                        handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation)
                    } else {
                        throw RecognitionError.imageUnavailable
                    }
                    try handler.perform([request])

                    let fragments = (request.results ?? []).compactMap { observation -> OCRFragment? in
                        guard let text = observation.topCandidates(1).first?.string,
                              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                        let box = observation.boundingBox
                        return OCRFragment(
                            text: text,
                            x: box.minX,
                            maxX: box.maxX,
                            y: box.midY,
                            height: box.height
                        )
                    }
                    continuation.resume(returning: parse(assembleRows(fragments)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private enum RecognitionError: Error {
        case imageUnavailable
    }

    private static func cgImageOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        case .up: return .up
        @unknown default: return .up
        }
    }

    /// Vision may return separate observations for each cell. Cluster by vertical
    /// center first, then rebuild each row left-to-right so columns never pair
    /// with values from a neighboring card row.
    private static func assembleRows(_ fragments: [OCRFragment]) -> String {
        let sorted = fragments.sorted { $0.y > $1.y }
        var rows: [[OCRFragment]] = []
        for fragment in sorted {
            if let rowIndex = rows.indices.min(by: {
                abs(rows[$0].map(\.y).reduce(0, +) / CGFloat(rows[$0].count) - fragment.y)
                    < abs(rows[$1].map(\.y).reduce(0, +) / CGFloat(rows[$1].count) - fragment.y)
            }), let first = rows[rowIndex].first {
                let center = rows[rowIndex].map(\.y).reduce(0, +) / CGFloat(rows[rowIndex].count)
                let tolerance = min(0.025, min(first.height, fragment.height) * 0.8)
                if abs(center - fragment.y) <= tolerance {
                    rows[rowIndex].append(fragment)
                    continue
                }
            }
            rows.append([fragment])
        }

        return rows.map { row in
            let ordered = row.sorted { $0.x < $1.x }
            var result = ""
            var previous: OCRFragment?
            for fragment in ordered {
                if let previous {
                    let gap = fragment.x - previous.maxX
                    let columnGap = max(0.026, max(previous.height, fragment.height) * 1.6)
                    result += gap >= columnGap ? "\t" : " "
                }
                result += fragment.text
                previous = fragment
            }
            return result
        }.joined(separator: "\n")
    }

    private static func parseRow(_ line: String, sourceRow: Int, codeIsPIN: Bool) -> BulkCardRow {
        if let columns = delimitedColumns(line), columns.count > 1 {
            return parseDelimited(columns, sourceRow: sourceRow, codeIsPIN: codeIsPIN)
        }
        return parseWhitespaceRow(line, sourceRow: sourceRow, codeIsPIN: codeIsPIN)
    }

    private static func delimitedColumns(_ line: String) -> [String]? {
        guard line.contains(where: { $0 == "," || $0 == "\t" || $0 == ";" || $0 == "|" }) else { return nil }
        var columns: [String] = []
        var cell = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if character == "\"" {
                if quoted, next < line.endIndex, line[next] == "\"" {
                    cell.append("\"")
                    index = line.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if !quoted && [",", "\t", ";", "|"].contains(character) {
                columns.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
                cell = ""
            } else { cell.append(character) }
            index = next
        }
        columns.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
        return columns
    }

    private static func parseDelimited(_ columns: [String], sourceRow: Int, codeIsPIN: Bool) -> BulkCardRow {
        var cardDigits = ""
        var panFieldCount = 0
        for index in columns.indices {
            var field = columns[index]
            if index == 0 { field = removeLeadingLabel(field, labels: ["card", "number", "pan"]) }
            if index > 0, index + 1 < columns.count,
               cardDigits.count >= 12, isMonth(field), isYear(columns[index + 1]) {
                break
            }
            guard isNumericGroup(field) else { break }
            let digits = digitsOnly(field)
            guard !digits.isEmpty, cardDigits.count + digits.count <= 19 else { break }
            cardDigits += digits
            panFieldCount += 1
            if cardDigits.count >= 13 { break }
        }

        var expiry = ""
        var used = Set<Int>(columns.indices.filter { $0 < panFieldCount })
        let firstBodyColumn = max(1, panFieldCount)
        if columns.indices.contains(firstBodyColumn) {
            if let match = expiryMatch(in: columns[firstBodyColumn]) {
                expiry = match.value
                used.insert(firstBodyColumn)
            } else if columns.indices.contains(firstBodyColumn + 1),
                      isMonth(columns[firstBodyColumn]), isYear(columns[firstBodyColumn + 1]) {
                let month = columns[firstBodyColumn]
                let year = columns[firstBodyColumn + 1]
                expiry = makeExpiry(month: month, year: year) ?? "\(month)/\(year)"
                used.formUnion([firstBodyColumn, firstBodyColumn + 1])
            } else if !columns[firstBodyColumn].isEmpty {
                expiry = stripExpiryLabel(columns[firstBodyColumn])
                used.insert(firstBodyColumn)
            }
        }

        let codeColumn = columns.indices.reversed().first { !used.contains($0) }
        let code = codeColumn.map { cleanCode(columns[$0]) } ?? ""
        return BulkCardRow(
            cardNumber: cardDigits,
            expiry: expiry,
            code: code,
            codeIsPIN: codeIsPIN,
            sourceRow: sourceRow
        )
    }

    private static func parseWhitespaceRow(_ line: String, sourceRow: Int, codeIsPIN: Bool) -> BulkCardRow {
        var tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        while let first = tokens.first, isCardLabel(first) {
            tokens.removeFirst()
        }

        var panTokens: [String] = []
        var panDigits = ""
        for token in tokens {
            guard isNumericGroup(token) else { break }
            let digits = digitsOnly(token)
            guard panDigits.count + digits.count <= 19 else { break }
            panTokens.append(token)
            panDigits += digits
            if panDigits.count >= 13 { break }
        }

        let body = Array(tokens.dropFirst(panTokens.count))
        var expiry = ""
        var usedBodyIndices = Set<Int>()
        if !body.isEmpty {
            for index in body.indices {
                if let match = expiryMatch(in: body[index]) {
                    expiry = match.value
                    usedBodyIndices.insert(index)
                    if match.tokenCount == 2, body.indices.contains(index + 1) {
                        usedBodyIndices.insert(index + 1)
                    }
                    break
                }
                if index + 1 < body.count, isMonth(body[index]), isYear(body[index + 1]) {
                    expiry = makeExpiry(month: body[index], year: body[index + 1])
                        ?? "\(body[index])/\(body[index + 1])"
                    usedBodyIndices.formUnion([index, index + 1])
                    break
                }
            }
        }

        if expiry.isEmpty {
            // Keep the nearest non-code field as an editable malformed expiry candidate.
            let values = body.enumerated().filter { !usedBodyIndices.contains($0.offset) && !isFieldLabel($0.element) }
            if let candidate = values.first(where: { !isLikelyCode($0.element) }) {
                expiry = stripExpiryLabel(candidate.element)
            }
        }

        let remaining = body.enumerated().filter { !usedBodyIndices.contains($0.offset) && !isFieldLabel($0.element) }
        let code = remaining.last.map { cleanCode($0.element) } ?? ""
        return BulkCardRow(
            cardNumber: panDigits,
            expiry: expiry,
            code: code,
            codeIsPIN: codeIsPIN,
            sourceRow: sourceRow
        )
    }

    private static func expiryMatch(in raw: String) -> ExpiryMatch? {
        let value = stripExpiryLabel(raw)
        if let normalized = normalizeExpiry(value) {
            return ExpiryMatch(value: normalized, tokenCount: 1)
        }
        let pieces = value.split(whereSeparator: \.isWhitespace).map(String.init)
        if pieces.count == 2, isMonth(pieces[0]), isYear(pieces[1]) {
            let normalized = makeExpiry(month: pieces[0], year: pieces[1])
            return ExpiryMatch(value: normalized ?? "\(pieces[0])/\(pieces[1])", tokenCount: 1)
        }
        // Retain month/year-shaped invalid values, such as 13/29, for review.
        if matches(value, pattern: #"^(?:\d{1,2}|[A-Za-z]{3,9})\s*[/.-]\s*['’]?\d{2,4}$"#) {
            return ExpiryMatch(value: value, tokenCount: 1)
        }
        if matches(value, pattern: #"^\d{3,6}$"#) {
            let digits = digitsOnly(value)
            if digits.count == 4 || digits.count == 6 {
                let monthLength = digits.count == 4 ? 2 : 2
                let month = String(digits.prefix(monthLength))
                let year = String(digits.dropFirst(monthLength))
                if isMonth(month) { return ExpiryMatch(value: makeExpiry(month: month, year: year) ?? value, tokenCount: 1) }
            }
        }
        return nil
    }

    private static func normalizeExpiry(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = value.range(of: #"^(0?[1-9]|1[0-2])\s*[/.-]\s*['’]?(\d{2}|\d{4})$"#, options: .regularExpression) {
            let parts = value[match].split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." })
            guard parts.count == 2 else { return nil }
            return makeExpiry(month: String(parts[0]), year: String(parts[1]))
        }
        if let match = value.range(of: #"^([A-Za-z]{3,9})\s*[/.-]?\s*['’]?(\d{2}|\d{4})$"#, options: .regularExpression) {
            let matched = String(value[match])
            let pieces = matched.split(whereSeparator: { $0.isWhitespace || $0 == "/" || $0 == "-" || $0 == "." || $0 == "'" || $0 == "’" })
            guard pieces.count == 2 else { return nil }
            return makeExpiry(month: String(pieces[0]), year: String(pieces[1]))
        }
        if matches(value, pattern: #"^(0[1-9]|1[0-2])(\d{2}|\d{4})$"#) {
            let digits = digitsOnly(value)
            return makeExpiry(month: String(digits.prefix(2)), year: String(digits.dropFirst(2)))
        }
        return nil
    }

    private static func makeExpiry(month: String, year: String) -> String? {
        guard let monthNumber = monthNumber(month), (1...12).contains(monthNumber), isYear(year) else { return nil }
        let yearDigits = digitsOnly(year)
        return String(format: "%02d/%02d", monthNumber, Int(yearDigits.suffix(2)) ?? 0)
    }

    private static func monthNumber(_ value: String) -> Int? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let number = Int(cleaned), (1...12).contains(number) { return number }
        let names: [String: Int] = [
            "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
            "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7,
            "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12
        ]
        return names[cleaned]
    }

    private static func isMonth(_ value: String) -> Bool {
        monthNumber(value) != nil || matches(value, pattern: #"^\d{1,2}$"#)
    }

    private static func isYear(_ value: String) -> Bool {
        matches(value.trimmingCharacters(in: CharacterSet(charactersIn: "'’")), pattern: #"^\d{2}(?:\d{2})?$"#)
    }

    private static func isHeader(_ line: String) -> Bool {
        guard !line.contains(where: \.isNumber) else { return false }
        let normalized = line.lowercased()
        let hasColumnWord = ["card", "number", "pan", "expiry", "expiration", "exp", "month", "year", "cvv", "cvc", "pin", "code"]
            .contains { normalized.range(of: #"\b\#($0)\b"#, options: .regularExpression) != nil }
        return hasColumnWord
    }

    private static func headerHasPIN(_ line: String) -> Bool {
        line.lowercased().range(of: #"\bpin\b"#, options: .regularExpression) != nil
    }

    private static func isCardLabel(_ token: String) -> Bool {
        let cleaned = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":#"))
        return ["card", "number", "pan", "no"].contains(cleaned)
    }

    private static func isFieldLabel(_ token: String) -> Bool {
        let cleaned = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":#"))
        return ["expiry", "expiration", "exp", "cvv", "cvc", "pin", "code"].contains(cleaned)
    }

    private static func stripExpiryLabel(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?i)^(exp|expiry|expiration)\s*[:=]?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanCode(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"(?i)^(cvv|cvc|pin|code)\s*[:=]?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeLeadingLabel(_ value: String, labels: Set<String>) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in labels {
            let pattern = #"(?i)^\s*\#(label)\s*[:#]?\s*"#
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result
    }

    private static func isNumericGroup(_ token: String) -> Bool {
        matches(token, pattern: #"^[\d\s-]+$"#)
    }

    private static func isLikelyCode(_ token: String) -> Bool {
        let value = cleanCode(token)
        return matches(value, pattern: #"^\d{3,4}$"#)
    }

    private static func digitsOnly(_ value: String) -> String {
        String(value.filter(\.isNumber))
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
