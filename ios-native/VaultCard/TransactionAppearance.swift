import SwiftUI

enum TransactionDirectionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case debits = "Debits"
    case credits = "Credits"

    var id: String { rawValue }

    func includes(_ amount: Double) -> Bool {
        guard amount.isFinite else { return false }
        switch self {
        case .all: return true
        case .debits: return amount < 0
        case .credits: return amount > 0
        }
    }
}

enum TransactionAmountOrder {
    case highest
    case lowest

    func precedes(_ lhs: Double, _ rhs: Double) -> Bool {
        switch self {
        case .highest: return abs(lhs) > abs(rhs)
        case .lowest: return abs(lhs) < abs(rhs)
        }
    }
}

struct TransactionAmountRange: Equatable {
    var minimum: Double? = nil
    var maximum: Double? = nil

    var isActive: Bool { minimum != nil || maximum != nil }

    func includes(_ amount: Double) -> Bool {
        guard amount.isFinite else { return false }
        let magnitude = abs(amount)
        return (minimum.map { magnitude >= $0 } ?? true)
            && (maximum.map { magnitude <= $0 } ?? true)
    }

    static func parse(minimum: String, maximum: String, locale: Locale = .current) throws -> Self {
        let lower = try bound(minimum, locale: locale)
        let upper = try bound(maximum, locale: locale)
        if let lower, let upper, lower > upper {
            throw VaultError.validation("Minimum amount must be no greater than maximum amount.")
        }
        return Self(minimum: lower, maximum: upper)
    }

    private static func bound(_ text: String, locale: Locale) throws -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let decimal = formatter.decimalSeparator ?? "."
        let grouping = formatter.groupingSeparator ?? ","
        let d = NSRegularExpression.escapedPattern(for: decimal)
        let g = NSRegularExpression.escapedPattern(for: grouping)
        let whole = "(?:[0-9]+|[0-9]{1,3}(?:\(g)[0-9]{3})+)"
        let pattern = "^(?:\(whole)(?:\(d)[0-9]{0,2})?|\(d)[0-9]{1,2})$"
        let normalized = value.replacingOccurrences(of: grouping, with: "")
            .replacingOccurrences(of: decimal, with: ".")
        guard value.range(of: pattern, options: .regularExpression) != nil,
              let amount = Double(normalized), amount.isFinite, amount >= 0 else {
            throw VaultError.validation("Enter a positive amount with up to two decimal places. Use Debits or Credits to choose the transaction type.")
        }
        return amount
    }
}

enum TransactionInitialLoad {
    static func key(cardID: String, transactionID: String) -> String {
        "\(cardID):\(transactionID)"
    }

    static func ids(for card: VaultCard, overrides: [String: Bool]) -> Set<String> {
        let credits = card.transactions.filter { $0.amount.isFinite && $0.amount > 0 }
        let marked = credits.filter { overrides[key(cardID: card.id, transactionID: $0.id)] == true }
        if !marked.isEmpty { return Set(marked.map(\.id)) }
        guard let first = credits.min(by: {
            $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id
        }), overrides[key(cardID: card.id, transactionID: first.id)] != false else { return [] }
        return [first.id]
    }
}

struct TransactionAppearance {
    enum Kind: Equatable {
        case debit
        case credit
        case adjustment
    }

    let amount: Double

    var kind: Kind {
        if amount > 0 { return .credit }
        if amount < 0 { return .debit }
        return .adjustment
    }

    var kindLabel: String {
        switch kind {
        case .debit: return "Debit"
        case .credit: return "Credit"
        case .adjustment: return "Adjustment"
        }
    }

    var iconName: String {
        switch kind {
        case .debit: return "bag.fill"
        case .credit: return "arrow.down.left"
        case .adjustment: return "slider.horizontal.3"
        }
    }

    var formattedAmount: String {
        let magnitude = abs(amount).formatted(.currency(code: "USD"))
        switch kind {
        case .debit: return "−\(magnitude)"
        case .credit: return "+\(magnitude)"
        case .adjustment: return magnitude
        }
    }

    var accessibilityLabel: String {
        let magnitude = abs(amount).formatted(.currency(code: "USD"))
        switch kind {
        case .debit: return "Debit, minus \(magnitude)"
        case .credit: return "Credit, plus \(magnitude)"
        case .adjustment: return "Adjustment, \(magnitude)"
        }
    }

    func amountColor(for colorScheme: ColorScheme) -> Color {
        switch kind {
        case .credit:
            return colorScheme == .dark
                ? Color(red: 0.48, green: 0.86, blue: 0.58)
                : Color(red: 0.06, green: 0.42, blue: 0.17)
        case .debit:
            return .primary
        case .adjustment:
            return .secondary
        }
    }

    func iconColor(for colorScheme: ColorScheme) -> Color {
        switch kind {
        case .credit:
            return amountColor(for: colorScheme)
        case .debit, .adjustment:
            return .secondary
        }
    }
}

struct TransactionIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let amount: Double

    var body: some View {
        let appearance = TransactionAppearance(amount: amount)
        VaultRowIcon(
            symbol: appearance.iconName,
            color: appearance.iconColor(for: colorScheme)
        )
        .accessibilityHidden(true)
    }
}

struct TransactionAmountLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let amount: Double
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        let appearance = TransactionAppearance(amount: amount)
        VStack(alignment: .trailing, spacing: 2) {
            Text(appearance.formattedAmount)
                .font(font)
                .foregroundStyle(appearance.amountColor(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if appearance.kind != .debit {
                Text(appearance.kindLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(appearance.amountColor(for: colorScheme))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.accessibilityLabel)
    }
}
