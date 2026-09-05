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
    @FocusState private var searchFocused: Bool
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

        ZStack {
            VaultBackground()
            VStack(spacing: 0) {
                searchControls
                List {
                    if entries.isEmpty {
                        emptyActivity
                    } else {
                        filteredSummary(total: filteredEntries.reduce(0) { $0 + $1.amount }, count: filteredEntries.count)

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
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $filterPresentation) { presentation in
            ActivityFilterSheet(
                cards: model.cards,
                initialConfiguration: presentation.configuration
            ) { updatedFilters in
                filters = updatedFilters
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.screen")
    }

    private var hasChanges: Bool {
        !searchText.isEmpty || filters.hasFilters || filters.sort != .newest
    }

    private func resetAll() {
        searchText = ""
        filters = ActivityFilterConfiguration()
        searchFocused = false
    }

    private var searchControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search merchants, cards, or last 4", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .accessibilityIdentifier("activity.search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("activity.search.clear")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(minHeight: 48)
            .vaultGlass(cornerRadius: 14)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    filterButton
                    Spacer(minLength: 0)
                    sortMenu
                }
                VStack(alignment: .leading, spacing: 4) {
                    filterButton
                    sortMenu
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hasChanges {
                HStack {
                    Text(filters.hasFilters || !searchText.isEmpty ? "Filtered activity" : "All activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset all", action: resetAll)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("activity.reset")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var filterButton: some View {
        Button {
            searchFocused = false
            filterPresentation = ActivityFilterPresentation(configuration: filters)
        } label: {
            Label(filters.activeControlCount == 0 ? "Filters" : "Filters (\(filters.activeControlCount))",
                  systemImage: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityIdentifier("activity.filters")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort activity", selection: $filters.sort) {
                ForEach(ActivitySortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Label("Sort: \(filters.sort.rawValue)", systemImage: "arrow.up.arrow.down")
                .font(.subheadline)
                .frame(minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityIdentifier("activity.sort")
    }

    private var dateScope: String {
        guard filters.dateRange == .custom else { return filters.dateRange.rawValue }
        let start = min(filters.startDate, filters.endDate).formatted(date: .abbreviated, time: .omitted)
        let end = max(filters.startDate, filters.endDate).formatted(date: .abbreviated, time: .omitted)
        return "\(start) – \(end)"
    }

    private func scopeChip(_ title: String, id: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 8) {
                Text(title).multilineTextAlignment(.leading)
                Image(systemName: "xmark.circle.fill")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(VaultTheme.electricBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(title)")
        .accessibilityIdentifier(id)
    }

    private func filteredSummary(total: Double, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(filters.selectedCardIDs.isEmpty ? "All cards" : "Selected cards") • \(dateScope)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("activity.scope")
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scopeChip("Search: “\(searchText)”", id: "activity.filter.remove.search") { searchText = "" }
            }
            if filters.dateRange != .all {
                scopeChip(dateScope, id: "activity.filter.remove.date") { filters.dateRange = .all }
            }
            ForEach(model.cards.filter { filters.selectedCardIDs.contains($0.id) }) { card in
                scopeChip("\(card.displayName) •••• \(card.last4)", id: "activity.filter.remove.card.\(card.id)") {
                    filters.selectedCardIDs.remove(card.id)
                }
            }
            HStack(spacing: 20) {
                summaryMetric(title: "Net amount", value: total.formatted(.currency(code: "USD")))
                Divider().frame(height: 36)
                summaryMetric(title: "Transactions", value: count.formatted())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .vaultGlass(cornerRadius: 18)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .contain)
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
                resetAll()
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
                    Button("Reset filters") {
                        let sort = configuration.sort
                        configuration = ActivityFilterConfiguration()
                        configuration.sort = sort
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("activity.filters.reset")
                }
            }
            .navigationTitle("Filters")
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
        .presentationDetents([.large])
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
