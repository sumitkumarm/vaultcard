import XCTest
@testable import VaultCard

final class VaultFundsSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testTotalAddsBalancesWithCentAccuracy() {
        let summary = VaultFundsSummary(cards: [
            card("1", balance: 1.10, fetchedAt: now),
            card("2", balance: 0.20, fetchedAt: now),
            card("3", balance: 0, fetchedAt: now)
        ], now: now)

        XCTAssertEqual(summary.total, Decimal(string: "1.30"))
        XCTAssertEqual(summary.unknownBalanceCount, 0)
        XCTAssertEqual(summary.totalText, "$1.30")
    }

    func testSummarySeparatesArchivedStaleAndUnknownBalances() {
        let staleDate = now.addingTimeInterval(-VaultCard.balanceFreshnessInterval - 1)
        let summary = VaultFundsSummary(cards: [
            card("fresh", balance: 8.25, fetchedAt: now),
            card("stale", balance: 3.50, fetchedAt: staleDate),
            card("zero", balance: 0, fetchedAt: now),
            card("unknown", balance: nil, fetchedAt: nil),
            card("archived", balance: 999, fetchedAt: now, archived: true)
        ], now: now)

        XCTAssertEqual(summary.total, Decimal(string: "11.75"))
        XCTAssertEqual(summary.activeCardCount, 4)
        XCTAssertEqual(summary.unknownBalanceCount, 1)
        XCTAssertEqual(summary.staleBalanceCount, 1)
        XCTAssertEqual(summary.totalLabel, "Known unused funds")
        XCTAssertEqual(summary.coverageText, "1 card needs a balance check · 1 balance needs refresh")
        let lenient = VaultFundsSummary(cards: [card("stale", balance: 3.50, fetchedAt: staleDate)], now: now, refreshAfterDays: 14)
        XCTAssertEqual(lenient.staleBalanceCount, 0)

        let allUnknown = VaultFundsSummary(cards: [card("unknown", balance: nil, fetchedAt: nil)], now: now)
        XCTAssertNil(allUnknown.total)
        XCTAssertEqual(allUnknown.totalText, "Not checked yet")
    }

    private func card(
        _ id: String,
        balance: Double?,
        fetchedAt: Date?,
        archived: Bool = false
    ) -> VaultCard {
        VaultCard(
            id: id,
            nickname: nil,
            network: .visa,
            last4: "1111",
            expiry: "09/29",
            balance: balance,
            transactions: [],
            lastFetchedAt: fetchedAt,
            fetchFailureCount: 0,
            addedAt: Date(timeIntervalSince1970: 0),
            refreshBlockedUntil: nil,
            credentialVersion: 1,
            archivedAt: archived ? now : nil
        )
    }
}
