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
    struct OCRFragment {
        var text: String
        var x: CGFloat
        var maxX: CGFloat
        var y: CGFloat
        var height: CGFloat
    }

    private enum ColumnKind: Hashable {
        case card
        case month
        case year
        case expiry
        case code
        case pin
    }

    private struct ColumnAnchor {
        var kind: ColumnKind
        var x: CGFloat
    }

    private struct TextHeader {
        var card: Int?
        var month: Int?
        var year: Int?
        var expiry: Int?
        var code: Int?
        var codeIsPIN: Bool
    }

    private struct CardCandidate {
        var digits: String
        var start: Int
        var end: Int
        var score: Int
    }

    private struct ExpiryMatch {
        var value: String
        var tokenCount: Int
    }

    static func parse(_ text: String) -> [BulkCardRow] {
        let lines = text.components(separatedBy: .newlines)
        let header = lines.enumerated().compactMap { index, line -> (Int, TextHeader)? in
            guard let columns = delimitedColumns(line), let header = textHeader(columns) else { return nil }
            return (index, header)
        }.first

        if let header {
            let (headerIndex, headerLayout) = header
            return lines.enumerated().compactMap { index, rawLine in
                guard index > headerIndex,
                      let columns = delimitedColumns(rawLine),
                      let row = parseTextHeaderRow(columns, header: headerLayout, sourceRow: index + 1) else { return nil }
                return row
            }
        }

        return lines.enumerated().compactMap { index, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !isHeader(line) else { return nil }
            let parsed = parseRow(line, sourceRow: index + 1, codeIsPIN: false)
            return parsed.cardNumber.count >= 12 ? parsed : nil
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

                    let fragments = (request.results ?? []).flatMap(ocrFragments)
                    continuation.resume(returning: parseOCRFragments(fragments))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private enum RecognitionError: Error {
        case imageUnavailable
    }

    /// Keeps the word-level Vision geometry so grid columns survive OCR. This is
    /// internal to the module so tests can exercise dense layouts deterministically.
    static func parseOCRFragments(_ fragments: [OCRFragment]) -> [BulkCardRow] {
        let rows = clusterOCRRows(fragments)
        guard let header = rows.enumerated().compactMap({ index, row in
            geometryHeader(row).map { (index, $0.0, $0.1) }
        }).first else {
            // Headerless OCR still benefits from keeping each visual line intact.
            return rows.enumerated().compactMap { index, row in
                let text = row.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
                guard !text.isEmpty, !isHeader(text) else { return nil }
                let parsed = parseRow(text, sourceRow: index + 1, codeIsPIN: false)
                return parsed.cardNumber.count >= 12 ? parsed : nil
            }
        }

        return rows.enumerated().compactMap { index, row in
            guard index > header.0, !isGeometryHeader(row) else { return nil }
            return parseGeometryRow(row, anchors: header.1, codeIsPIN: header.2, sourceRow: index + 1)
        }
    }

    private static func ocrFragments(_ observation: VNRecognizedTextObservation) -> [OCRFragment] {
        guard let candidate = observation.topCandidates(1).first else { return [] }
        let text = candidate.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let start, start < index { ranges.append(start..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let start, start < text.endIndex { ranges.append(start..<text.endIndex) }
        guard !ranges.isEmpty else { return [] }

        let fallback = observation.boundingBox
        let length = max(1, text.count)
        return ranges.map { range in
            let token = String(text[range])
            if let tokenBox = try? candidate.boundingBox(for: range) {
                let box = tokenBox.boundingBox
                return OCRFragment(text: token, x: box.minX, maxX: box.maxX, y: box.midY, height: box.height)
            }
            let leading = CGFloat(text.distance(from: text.startIndex, to: range.lowerBound)) / CGFloat(length)
            let trailing = CGFloat(text.distance(from: text.startIndex, to: range.upperBound)) / CGFloat(length)
            let minX = fallback.minX + fallback.width * leading
            let maxX = fallback.minX + fallback.width * trailing
            return OCRFragment(
                text: token,
                x: minX,
                maxX: max(maxX, minX + fallback.width / CGFloat(ranges.count)),
                y: fallback.midY,
                height: fallback.height
            )
        }
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

    private static func clusterOCRRows(_ fragments: [OCRFragment]) -> [[OCRFragment]] {
        var rows: [[OCRFragment]] = []
        for fragment in fragments.sorted(by: { $0.y > $1.y }) {
            var best: (index: Int, residual: CGFloat)?
            for index in rows.indices {
                let residual = abs(predictedY(in: rows[index], at: (fragment.x + fragment.maxX) / 2) - fragment.y)
                let rowHeight = rows[index].map(\.height).sorted().dropFirst(rows[index].count / 2).first ?? fragment.height
                let tolerance = min(0.021, max(0.008, min(rowHeight, fragment.height) * 1.0))
                guard residual <= tolerance else { continue }
                if best == nil || residual < best!.residual { best = (index, residual) }
            }
            if let best { rows[best.index].append(fragment) }
            else { rows.append([fragment]) }
        }
        let orderedRows: [[OCRFragment]] = rows.map { row in
            row.sorted { lhs, rhs in lhs.x < rhs.x }
        }
        return orderedRows.sorted { lhs, rhs in
            let lhsMeanY = lhs.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(max(1, lhs.count))
            let rhsMeanY = rhs.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(max(1, rhs.count))
            return lhsMeanY > rhsMeanY
        }
    }

    private static func predictedY(in row: [OCRFragment], at x: CGFloat) -> CGFloat {
        guard !row.isEmpty else { return 0 }
        let centers = row.map { (($0.x + $0.maxX) / 2, $0.y) }
        let meanX = centers.map(\.0).reduce(0, +) / CGFloat(centers.count)
        let meanY = centers.map(\.1).reduce(0, +) / CGFloat(centers.count)
        let variance = centers.reduce(CGFloat.zero) { $0 + pow($1.0 - meanX, 2) }
        guard variance > 0.000001 else { return meanY }
        let covariance = centers.reduce(CGFloat.zero) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        return meanY + (covariance / variance) * (x - meanX)
    }

    private static func geometryHeader(_ row: [OCRFragment]) -> ([ColumnAnchor], Bool)? {
        var positions: [ColumnKind: [CGFloat]] = [:]
        for fragment in row {
            guard let kind = headerKind(fragment.text) else { continue }
            positions[kind, default: []].append((fragment.x + fragment.maxX) / 2)
        }
        guard let cardX = positions[.card]?.first else { return nil }

        let balanceX = row.first(where: { $0.text.lowercased().contains("balance") })
            .map { ($0.x + $0.maxX) / 2 }
        if let balanceX, balanceX > cardX {
            let known = positions.values.flatMap { $0 }
            let unknownPositions = row.filter { fragment in
                let x = (fragment.x + fragment.maxX) / 2
                return headerKind(fragment.text) == nil
                    && x > cardX + 0.035 && x < balanceX - 0.025
                    && !known.contains(where: { abs($0 - x) < 0.03 })
            }.map { ($0.x + $0.maxX) / 2 }
            let unknown = unknownPositions.sorted()
            var needed: [ColumnKind] = []
            if positions[.expiry] == nil {
                if positions[.month] == nil { needed.append(.month) }
                if positions[.year] == nil { needed.append(.year) }
            }
            for (kind, x) in zip(needed, unknown) { positions[kind, default: []].append(x) }

        }

        let hasExpiry = positions[.expiry] != nil || (positions[.month] != nil && positions[.year] != nil)
        guard hasExpiry else { return nil }

        var anchors: [ColumnAnchor] = []
        for (kind, xs) in positions {
            let groups = groupHeaderPositions(xs)
            anchors.append(contentsOf: groups.map { ColumnAnchor(kind: kind, x: $0) })
        }
        return (anchors.sorted { $0.x < $1.x }, positions[.pin] != nil)
    }

    private static func groupHeaderPositions(_ positions: [CGFloat]) -> [CGFloat] {
        let ordered = positions.sorted()
        var groups: [[CGFloat]] = []
        for x in ordered {
            if let last = groups.indices.last, x - (groups[last].last ?? x) <= 0.045 {
                groups[last].append(x)
            } else {
                groups.append([x])
            }
        }
        return groups.map { $0.reduce(0, +) / CGFloat($0.count) }
    }

    private static func isGeometryHeader(_ row: [OCRFragment]) -> Bool {
        geometryHeader(row) != nil
    }

    private static func headerKind(_ raw: String) -> ColumnKind? {
        let normalized = raw.lowercased().filter(\.isLetter)
        if normalized.contains("securitycode") { return .code }
        if normalized.contains("month") { return .month }
        if normalized.contains("year") { return .year }
        if normalized.contains("expiry") || normalized.contains("expiration") { return .expiry }
        switch normalized {
        case "card", "number", "pan", "cardnumber": return .card
        case "month", "months": return .month
        case "year", "date": return .year
        case "expiry", "expiration", "exp": return .expiry
        case "cvv", "cvc", "securitycode", "code": return .code
        case "pin": return .pin
        case "cw", "cwy", "cwv", "cvy": return .code
        default: return nil
        }
    }

    private static func parseGeometryRow(
        _ row: [OCRFragment],
        anchors: [ColumnAnchor],
        codeIsPIN: Bool,
        sourceRow: Int
    ) -> BulkCardRow? {
        let ordered = row.sorted { $0.x < $1.x }
        let allFields = ordered.map(\.text)
        guard let candidate = bestCardCandidate(in: allFields), candidate.digits.count >= 12 else { return nil }
        let panFragments = Array(ordered[candidate.start...candidate.end])
        let panCenter = (panFragments.map(\.x).min()! + panFragments.map(\.maxX).max()!) / 2
        let rowAnchors = anchors.map { anchor in
            anchor.kind == .card ? ColumnAnchor(kind: .card, x: panCenter) : anchor
        }
        let panIndices = Set(candidate.start...candidate.end)

        var cells: [ColumnKind: [OCRFragment]] = [:]
        for (index, fragment) in ordered.enumerated() where !panIndices.contains(index) {
            guard let kind = nearestColumn(to: (fragment.x + fragment.maxX) / 2, anchors: rowAnchors) else { continue }
            cells[kind, default: []].append(fragment)
        }

        var expiry = ""
        if let expiryCell = joinedCell(cells[.expiry]), let match = expiryMatch(in: expiryCell) {
            expiry = match.value
        }
        if expiry.isEmpty, let month = joinedCell(cells[.month]), let year = joinedCell(cells[.year]) {
            expiry = makeExpiry(month: month, year: year) ?? "\(month)/\(year)"
        }
        let codeKind: ColumnKind = codeIsPIN ? .pin : .code
        let code = joinedCell(cells[codeKind]).map(cleanCode) ?? ""
        return BulkCardRow(
            cardNumber: candidate.digits,
            expiry: expiry,
            code: code,
            codeIsPIN: codeIsPIN,
            sourceRow: sourceRow
        )
    }

    private static func nearestColumn(to x: CGFloat, anchors: [ColumnAnchor]) -> ColumnKind? {
        let ordered = anchors.sorted { $0.x < $1.x }
        guard let nearestIndex = ordered.indices.min(by: { abs(ordered[$0].x - x) < abs(ordered[$1].x - x) }) else { return nil }
        let anchor = ordered[nearestIndex]
        let leftGap = nearestIndex > 0 ? anchor.x - ordered[nearestIndex - 1].x : (ordered.dropFirst().first?.x ?? anchor.x + 0.1) - anchor.x
        let rightGap = nearestIndex + 1 < ordered.count ? ordered[nearestIndex + 1].x - anchor.x : leftGap
        let halfGap = max(0.012, min(leftGap, rightGap) * 0.58)
        guard abs(x - anchor.x) <= halfGap + 0.018 else { return nil }
        return anchor.kind
    }

    private static func joinedCell(_ fragments: [OCRFragment]?) -> String? {
        guard let fragments, !fragments.isEmpty else { return nil }
        return fragments.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func textHeader(_ columns: [String]) -> TextHeader? {
        var result = TextHeader(codeIsPIN: false)
        for index in columns.indices {
            let normalized = columns[index].lowercased().filter(\.isLetter)
            if let kind = headerKind(normalized) {
                switch kind {
                case .card: result.card = result.card ?? index
                case .month: result.month = result.month ?? index
                case .year: result.year = result.year ?? index
                case .expiry: result.expiry = result.expiry ?? index
                case .code: result.code = result.code ?? index
                case .pin:
                    result.code = result.code ?? index
                    result.codeIsPIN = true
                }
            } else if normalized.contains("expiration") || normalized.contains("expiry") {
                result.expiry = result.expiry ?? index
            } else if normalized.contains("securitycode") {
                result.code = result.code ?? index
            }
        }
        guard result.card != nil,
              result.expiry != nil || (result.month != nil && result.year != nil) else { return nil }
        return result
    }

    private static func parseTextHeaderRow(
        _ columns: [String],
        header: TextHeader,
        sourceRow: Int
    ) -> BulkCardRow? {
        guard let cardIndex = header.card, columns.indices.contains(cardIndex) else { return nil }
        let cardField = removeLeadingLabel(columns[cardIndex], labels: ["card", "number", "pan"])
        guard let card = bestCardCandidate(in: cardField.split(whereSeparator: { $0.isWhitespace }).map(String.init)) else {
            return nil
        }

        var expiry = ""
        var splitYearIndex: Int?
        if let expiryIndex = header.expiry, columns.indices.contains(expiryIndex),
           let match = expiryMatch(in: columns[expiryIndex]) {
            expiry = match.value
        } else if let expiryIndex = header.expiry, columns.indices.contains(expiryIndex),
                  columns.indices.contains(expiryIndex + 1), isMonth(columns[expiryIndex]),
                  isYear(columns[expiryIndex + 1]) {
            expiry = makeExpiry(month: columns[expiryIndex], year: columns[expiryIndex + 1])
                ?? "\(columns[expiryIndex])/\(columns[expiryIndex + 1])"
            splitYearIndex = expiryIndex + 1
        }
        if expiry.isEmpty, let monthIndex = header.month, let yearIndex = header.year,
           columns.indices.contains(monthIndex), columns.indices.contains(yearIndex) {
            let month = columns[monthIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let year = columns[yearIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = expiryMatch(in: month) {
                expiry = match.value
            } else if !month.isEmpty || !year.isEmpty {
                expiry = makeExpiry(month: month, year: year) ?? "\(month)/\(year)"
            }
        }

        var codeIndex = header.code
        if let splitYearIndex, codeIndex == splitYearIndex, columns.indices.contains(splitYearIndex + 1) {
            codeIndex = splitYearIndex + 1
        }
        let code = codeIndex.flatMap { columns.indices.contains($0) ? cleanCode(columns[$0]) : nil } ?? ""
        return BulkCardRow(
            cardNumber: card.digits,
            expiry: expiry,
            code: code,
            codeIsPIN: header.codeIsPIN,
            sourceRow: sourceRow
        )
    }

    private static func parseDelimited(_ columns: [String], sourceRow: Int, codeIsPIN: Bool) -> BulkCardRow {
        let normalized = columns.enumerated().map { index, column in
            index == 0 ? removeLeadingLabel(column, labels: ["card", "number", "pan"]) : column
        }
        let candidate = bestCardCandidate(in: normalized)
        let cardDigits = candidate?.digits ?? ""
        let afterPAN = candidate.map { Array(normalized.dropFirst($0.end + 1)) } ?? []
        let (expiry, expiryIndices) = findExpiry(in: afterPAN)
        let code = firstCode(in: afterPAN, skipping: expiryIndices, hasExpiry: !expiry.isEmpty)
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

        let candidate = bestCardCandidate(in: tokens)
        let panDigits = candidate?.digits ?? ""
        let body = candidate.map { Array(tokens.dropFirst($0.end + 1)) } ?? []
        let (expiry, expiryIndices) = findExpiry(in: body)
        let code = firstCode(in: body, skipping: expiryIndices, hasExpiry: !expiry.isEmpty)
        return BulkCardRow(
            cardNumber: panDigits,
            expiry: expiry,
            code: code,
            codeIsPIN: codeIsPIN,
            sourceRow: sourceRow
        )
    }

    private static func bestCardCandidate(in fields: [String]) -> CardCandidate? {
        var best: CardCandidate?
        for start in fields.indices {
            var digits = ""
            var groupLengths: [Int] = []
            for end in start..<min(fields.count, start + 7) {
                let field = fields[end].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let group = normalizedCardGroup(field) else { break }
                guard !group.isEmpty, digits.count + group.count <= 19 else { break }
                digits += group
                groupLengths.append(group.count)
                guard (12...19).contains(digits.count) else { continue }

                let fourDigitGroups = groupLengths.filter { $0 == 4 }.count
                let shortGroups = groupLengths.filter { $0 <= 2 }.count
                let score = (digits.count == 16 ? 8 : 0)
                    + fourDigitGroups * 2
                    + (groupLengths.count == 1 ? 2 : 0)
                    - shortGroups * 3
                    + (CardRules.isValidCardNumber(digits) ? 2 : 0)
                let candidate = CardCandidate(digits: digits, start: start, end: end, score: score)
                if best == nil || candidate.score > best!.score
                    || (candidate.score == best!.score && candidate.digits.count > best!.digits.count) {
                    best = candidate
                }
            }
        }
        return best
    }

    private static func findExpiry(in fields: [String]) -> (value: String, indices: Set<Int>) {
        for index in fields.indices {
            if let match = expiryMatch(in: fields[index]) {
                var used = Set([index])
                if match.tokenCount == 2, fields.indices.contains(index + 1) { used.insert(index + 1) }
                return (match.value, used)
            }
            if fields.indices.contains(index + 1), isMonth(fields[index]), isYear(fields[index + 1]) {
                let expiry = makeExpiry(month: fields[index], year: fields[index + 1])
                    ?? "\(fields[index])/\(fields[index + 1])"
                return (expiry, [index, index + 1])
            }
        }

        // Keep a nearby malformed expiry value reviewable, while excluding a likely code.
        if let first = fields.indices.first,
           !isFieldLabel(fields[first]), !fields[first].isEmpty, !isLikelyCode(fields[first]) {
            return (stripExpiryLabel(fields[first]), [first])
        }
        return ("", [])
    }

    private static func firstCode(in fields: [String], skipping: Set<Int>, hasExpiry: Bool) -> String {
        let eligible = fields.indices.filter { !skipping.contains($0) && !isFieldLabel(fields[$0]) }
        let codeIndex = hasExpiry
            ? eligible.first(where: { $0 > (skipping.max() ?? -1) })
            : eligible.first(where: { !fields[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return codeIndex.map { cleanCode(fields[$0]) } ?? ""
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

    private static func normalizedCardGroup(_ raw: String) -> String? {
        let edgePunctuation = CharacterSet(charactersIn: ".,;:|\"'‘’()[]{}")
        let trimmed = raw.trimmingCharacters(in: edgePunctuation)
        guard isNumericGroup(trimmed) else { return nil }
        return digitsOnly(trimmed)
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
