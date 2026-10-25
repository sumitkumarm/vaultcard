import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BulkCardCaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var rows: [BulkCardRow] = []
    @State private var existingNumbers: Set<String> = []
    @State private var existingNumberLookupError: String?
    @State private var isLoadingExistingNumbers = false
    @State private var didAttemptExistingNumberLookup = false
    @State private var editingRow: BulkCardRow?
    @State private var isCameraPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var isRecognizing = false
    @State private var isSaving = false
    @State private var isPrivacyShieldVisible = false
    @State private var showError = false
    @State private var showCameraMessage = false
    @State private var showSaveSummary = false
    @State private var saveSummaryTitle = ""
    @State private var saveSummaryMessage = ""
    @State private var shouldLeaveAfterSaveSummary = false
    @State private var errorMessage = ""
    @State private var cameraMessage = ""
    @State private var pastedText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var recognitionTask: Task<Void, Never>?
    @State private var didLoadUITestFixture = false

    private let importTypes: [UTType] = [.image, .commaSeparatedText, .tabSeparatedText, .plainText]

    private var reviewedRows: [(row: BulkCardRow, status: BulkCardReviewStatus)] {
        var precedingNumbers = Set<String>()
        return rows.map { row in
            let status = BulkCardReview.status(
                for: row,
                existingNumbers: existingNumbers,
                precedingNumbers: precedingNumbers
            )
            let number = CardRules.digitsOnly(row.cardNumber)
            if status == .ready, !number.isEmpty { precedingNumbers.insert(number) }
            return (row: row, status: status)
        }
    }

    private var eligibleCount: Int { reviewedRows.filter { $0.status.canSave }.count }
    private var existingCount: Int { reviewedRows.filter { $0.status == .existing }.count }
    private var duplicateCount: Int { reviewedRows.filter { $0.status == .duplicate }.count }
    private var needsReviewCount: Int {
        reviewedRows.filter {
            if case .needsReview = $0.status { return true }
            return false
        }.count
    }

    var body: some View {
        ZStack {
            VaultBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if rows.isEmpty {
                        introduction
                        captureOptions
                        pasteDisclosure
                    } else {
                        Text("Check the captured details, then add all cards in one tap.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if isRecognizing {
                        VaultSurface(padding: 14) {
                            HStack(spacing: 12) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Reading card details…")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Images are processed on this device.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .accessibilityIdentifier("bulk.recognition.progress")
                    }

                    if !rows.isEmpty {
                        reviewSection
                    }
                    if !rows.isEmpty {
                        DisclosureGroup("Add another image or file") {
                            captureOptions
                            pasteDisclosure
                        }
                    }

                    Label("Your card details stay on this device. Review every row before adding.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                        .accessibilityIdentifier("bulk.privacy.footer")
                }
                .padding(20)
            }
            .accessibilityIdentifier("bulk.scroll")
            .scrollBounceBehavior(.basedOnSize)

            if isPrivacyShieldVisible {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.largeTitle)
                                .foregroundStyle(VaultTheme.electricBlue)
                            Text("VaultCard is locked")
                                .font(.headline)
                        }
                    }
                    .ignoresSafeArea()
                    .accessibilityIdentifier("bulk.privacyShield")
            }
        }
        .navigationTitle("Add Multiple Cards")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotos,
            maxSelectionCount: 20,
            matching: .images
        )
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .sheet(isPresented: $isCameraPresented) {
            BulkCameraPicker(
                onImage: { image in
                    isCameraPresented = false
                    recognize(images: [image])
                },
                onCancel: { isCameraPresented = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $editingRow) { row in
            BulkCardEditSheet(
                row: binding(for: row),
                onDelete: { removeRow(withID: row.id) }
            )
        }
        .alert("Bulk capture", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Camera unavailable", isPresented: $showCameraMessage) {
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied
                || AVCaptureDevice.authorizationStatus(for: .video) == .restricted {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(cameraMessage)
        }
        .alert(saveSummaryTitle, isPresented: $showSaveSummary) {
            Button("OK") {
                if shouldLeaveAfterSaveSummary { model.routePath = [] }
            }
        } message: {
            Text(saveSummaryMessage)
                .accessibilityIdentifier("bulk.save.summary")
        }
        .onChange(of: selectedPhotos) { _, newItems in
            importPhotos(newItems)
        }
        .onChange(of: scenePhase) { _, phase in
            isPrivacyShieldVisible = phase != .active
            if phase != .active {
                recognitionTask?.cancel()
            }
        }
        .onAppear {
            isPrivacyShieldVisible = scenePhase != .active
            loadUITestFixtureIfNeeded()
            if !didAttemptExistingNumberLookup { loadExistingNumbers() }
        }
        .onDisappear {
            recognitionTask?.cancel()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capture or import card details")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("Take a photo or import a spreadsheet with card numbers, expiry dates, and optional CVV/PIN. Extra columns are ignored.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureOptions: some View {
        VaultSurface(padding: 8) {
            VStack(spacing: 0) {
                captureButton(
                    title: "Take a Photo",
                    subtitle: "Photograph the whole card grid",
                    symbol: "camera.fill",
                    identifier: "bulk.capture.camera",
                    action: requestCamera
                )
                Divider().padding(.leading, 58)
                captureButton(
                    title: "Choose Photos",
                    subtitle: "Select photos of your card details",
                    symbol: "photo.on.rectangle.angled",
                    identifier: "bulk.capture.photos"
                ) {
                    isPhotoPickerPresented = true
                }
                Divider().padding(.leading, 58)
                captureButton(
                    title: "Import Files",
                    subtitle: "Images, CSV, TSV, or plain text",
                    symbol: "doc.badge.plus",
                    identifier: "bulk.capture.files"
                ) {
                    isFileImporterPresented = true
                }
            }
        }
    }

    private func captureButton(
        title: String,
        subtitle: String,
        symbol: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VaultTheme.electricBlue)
                    .frame(width: 34, height: 34)
                    .background(VaultTheme.electricBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var pasteDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste rows copied from a spreadsheet or a text list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $pastedText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 105)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .background(VaultTheme.electricBlue.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("bulk.paste.text")
                Button {
                    appendParsedText(pastedText)
                } label: {
                    Label("Preview pasted cards", systemImage: "text.insert")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("bulk.paste.preview")
            }
            .padding(.top, 12)
        } label: {
            Label("Paste a spreadsheet grid", systemImage: "clipboard")
                .font(.subheadline.weight(.semibold))
        }
        .tint(VaultTheme.electricBlue)
        .padding(15)
        .background(VaultTheme.electricBlue.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VaultTheme.border(for: .light), lineWidth: 1)
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("Review cards")
                    .font(.headline)
                Spacer()
                Text("\(rows.count) \(rows.count == 1 ? "card" : "cards")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("bulk.review.count")
            }

            if let existingNumberLookupError {
                VaultSurface(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Couldn’t check for cards already in your vault", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(VaultTheme.danger)
                        Text(existingNumberLookupError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            loadExistingNumbers()
                        } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingExistingNumbers)
                        .accessibilityIdentifier("bulk.existing.retry")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("bulk.existing.error")
            }

            if reviewedRows.contains(where: { $0.status != .existing && $0.status != .duplicate && $0.row.input.cvv.isEmpty }) {
                Label("Some cards have no CVV. Add CVV later from the card to manage it.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(VaultTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bulk.missingCVV.warning")
            }

            ForEach(rows) { row in
                compactReviewRow(row)
            }

            if !rows.isEmpty {
                HStack(spacing: 8) {
                    reviewCount("\(eligibleCount) ready", color: VaultTheme.success)
                    reviewCount("\(existingCount) existing", color: .secondary)
                    reviewCount("\(duplicateCount) repeated", color: VaultTheme.warning)
                    reviewCount("\(needsReviewCount) review", color: VaultTheme.danger)
                }
                .font(.caption2.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("bulk.review.summary")
            }

            Button {
                saveCards()
            } label: {
                HStack(spacing: 8) {
                    if isSaving || isLoadingExistingNumbers { ProgressView().tint(.white) }
                    Text(isSaving ? "Adding Cards…" : "Confirm & Add \(eligibleCount) \(eligibleCount == 1 ? "Card" : "Cards")")
                }
                .frame(maxWidth: .infinity)
            }
            .font(.headline)
            .controlSize(.large)
            .vaultPrimaryButton()
            .disabled(rows.isEmpty || eligibleCount == 0 || existingNumberLookupError != nil || isLoadingExistingNumbers || isSaving || isRecognizing)
            .opacity(rows.isEmpty || eligibleCount == 0 || existingNumberLookupError != nil ? 0.55 : 1)
            .accessibilityIdentifier("bulk.confirm")
        }
    }

    // Editors can finish an update while a row is removed or the review closes.
    // Resolve by identity so those updates never address a deleted array index.
    private func binding(for row: BulkCardRow) -> Binding<BulkCardRow> {
        Binding(
            get: { rows.first { $0.id == row.id } ?? row },
            set: { updated in
                if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = updated }
            }
        )
    }

    private func compactReviewRow(_ row: BulkCardRow) -> some View {
        let status = reviewStatus(for: row)
        let digits = CardRules.digitsOnly(row.cardNumber)
        let invalidNumber = !CardRules.isValidCardNumber(row.cardNumber)
        let rowStatusColor = invalidNumber ? VaultTheme.warning : reviewColor(for: status)
        let badge = invalidNumber && row.numberConfirmed && status == .ready ? "Checked" : reviewBadge(for: status)
        return VaultSurface(padding: 7) {
            HStack(spacing: 8) {
                VaultNetworkRowIcon(network: CardRules.inferNetwork(row.cardNumber))
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(digits.isEmpty ? "No number" : digits)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("bulk.row.\(row.sourceRow).number.value")
                    HStack(spacing: 9) {
                        Text(row.expiry.isEmpty ? "—/——" : row.expiry)
                            .accessibilityIdentifier("bulk.row.\(row.sourceRow).expiry.value")
                        Text("\(row.codeIsPIN ? "PIN" : "CVV") \(row.code.isEmpty ? "—" : row.code)")
                            .accessibilityLabel("\(row.codeIsPIN ? "PIN" : "CVV") \(row.code.isEmpty ? "missing" : row.code)")
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(badge)
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .foregroundStyle(rowStatusColor)
                        .background(rowStatusColor.opacity(0.11), in: Capsule())
                        .accessibilityLabel(status.message ?? (invalidNumber ? "Number checked; ready to add" : "Ready to add"))
                    Button {
                        editingRow = row
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VaultTheme.electricBlue)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit card ending in \(digits.suffix(4))")
                    .accessibilityIdentifier("bulk.edit.\(row.sourceRow)")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(invalidNumber ? VaultTheme.warning : VaultTheme.border(for: .light), lineWidth: invalidNumber ? 1.5 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bulk.row.\(row.sourceRow)")
    }

    private func reviewCount(_ title: String, color: Color) -> some View {
        Text(title)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func reviewBadge(for status: BulkCardReviewStatus) -> String {
        switch status {
        case .ready: "Ready"
        case .existing: "In vault"
        case .duplicate: "Repeat"
        case .needsReview: "Review"
        }
    }

    private func reviewColor(for status: BulkCardReviewStatus) -> Color {
        switch status {
        case .ready: VaultTheme.success
        case .existing: VaultTheme.electricBlue
        case .duplicate: VaultTheme.warning
        case .needsReview: VaultTheme.danger
        }
    }

    private func reviewStatus(for row: BulkCardRow) -> BulkCardReviewStatus {
        reviewedRows.first { $0.row.id == row.id }?.status ?? .needsReview("Check card details")
    }

    private func saveCards() {
        guard !rows.isEmpty, existingNumberLookupError == nil, !isLoadingExistingNumbers else { return }
        isSaving = true
        defer { isSaving = false }
        guard eligibleCount > 0 else { return }
        do {
            let result = try model.saveBulkRows(rows)
            let removedIDs = result.savedRowIDs.union(result.duplicateRowIDs)
            rows.removeAll { removedIDs.contains($0.id) }
            let refreshError = refreshExistingNumbers()
            presentSaveSummary(
                added: result.savedRowIDs.count,
                skipped: result.duplicateRowIDs.count,
                refreshError: refreshError
            )
        } catch let partial as BulkCardSaveError {
            let removedIDs = partial.savedRowIDs.union(partial.duplicateRowIDs)
            rows.removeAll { removedIDs.contains($0.id) }
            let refreshError = refreshExistingNumbers()
            presentSaveSummary(
                added: partial.savedRowIDs.count,
                skipped: partial.duplicateRowIDs.count,
                detail: partial.localizedDescription,
                refreshError: refreshError
            )
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func loadExistingNumbers() {
        guard !isLoadingExistingNumbers else { return }
        didAttemptExistingNumberLookup = true
        isLoadingExistingNumbers = true
        defer { isLoadingExistingNumbers = false }
        do {
            existingNumbers = try model.bulkExistingCardNumbers()
            existingNumberLookupError = nil
        } catch {
            existingNumberLookupError = error.localizedDescription
        }
    }

    private func refreshExistingNumbers() -> String? {
        do {
            existingNumbers = try model.bulkExistingCardNumbers()
            existingNumberLookupError = nil
            return nil
        } catch {
            existingNumberLookupError = error.localizedDescription
            return "Couldn’t refresh the vault check: \(error.localizedDescription)"
        }
    }

    private func presentSaveSummary(
        added: Int,
        skipped: Int,
        detail: String? = nil,
        refreshError: String? = nil
    ) {
        shouldLeaveAfterSaveSummary = rows.isEmpty
        saveSummaryTitle = rows.isEmpty ? "Bulk capture complete" : "Cards added; review remains"
        var message = "Added \(added) cards; skipped \(skipped) existing or repeated cards."
        if needsReviewCount > 0 {
            message += " \(needsReviewCount) \(needsReviewCount == 1 ? "card needs" : "cards need") review."
        }
        if existingCount + duplicateCount > 0 {
            message += " Existing and repeated rows remain marked as skipped."
        }
        if let detail { message += "\n\(detail)" }
        if let refreshError { message += "\n\(refreshError)" }
        saveSummaryMessage = message
        showSaveSummary = true
    }

    private func removeRow(withID id: UUID) {
        rows.removeAll { $0.id == id }
        if editingRow?.id == id { editingRow = nil }
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraMessage = "This device has no camera. Choose Photos or Files to import card details."
            showCameraMessage = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    isCameraPresented = true
                } else {
                    cameraMessage = "Allow camera access in Settings to take a photo, or choose Photos or Files instead."
                    showCameraMessage = true
                }
            }
        case .denied, .restricted:
            cameraMessage = "Allow camera access in Settings to take a photo, or choose Photos or Files instead."
            showCameraMessage = true
        @unknown default:
            cameraMessage = "Camera access is unavailable. Choose Photos or Files to import card details."
            showCameraMessage = true
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        recognitionTask?.cancel()
        recognitionTask = Task { @MainActor in
            isRecognizing = true
            defer {
                isRecognizing = false
                selectedPhotos = []
            }
            var images: [UIImage] = []
            for item in items {
                guard !Task.isCancelled else { return }
                do {
                    if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        images.append(image)
                    } else {
                        presentError("A selected photo could not be opened. Try downloading it to this device first.")
                    }
                } catch {
                    presentError("A selected photo could not be opened. Try importing it again.")
                }
            }
            await appendRecognized(images)
        }
    }

    private func recognize(images: [UIImage]) {
        guard !images.isEmpty else { return }
        recognitionTask?.cancel()
        recognitionTask = Task { @MainActor in
            isRecognizing = true
            defer { isRecognizing = false }
            await appendRecognized(images)
        }
    }

    @MainActor
    private func appendRecognized(_ images: [UIImage]) async {
        var foundRows: [BulkCardRow] = []
        var failedCount = 0
        for image in images {
            guard !Task.isCancelled else { return }
            do {
                foundRows.append(contentsOf: try await BulkCardParser.recognize(image))
            } catch {
                failedCount += 1
            }
        }
        guard !Task.isCancelled else { return }
        rows.append(contentsOf: foundRows)
        if foundRows.isEmpty {
            presentError(failedCount > 0
                ? "The image could not be read. Try a clearer photo or import a text file."
                : "No card details were found. You can edit rows after pasting a spreadsheet grid.")
        } else if failedCount > 0 {
            presentError("Some images could not be read. Review the cards that were detected and import the others again.")
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            presentError("The selected files could not be opened. Choose another image or text export.")
        case .success(let urls):
            var images: [UIImage] = []
            var fileError = false
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
                   let image = UIImage(contentsOfFile: url.path) {
                    images.append(image)
                } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                    appendParsedText(text)
                } else {
                    fileError = true
                }
            }
            if !images.isEmpty { recognize(images: images) }
            if fileError {
                presentError("One or more files could not be read. Supported files include images, CSV, TSV, and plain text.")
            }
        }
    }

    private func appendParsedText(_ text: String) {
        let parsed = BulkCardParser.parse(text)
        guard !parsed.isEmpty else {
            presentError("No card rows were found. Include a card number and expiry on each line.")
            return
        }
        rows.append(contentsOf: parsed)
        pastedText = ""
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func loadUITestFixtureIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !didLoadUITestFixture,
              arguments.contains("--ui-testing-bulk") || arguments.contains("--ui-testing-bulk-mixed") else { return }
        didLoadUITestFixture = true
        if arguments.contains("--ui-testing-bulk-mixed") {
            rows = BulkCardParser.parse("4111111111111111,May 26,123\n5555555555554444,August 2028,\n4000000000000002,June 2028,321\n4000000000000003,July 2028,123\n4000000000000002,June 2028,321")
        } else {
            rows = BulkCardParser.parse("4111111111111111,May 26,123\n5555555555554444,August 2028,")
        }
    }
}

private struct BulkCardEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Binding var row: BulkCardRow
    let onDelete: () -> Void

    private var issue: String? {
        guard CardRules.isValidCardNumber(row.cardNumber)
                || (row.numberConfirmed && BulkCardReview.canConfirmNumber(row.cardNumber)) else {
            return "Check the card number before adding it."
        }
        guard CardRules.validateExpiry(row.expiry) else { return "Enter expiry as MM/YY." }
        let code = CardRules.digitsOnly(row.code)
        if !code.isEmpty {
            if row.codeIsPIN {
                guard code.count == 4 else { return "A PIN should contain 4 digits." }
            } else if !CardRules.validateCVV(code) {
                return "A CVV should contain 3 or 4 digits."
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card number") {
                    TextField("Card number", text: $row.cardNumber)
                        .keyboardType(.numberPad)
                        .textContentType(.creditCardNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospacedDigit())
                        .accessibilityIdentifier("bulk.row.\(row.sourceRow).number")
                        .onChange(of: row.cardNumber) { _, newValue in
                            let digits = CardRules.digitsOnly(newValue)
                            let limited = String(digits.prefix(19))
                            if limited != newValue { row.cardNumber = limited }
                            row.numberConfirmed = false
                        }

                    if !CardRules.isValidCardNumber(row.cardNumber),
                       BulkCardReview.canConfirmNumber(row.cardNumber) {
                        Toggle("I checked this card number", isOn: $row.numberConfirmed)
                            .accessibilityIdentifier("bulk.row.\(row.sourceRow).confirmNumber")
                    }
                }

                Section("Expiry and security code") {
                    TextField("Expiry (MM/YY)", text: $row.expiry)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                        .font(.body.monospacedDigit())
                        .accessibilityIdentifier("bulk.row.\(row.sourceRow).expiry")
                        .onChange(of: row.expiry) { _, newValue in
                            row.expiry = CardRules.formatExpiryInput(newValue)
                        }

                    TextField(row.codeIsPIN ? "Optional PIN" : "Optional CVV", text: $row.code)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                        .font(.body.monospacedDigit())
                        .accessibilityIdentifier("bulk.row.\(row.sourceRow).code")
                        .onChange(of: row.code) { _, newValue in
                            row.code = String(CardRules.digitsOnly(newValue).prefix(4))
                        }

                    Toggle("This security code is a PIN", isOn: $row.codeIsPIN)
                        .tint(VaultTheme.electricBlue)
                }

                if let issue {
                    Section {
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(VaultTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("bulk.row.\(row.sourceRow).issue")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete card", systemImage: "trash")
                    }
                    .accessibilityIdentifier("bulk.remove.\(row.sourceRow)")
                }
            }
            .navigationTitle("Edit card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .overlay {
            if scenePhase != .active {
                Color(uiColor: .systemBackground)
                    .overlay { Label("VaultCard is locked", systemImage: "lock.fill").font(.headline) }
                    .ignoresSafeArea()
                    .accessibilityIdentifier("bulk.editor.privacyShield")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct BulkCameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        uiViewController.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onImage: (UIImage) -> Void
        private let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
