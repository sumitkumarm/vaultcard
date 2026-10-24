import SwiftUI

struct BulkCardSaveError: LocalizedError {
    let savedIDs: [String]
    let underlying: Error
    var errorDescription: String? {
        if savedIDs.isEmpty { return underlying.localizedDescription }
        return "Saved \(savedIDs.count) card(s). The remaining cards could not be saved: \(underlying.localizedDescription) You can retry the remaining rows."
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
