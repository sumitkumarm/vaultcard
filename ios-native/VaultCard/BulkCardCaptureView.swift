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
    @State private var isCameraPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var isRecognizing = false
    @State private var isSaving = false
    @State private var isPrivacyShieldVisible = false
    @State private var showError = false
    @State private var showCameraMessage = false
    @State private var errorMessage = ""
    @State private var cameraMessage = ""
    @State private var pastedText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var recognitionTask: Task<Void, Never>?
    @State private var didLoadUITestFixture = false

    private let importTypes: [UTType] = [.image, .commaSeparatedText, .tabSeparatedText, .plainText]

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

    @ViewBuilder
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

            if rows.isEmpty {
                VaultSurface(padding: 18) {
                    VStack(spacing: 9) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.title2)
                            .foregroundStyle(VaultTheme.electricBlue)
                        Text("No cards yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Take a photo, choose images, import a file, or paste rows to begin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(rows) { row in
                    cardEditor(row: binding(for: row))
                }
            }

            if rows.contains(where: { $0.input.cvv.isEmpty }) {
                Label("Some cards have no CVV. Add CVV later from the card to manage it.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(VaultTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bulk.missingCVV.warning")
            }

            Button {
                saveCards()
            } label: {
                HStack(spacing: 8) {
                    if isSaving { ProgressView().tint(.white) }
                    Text(isSaving ? "Adding Cards…" : "Confirm & Add \(rows.count) \(rows.count == 1 ? "Card" : "Cards")")
                }
                .frame(maxWidth: .infinity)
            }
            .font(.headline)
            .controlSize(.large)
            .vaultPrimaryButton()
            .disabled(rows.isEmpty || rows.contains(where: { blockingIssue(for: $0) != nil }) || isSaving || isRecognizing)
            .opacity(rows.isEmpty || rows.contains(where: { blockingIssue(for: $0) != nil }) ? 0.55 : 1)
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

    private func cardEditor(row: Binding<BulkCardRow>) -> some View {
        let value = row.wrappedValue
        let issue = displayIssue(for: value)
        return VaultSurface(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Card from row \(value.sourceRow)")
                            .font(.subheadline.weight(.semibold))
                        Text(CardRules.inferNetwork(value.cardNumber).displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        rows.removeAll { $0.id == value.id }
                    } label: {
                        Image(systemName: "trash")
                            .font(.body.weight(.medium))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove card from row \(value.sourceRow)")
                    .accessibilityIdentifier("bulk.remove.\(value.sourceRow)")
                }

                field(title: "Card number", accessibilityID: "bulk.row.\(value.sourceRow).number") {
                    TextField("16-digit card number", text: row.cardNumber)
                        .keyboardType(.numberPad)
                        .textContentType(.creditCardNumber)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: row.wrappedValue.cardNumber) { _, newValue in
                            row.wrappedValue.cardNumber = String(CardRules.digitsOnly(newValue).prefix(16))
                        }
                }

                HStack(spacing: 12) {
                    field(title: "Expiry", accessibilityID: "bulk.row.\(value.sourceRow).expiry") {
                        TextField("MM/YY", text: row.expiry)
                            .keyboardType(.numberPad)
                            .textContentType(.none)
                            .onChange(of: row.wrappedValue.expiry) { _, newValue in
                                row.wrappedValue.expiry = CardRules.formatExpiryInput(newValue)
                            }
                    }
                    field(title: row.wrappedValue.codeIsPIN ? "PIN" : "CVV", accessibilityID: "bulk.row.\(value.sourceRow).code") {
                        TextField(row.wrappedValue.codeIsPIN ? "Optional PIN" : "Optional CVV", text: row.code)
                            .keyboardType(.numberPad)
                            .textContentType(.none)
                            .onChange(of: row.wrappedValue.code) { _, newValue in
                                row.wrappedValue.code = String(CardRules.digitsOnly(newValue).prefix(4))
                            }
                    }
                }

                Toggle("This security code is a PIN", isOn: row.codeIsPIN)
                    .font(.caption.weight(.medium))
                    .tint(VaultTheme.electricBlue)

                if let issue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(blockingIssue(for: row.wrappedValue) == nil ? VaultTheme.warning : VaultTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("bulk.row.\(value.sourceRow).issue")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bulk.row.\(value.sourceRow)")
    }

    private func field<Content: View>(
        title: String,
        accessibilityID: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .font(.subheadline.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(accessibilityID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func blockingIssue(for row: BulkCardRow) -> String? {
        guard CardRules.isValidCardNumber(row.cardNumber) else {
            return "Enter a valid 16-digit Visa or Mastercard number."
        }
        guard CardRules.validateExpiry(row.expiry) else {
            return "Enter expiry as MM/YY."
        }
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

    private func displayIssue(for row: BulkCardRow) -> String? {
        blockingIssue(for: row) ?? row.issue
    }

    private func saveCards() {
        guard !rows.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        let inputs = rows.map(\.input)
        do {
            _ = try model.addBulkCards(inputs)
            rows.removeAll()
            model.routePath = []
        } catch let partial as BulkCardSaveError {
            let savedCount = min(partial.savedIDs.count, rows.count)
            if savedCount > 0 { rows.removeFirst(savedCount) }
            presentError(partial.localizedDescription)
        } catch {
            presentError(error.localizedDescription)
        }
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
        guard !didLoadUITestFixture,
              ProcessInfo.processInfo.arguments.contains("--ui-testing-bulk") else { return }
        didLoadUITestFixture = true
        rows = BulkCardParser.parse("4111111111111111,May 26,123\n5555555555554444,August 2028,")
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
