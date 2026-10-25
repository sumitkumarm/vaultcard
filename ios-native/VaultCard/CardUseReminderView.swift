import SwiftUI

struct LowBalanceCardPanel: View {
    let card: VaultCard
    let reminder: CardUseReminder?
    let onRemind: () -> Void
    let onCancel: () -> Void

    private var snapshotDate: Date? { reminder?.lastCheckedAt ?? card.lastFetchedAt }

    @ViewBuilder
    var body: some View {
        if !card.isArchived,
           let balance = card.balance,
           balance.isFinite,
           balance > 0,
           balance < 10 {
            VaultSurface(cornerRadius: 18, padding: 13) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use the remaining \(balance.currencyText)")
                        .font(.headline)

                    if let snapshotDate {
                        Text("Last checked \(CardRowTimestamp.string(date: snapshotDate)). Saved balance may have changed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Balance has not been checked yet. Saved balance may have changed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let reminder {
                        if reminder.fireDate > Date() {
                            HStack(spacing: 12) {
                                Text("Reminder: \(CardRowTimestamp.string(date: reminder.fireDate))")
                                    .font(.subheadline.weight(.medium))
                                    .accessibilityIdentifier("reminder.date")
                                Spacer(minLength: 4)
                                Button("Edit", action: onRemind)
                                    .accessibilityIdentifier("reminder.open")
                                Button("Cancel", action: onCancel)
                                    .accessibilityIdentifier("reminder.cancel")
                            }
                        } else {
                            Text("Reminder date passed")
                                .font(.subheadline.weight(.medium))
                            HStack {
                                Button("Remind me again", action: onRemind)
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("reminder.open")
                                Spacer()
                                Button("Dismiss", action: onCancel)
                                    .accessibilityIdentifier("reminder.cancel")
                            }
                        }
                    } else {
                        Button("Remind me to use this", action: onRemind)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("reminder.open")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct CardUseReminderView: View {
    @Environment(\.dismiss) private var dismiss
    let card: VaultCard
    let reminder: CardUseReminder?
    let onSave: (Date) async throws -> Void

    @State private var fireDate: Date
    @State private var isSaving = false
    @State private var errorText: String?

    init(
        card: VaultCard,
        reminder: CardUseReminder? = nil,
        onSave: @escaping (Date) async throws -> Void
    ) {
        self.card = card
        self.reminder = reminder
        self.onSave = onSave
        let initialDate = reminder.flatMap { $0.fireDate > Date() ? $0.fireDate : nil } ?? Self.tomorrowAtNine()
        _fireDate = State(initialValue: initialDate)
    }

    private var snapshotBalance: Double? { reminder?.balance ?? card.balance }
    private var snapshotDate: Date? { reminder?.lastCheckedAt ?? card.lastFetchedAt }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card") {
                    LabeledContent("Card", value: card.displayName)
                    LabeledContent("Balance snapshot", value: snapshotBalance?.currencyText ?? "Not checked")
                    LabeledContent("Last checked", value: snapshotDate.map { CardRowTimestamp.string(date: $0) } ?? "Not available")
                    Text("This is the last saved balance. It may have changed since it was checked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Reminder") {
                    DatePicker(
                        "Date and time",
                        selection: $fireDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("reminder.date")
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("reminder.error")
                    }
                }

                Section {
                    Button {
                        saveReminder()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(reminder == nil ? "Set Reminder" : "Save Reminder")
                            Spacer()
                        }
                    }
                    .disabled(isSaving || fireDate <= Date())
                    .accessibilityIdentifier("reminder.save")
                }
            }
            .navigationTitle(reminder == nil ? "Set Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("reminder.sheet.cancel")
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func saveReminder() {
        guard fireDate > Date() else {
            errorText = "Choose a future date and time."
            return
        }

        errorText = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await onSave(fireDate)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private static func tomorrowAtNine() -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(24 * 60 * 60)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

private extension Double {
    var currencyText: String { formatted(.currency(code: "USD")) }
}
