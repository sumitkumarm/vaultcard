import SwiftUI

private enum ActivitySortOption: String, CaseIterable, Identifiable {
    case newest = "Newest first"
    case oldest = "Oldest first"
    case highestAmount = "Highest amount"
    case lowestAmount = "Lowest amount"

    var id: String { rawValue }
}

private enum ActivityDateRange: String, CaseIterable, Identifiable {
    case all = "All time"
    case last30Days = "Last 30 days"
    case last90Days = "Last 90 days"
    case custom = "Custom range"

    var id: String { rawValue }
}

private struct ActivityFilterConfiguration {
    var sort = ActivitySortOption.newest
    var dateRange = ActivityDateRange.all
    var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    var endDate = Date()
    var selectedCardIDs = Set<String>()

    var hasFilters: Bool {
        dateRange != .all || !selectedCardIDs.isEmpty
    }

    var activeControlCount: Int {
        (dateRange == .all ? 0 : 1)
            + (selectedCardIDs.isEmpty ? 0 : 1)
            + (sort == .newest ? 0 : 1)
    }
}

private struct ActivityFilterPresentation: Identifiable {
    let id = UUID()
    let configuration: ActivityFilterConfiguration
}

private struct ActivityEntry: Identifiable {
    let id: String
    let cardID: String
    let cardName: String
    let last4: String
    let network: CardNetwork
    let isArchived: Bool
    let date: Date
    let description: String
    let amount: Double

    init(card: VaultCard, transaction: CardTransaction) {
        id = "\(card.id):\(transaction.id)"
        cardID = card.id
        let nickname = card.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        cardName = nickname?.isEmpty == false ? nickname! : card.network.displayName.capitalized
        last4 = card.last4
        network = card.network
        isArchived = card.isArchived
        date = transaction.date
        description = transaction.description
        amount = transaction.amount
    }
}

struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var filters = ActivityFilterConfiguration()
    @State private var filterPresentation: ActivityFilterPresentation?

    private var allEntries: [ActivityEntry] {
        model.cards.flatMap { card in
            card.transactions.map { ActivityEntry(card: card, transaction: $0) }
        }
    }

    private func visibleEntries(from entries: [ActivityEntry], query: String) -> [ActivityEntry] {
        let calendar = Calendar.current
        let now = Date()
        let lowerBound: Date?
        let upperBound: Date?

        switch filters.dateRange {
        case .all:
            lowerBound = nil
            upperBound = nil
        case .last30Days:
            lowerBound = calendar.date(byAdding: .day, value: -30, to: now)
            upperBound = nil
        case .last90Days:
            lowerBound = calendar.date(byAdding: .day, value: -90, to: now)
            upperBound = nil
        case .custom:
            lowerBound = calendar.startOfDay(for: min(filters.startDate, filters.endDate))
            upperBound = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: max(filters.startDate, filters.endDate))
            )
        }

        let selectedCardIDs = filters.selectedCardIDs
        let filtered = entries.filter { entry in
            if !selectedCardIDs.isEmpty && !selectedCardIDs.contains(entry.cardID) {
                return false
            }
            if let lowerBound, entry.date < lowerBound {
                return false
            }
            if let upperBound, entry.date >= upperBound {
                return false
            }
            return query.isEmpty
                || entry.description.localizedCaseInsensitiveContains(query)
                || entry.cardName.localizedCaseInsensitiveContains(query)
                || entry.last4.contains(query)
        }

        return filtered.sorted { lhs, rhs in
            switch filters.sort {
            case .newest:
                if lhs.date != rhs.date { return lhs.date > rhs.date }
            case .oldest:
                if lhs.date != rhs.date { return lhs.date < rhs.date }
            case .highestAmount:
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            case .lowestAmount:
                if lhs.amount != rhs.amount { return lhs.amount < rhs.amount }
            }
            return lhs.id < rhs.id
        }
    }

    var body: some View {
        let entries = allEntries
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredEntries = entries.isEmpty ? [] : visibleEntries(from: entries, query: query)
        let refined = filters.hasFilters || !query.isEmpty

        ZStack {
            VaultBackground()
            List {
                if entries.isEmpty {
                    emptyActivity
                } else {
                    if refined {
                        filteredSummary(total: filteredEntries.reduce(0) { $0 + $1.amount }, count: filteredEntries.count)
                    }

                    if filteredEntries.isEmpty {
                        noResults
                    } else {
                        Section {
                            ForEach(filteredEntries) { entry in
                                Button {
                                    model.routePath.append(.detail(entry.cardID))
                                } label: {
                                    ActivityTransactionRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .accessibilityIdentifier("activity.transaction.\(entry.id)")
                                .accessibilityHint("Open \(entry.cardName)")
                            }
                        } header: {
                            Text("\(filteredEntries.count) transaction\(filteredEntries.count == 1 ? "" : "s")")
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .vaultFloatingBarScrollClearance()
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search merchants or cards")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    filterPresentation = ActivityFilterPresentation(configuration: filters)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease")
                        if filters.activeControlCount > 0 {
                            Circle()
                                .fill(VaultTheme.electricBlue)
                                .frame(width: 8, height: 8)
                                .offset(x: 5, y: -4)
                        }
                    }
                }
                .accessibilityIdentifier("activity.filters")
                .accessibilityLabel("Sort and filter")
                .accessibilityValue(
                    filters.activeControlCount == 0
                        ? "Default"
                        : "\(filters.activeControlCount) option\(filters.activeControlCount == 1 ? "" : "s") changed"
                )
            }
        }
        .sheet(item: $filterPresentation) { presentation in
            ActivityFilterSheet(
                cards: model.cards,
                initialConfiguration: presentation.configuration
            ) { updatedFilters in
                filters = updatedFilters
            }
        }
        .accessibilityIdentifier("activity.screen")
    }

    private func filteredSummary(total: Double, count: Int) -> some View {
        HStack(spacing: 20) {
            summaryMetric(
                title: "Net amount",
                value: total.formatted(.currency(code: "USD"))
            )
            Divider()
                .frame(height: 36)
            summaryMetric(
                title: "Transactions",
                value: count.formatted()
            )
        }
        .padding(16)
        .vaultGlass(cornerRadius: 18)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activity.summary")
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyActivity: some View {
        ContentUnavailableView {
            Label("No activity yet", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("Refresh a card balance to bring its available transactions into one private view.")
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("activity.empty")
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label("No matching transactions", systemImage: "magnifyingglass")
        } description: {
            Text("Try another merchant, card, or filter.")
        } actions: {
            Button("Clear search and filters") {
                searchText = ""
                filters = ActivityFilterConfiguration()
            }
            .vaultPrimaryButton()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("activity.no-results")
    }
}

private struct ActivityTransactionRow: View {
    let entry: ActivityEntry

    var body: some View {
        VaultSurface(padding: 12) {
            HStack(spacing: 12) {
                VaultRowIcon(symbol: "bag.fill")
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.description)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(entry.cardName)
                            .lineLimit(1)
                        Text("•••• \(entry.last4)")
                            .fontDesign(.monospaced)
                        if entry.isArchived {
                            Image(systemName: "archivebox.fill")
                                .accessibilityLabel("Archived card")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(entry.date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.amount.formatted(.currency(code: "USD")))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.description), \(entry.amount.formatted(.currency(code: "USD"))), "
                + "\(entry.cardName) ending \(entry.last4), "
                + entry.date.formatted(date: .complete, time: .shortened)
        )
    }
}

private struct ActivityFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let cards: [VaultCard]
    let onApply: (ActivityFilterConfiguration) -> Void
    @State private var configuration: ActivityFilterConfiguration

    init(
        cards: [VaultCard],
        initialConfiguration: ActivityFilterConfiguration,
        onApply: @escaping (ActivityFilterConfiguration) -> Void
    ) {
        self.cards = cards
        self.onApply = onApply
        _configuration = State(initialValue: initialConfiguration)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort by") {
                    Picker("Order", selection: $configuration.sort) {
                        ForEach(ActivitySortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Date range") {
                    Picker("Range", selection: $configuration.dateRange) {
                        ForEach(ActivityDateRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    if configuration.dateRange == .custom {
                        DatePicker("From", selection: $configuration.startDate, displayedComponents: .date)
                        DatePicker("Through", selection: $configuration.endDate, displayedComponents: .date)
                    }
                }

                Section("Cards") {
                    Button {
                        configuration.selectedCardIDs.removeAll()
                    } label: {
                        selectionRow(
                            title: "All cards",
                            subtitle: "\(cards.count) card\(cards.count == 1 ? "" : "s")",
                            isSelected: configuration.selectedCardIDs.isEmpty
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("activity.filter.cards.all")

                    ForEach(cards) { card in
                        Button {
                            toggleCard(card.id)
                        } label: {
                            selectionRow(
                                title: card.displayName,
                                subtitle: "•••• \(card.last4)\(card.isArchived ? " • Archived" : "")",
                                isSelected: configuration.selectedCardIDs.contains(card.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("activity.filter.card.\(card.id)")
                    }
                }

                Section {
                    Button("Reset sort and filters") {
                        configuration = ActivityFilterConfiguration()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("activity.filters.reset")
                }
            }
            .navigationTitle("Sort & Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(configuration)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("activity.filters.apply")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func selectionRow(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(VaultTheme.electricBlue)
            }
        }
        .contentShape(Rectangle())
    }

    private func toggleCard(_ cardID: String) {
        if configuration.selectedCardIDs.contains(cardID) {
            configuration.selectedCardIDs.remove(cardID)
        } else {
            configuration.selectedCardIDs.insert(cardID)
        }
    }
}
