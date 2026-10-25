import SwiftUI

struct BulkCardSaveError: LocalizedError {
    let savedIDs: [String]
    let underlying: Error
    var savedRowIDs: Set<UUID> = []
    var duplicateRowIDs: Set<UUID> = []
    var errorDescription: String? {
        if savedIDs.isEmpty { return underlying.localizedDescription }
        return "Saved \(savedIDs.count) card(s). The remaining cards could not be saved: \(underlying.localizedDescription) You can retry the remaining rows."
    }
}

struct BulkCardSaveResult {
    var savedRowIDs: Set<UUID> = []
    var savedCardIDs: [String] = []
    var duplicateRowIDs: Set<UUID> = []
    var pendingRowIDs: Set<UUID> = []
}

enum BulkCardReviewStatus: Equatable {
    case ready
    case existing
    case duplicate
    case needsReview(String)

    var canSave: Bool { self == .ready }
    var message: String? {
        switch self {
        case .ready: nil
        case .existing: "Already in vault"
        case .duplicate: "Repeated in this import"
        case .needsReview(let reason): reason
        }
    }
}

enum BulkCardReview {
    static func canConfirmNumber(_ number: String) -> Bool {
        let digits = CardRules.digitsOnly(number)
        return (12...19).contains(digits.count) && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func status(for row: BulkCardRow, existingNumbers: Set<String>, precedingNumbers: Set<String>) -> BulkCardReviewStatus {
        let number = CardRules.digitsOnly(row.cardNumber)
        if !number.isEmpty, existingNumbers.contains(number) { return .existing }
        if !number.isEmpty, precedingNumbers.contains(number) { return .duplicate }
        if !CardRules.isValidCardNumber(number) && !(row.numberConfirmed && canConfirmNumber(number)) {
            return .needsReview("Check card number")
        }
        guard CardRules.validateExpiry(row.expiry) else { return .needsReview("Check expiry") }
        let code = CardRules.digitsOnly(row.code)
        if !code.isEmpty {
            if row.codeIsPIN {
                guard code.count == 4 else { return .needsReview("Check PIN") }
            } else if !CardRules.validateCVV(code) { return .needsReview("Check CVV") }
        }
        return .ready
    }
}

struct BulkCardEntryButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.routePath.append(.bulkCapture) } label: {
            Label("Add Multiple Cards", systemImage: "rectangle.stack.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("add.bulk")
    }
}

struct AddMissingCVVView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cardID: String
    var onSaved: () -> Void
    @State private var cvv = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("CVV", text: $cvv)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("missingCVV.value")
                } footer: {
                    Text("Enter the security code printed on your card. Your saved PIN is kept separately.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button(isSaving ? "Saving…" : "Save CVV") {
                    isSaving = true
                    Task {
                        defer { isSaving = false }
                        do {
                            try await model.saveCVV(cvv, cardID: cardID)
                            onSaved()
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(isSaving || !CardRules.validateCVV(cvv))
                .accessibilityIdentifier("missingCVV.save")
            }
            .navigationTitle("Add CVV")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
