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
