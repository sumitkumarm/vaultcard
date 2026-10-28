import Foundation
import SwiftUI

struct VaultFundsSummary {
    let total: Decimal?
    let activeCardCount: Int
    let unknownBalanceCount: Int
    let staleBalanceCount: Int

    init(cards: [VaultCard], now: Date = Date(), refreshAfterDays: Int = 7) {
        let activeCards = cards.filter { !$0.isArchived }
        activeCardCount = activeCards.count

        var knownTotal = Decimal.zero
        var knownCount = 0
        var staleCount = 0

        for card in activeCards {
            guard let balance = card.balance,
                  balance.isFinite,
                  balance >= 0,
                  let amount = Decimal(string: String(balance), locale: Locale(identifier: "en_US_POSIX")) else {
                continue
            }

            var roundedAmount = Decimal.zero
            var sourceAmount = amount
            NSDecimalRound(&roundedAmount, &sourceAmount, 2, .plain)
            knownTotal += roundedAmount
            knownCount += 1
            if card.balanceFreshness(at: now, refreshAfterDays: refreshAfterDays) == .needsRefresh {
                staleCount += 1
            }
        }

        total = activeCards.isEmpty || knownCount > 0 ? knownTotal : nil
        unknownBalanceCount = activeCardCount - knownCount
        staleBalanceCount = staleCount
    }

    var totalLabel: String {
        unknownBalanceCount > 0 ? "Known unused funds" : "Unused funds"
    }

    var totalText: String {
        total?.formatted(.currency(code: "USD")) ?? "Not checked yet"
    }

    var coverageText: String {
        guard activeCardCount > 0 else { return "No active cards" }

        let unknownText = unknownBalanceCount == 0 ? nil :
            "\(unknownBalanceCount) card\(unknownBalanceCount == 1 ? " needs" : "s need") a balance check"
        let staleText = staleBalanceCount == 0 ? nil :
            "\(staleBalanceCount) balance\(staleBalanceCount == 1 ? " needs" : "s need") refresh"

        switch (unknownText, staleText) {
        case let (unknown?, stale?): return "\(unknown) · \(stale)"
        case let (unknown?, nil): return unknown
        case let (nil, stale?): return stale
        case (nil, nil): return "All \(activeCardCount) balances checked recently"
        }
    }
}

struct VaultFundsSummaryView: View {
    let cards: [VaultCard]
    var now: Date = Date()
    var refreshAfterDays = 7

    private var summary: VaultFundsSummary {
        VaultFundsSummary(cards: cards, now: now, refreshAfterDays: refreshAfterDays)
    }

    var body: some View {
        VaultSurface(cornerRadius: 18, padding: 13) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.totalLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(summary.totalText)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("funds.total")
                }

                Spacer(minLength: 4)

                Text("Across \(summary.activeCardCount) active cards\n" + summary.coverageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150, alignment: .trailing)
                    .accessibilityIdentifier("funds.coverage")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("funds.summary")
        }
    }
}
