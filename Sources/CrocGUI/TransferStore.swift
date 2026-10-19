import AppKit
import Foundation

@MainActor
final class TransferStore: ObservableObject {
    @Published var mode: TransferMode = .send
    @Published var phase: TransferPhase = .idle
    @Published var selectedItem: SelectedTransferItem?
    @Published var codePhrase = ""
    @Published var receiveCode = ""
    @Published var outputDirectory: URL
    @Published var progress: Double?
    @Published private(set) var progressSnapshot: CrocTransferProgress?
    @Published private(set) var secondsSinceLastActivity: Int?
    @Published private(set) var coreInfo: CrocCoreInfo
    @Published private(set) var completedAt: Date?
    @Published private(set) var transferDuration: TimeInterval?
    @Published private(set) var failureAllowsRetry = true
    @Published private(set) var failureRecovery: CrocRecoveryAction = .retry
    @Published private(set) var transferContext: TransferContext?
    @Published private(set) var receivedItemSummary: String?
    @Published private(set) var currentFileName: String?
    @Published var selectionNotice: String?
    @Published var logLines: [String] = []
    @Published var showDetails = false
    @Published var clipboardNotice: String?
    @Published var relay: String {
        didSet { defaults.set(relay, forKey: Keys.relay) }
    }
    @Published var useCustomRelay: Bool {
        didSet { defaults.set(useCustomRelay, forKey: Keys.useCustomRelay) }
    }
    @Published var executableOverride: String {
        didSet {
            guard executableOverride != oldValue else { return }
            defaults.set(executableOverride, forKey: Keys.executable)
            refreshCoreInfo()
        }
    }

    private let defaults: UserDefaults
    private let runner = CrocRunner()
    private var cancellationRequested = false
    private var promptFailureMessage: String?
    private var progressLogIndex: Int?
    private var lastActivityAt: Date?
    private var activityTask: Task<Void, Never>?
    private var coreInspectionTask: Task<Void, Never>?
    private var clipboardNoticeTask: Task<Void, Never>?
    private var transferStartedAt: Date?
    private var powerActivity: NSObjectProtocol?

    private enum Keys {
        static let relay = "relay"
        static let useCustomRelay = "useCustomRelay"
        static let executable = "executableOverride"
        static let outputDirectory = "outputDirectory"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedRelay = defaults.string(forKey: Keys.relay) ?? ""
        relay = savedRelay
        useCustomRelay = defaults.object(forKey: Keys.useCustomRelay) == nil
            ? !savedRelay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : defaults.bool(forKey: Keys.useCustomRelay)
        executableOverride = defaults.string(forKey: Keys.executable) ?? ""
        let savedOutput = defaults.string(forKey: Keys.outputDirectory)
        outputDirectory = savedOutput.map(URL.init(fileURLWithPath:))
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        progressSnapshot = nil
        secondsSinceLastActivity = nil
        coreInfo = CrocCoreInfo(state: .checking, version: nil, source: "System", path: nil)
        completedAt = nil
        transferDuration = nil
        Task { [weak self] in self?.refreshCoreInfo() }
    }

    var executableURL: URL? {
        CrocExecutableLocator.locate(overridePath: executableOverride)
    }

    var configuredRelay: String {
        useCustomRelay ? relay.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    var isRelayConfigurationValid: Bool {
        !useCustomRelay || !configuredRelay.isEmpty
    }

    var isBusy: Bool { phase.isRunning || runner.isRunning }

    var isCoreReady: Bool {
        guard let executableURL else { return false }
        return coreInfo.state == .available && coreInfo.path == executableURL.path
    }

    var coreReadinessMessage: String? {
        guard executableURL != nil else { return "Choose an available croc executable in Settings." }
        if coreInfo.state == .checking { return "Checking the croc core before starting…" }
        guard isCoreReady else {
            return "The selected core could not be verified. Choose a working croc executable or check it again in Settings."
        }
        return nil
    }

    var isFileProgress: Bool { phase == .transferring && progressSnapshot != nil }

    var canBeginSend: Bool {
        !isBusy && selectedItem != nil && isCoreReady && isRelayConfigurationValid
    }

    var canBeginReceive: Bool {
        !isBusy && !receiveCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isCoreReady && isRelayConfigurationValid
    }

    var displayedItem: SelectedTransferItem? { transferContext?.item ?? selectedItem }

    var displayedOutputDirectory: URL { transferContext?.outputDirectory ?? outputDirectory }

    var inactivityNotice: String? {
        guard isBusy, let secondsSinceLastActivity, secondsSinceLastActivity >= 30 else { return nil }
        return "No new output for \(TimeInterval(secondsSinceLastActivity).durationLabel). croc is still running."
    }

    var windowsReceiveCommand: String? {
        guard !codePhrase.isEmpty else { return nil }
        return CrocCommandBuilder.windowsReceiveInstruction(code: codePhrase, relay: transferContext?.relay ?? configuredRelay)
    }

    var unixReceiveCommand: String? {
        guard !codePhrase.isEmpty else { return nil }
        return CrocCommandBuilder.unixReceiveInstruction(code: codePhrase, relay: transferContext?.relay ?? configuredRelay)
    }

    var receiveInstructions: String? {
        guard let windowsReceiveCommand, let unixReceiveCommand else { return nil }
        return """
        For Windows (PowerShell):
            \(windowsReceiveCommand)

        For Linux/macOS:
            \(unixReceiveCommand)
        """
    }

    var statusTitle: String {
        switch phase {
        case .idle: selectedItem == nil && mode == .send ? "Ready" : "Ready to transfer"
        case .preparing: "Preparing transfer"
        case .waiting: "Waiting for the receiver"
        case .transferring: (transferContext?.mode ?? mode) == .send ? "Sending securely" : "Receiving securely"
        case .cancelling: "Cancelling transfer"
        case .completed: "Transfer complete"
        case .cancelled: "Transfer cancelled"
        case .failed: "Transfer failed"
        }
    }

    var statusDetail: String {
        switch phase {
        case .idle: "End-to-end encrypted · No account or cloud storage"
        case .preparing: activityDetail(base: progressSnapshot?.detailLabel ?? "Preparing the encrypted handoff")
        case .waiting: activityDetail(base: "Share the code phrase with the receiver")
        case .transferring:
            activityDetail(base: progressSnapshot.map { "Current file · \($0.detailLabel)" } ?? "Transfer in progress")
        case .cancelling: "Waiting for croc to stop safely"
        case .completed: completionSummary
        case .cancelled: "Nothing else will be sent or received"
        case let .failed(message): message
        }
    }

    var completionLocationDetail: String? {
        guard phase == .completed else { return nil }
        if transferContext?.mode == .receive {
            return "Saved to \(displayedOutputDirectory.abbreviatedDirectoryPath)"
        }
        return displayedItem.map { "Sent \($0.name)" }
    }

    var completionLocationURL: URL? {
        guard phase == .completed else { return nil }
        return transferContext?.mode == .receive ? displayedOutputDirectory : displayedItem?.url
    }

    func select(_ url: URL) {
        guard !isBusy else { return }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            selectionNotice = "This item is unavailable or cannot be read. Choose another file or folder."
            return
        }
        selectedItem = .inspect(url)
        transferContext = nil
        selectionNotice = nil
        codePhrase = ""
        phase = .idle
        progress = nil
        progressSnapshot = nil
        receivedItemSummary = nil
        currentFileName = nil
        clipboardNotice = nil
    }

    @discardableResult
    func acceptDrop(_ urls: [URL]) -> Bool {
        guard !isBusy else { return false }
        guard urls.count == 1, let url = urls.first else {
            selectionNotice = "Drop one file or folder at a time. To send several files, put them in a folder first."
            return false
        }
        select(url)
        return selectionNotice == nil
    }

    func clearSelectedItem() {
        guard !isBusy else { return }
        selectedItem = nil
        transferContext = nil
        selectionNotice = nil
        codePhrase = ""
        phase = .idle
        progress = nil
        progressSnapshot = nil
        receivedItemSummary = nil
        currentFileName = nil
        clipboardNotice = nil
    }

    func changeMode(to newMode: TransferMode) {
        guard !isBusy, mode != newMode else { return }
        mode = newMode
        transferContext = nil
        selectionNotice = nil
        phase = .idle
        codePhrase = ""
        progress = nil
        progressSnapshot = nil
        receivedItemSummary = nil
        currentFileName = nil
        clipboardNotice = nil
    }

    func setOutputDirectory(_ url: URL) {
        guard !isBusy else { return }
        outputDirectory = url
        defaults.set(url.path, forKey: Keys.outputDirectory)
    }

    func beginSend() {
        guard !isBusy else { return }
        guard let selectedItem else { return }
        transferContext = nil
        guard isRelayConfigurationValid else {
            fail("Enter a custom relay address in Settings.", recovery: .settings)
            return
        }
        start(command: CrocCommandBuilder.send(item: selectedItem.url, relay: configuredRelay))
    }

    func beginReceive() {
        guard !isBusy else { return }
        transferContext = nil
        let code = receiveCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            fail("Enter the sender's code phrase first.", recovery: .editCode)
            return
        }
        guard isRelayConfigurationValid else {
            fail("Enter a custom relay address in Settings.", recovery: .settings)
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue, FileManager.default.isWritableFile(atPath: outputDirectory.path) else {
            fail("Choose an existing, writable folder for received files.", recovery: .chooseDestination)
            return
        }
        start(command: CrocCommandBuilder.receive(code: code, output: outputDirectory, relay: configuredRelay))
    }

    func cancel() {
        guard phase.isRunning, phase != .cancelling else { return }
        cancellationRequested = true
        codePhrase = ""
        clipboardNotice = nil
        phase = .cancelling
        progress = nil
        progressSnapshot = nil
        logLines.append("Cancelling transfer…")
        runner.cancel()
    }

    func copyCode() {
        guard !codePhrase.isEmpty else { return }
        copyToPasteboard(codePhrase, notice: "Code copied to clipboard!")
    }

    func copyWindowsCommand() {
        guard let windowsReceiveCommand else { return }
        copyToPasteboard(windowsReceiveCommand, notice: "Windows command copied to clipboard!")
    }

    func copyUnixCommand() {
        guard let unixReceiveCommand else { return }
        copyToPasteboard(unixReceiveCommand, notice: "Linux/macOS command copied to clipboard!")
    }

    func copyReceiveInstructions() {
        guard let receiveInstructions else { return }
        copyToPasteboard(receiveInstructions, notice: "Receive instructions copied to clipboard!")
    }

    func prepareNewTransfer() {
        guard !isBusy else { return }
        editTransfer()
        receiveCode = ""
        logLines = []
        if mode == .send {
            selectedItem = nil
        }
    }

    /// Return to the form without discarding the user's code or selected file.
    func editTransfer() {
        guard !isBusy else { return }
        phase = .idle
        codePhrase = ""
        transferContext = nil
        progress = nil
        progressSnapshot = nil
        receivedItemSummary = nil
        currentFileName = nil
        secondsSinceLastActivity = nil
        completedAt = nil
        transferDuration = nil
        failureAllowsRetry = true
        failureRecovery = .retry
        clipboardNotice = nil
        selectionNotice = nil
    }

    func revealCompletionLocation() {
        guard let url = completionLocationURL else { return }
        if transferContext?.mode == .receive {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func start(command: CrocCommand) {
        // Check before resetting any state: a duplicate action must leave the live task intact.
        guard !isBusy else { return }
        transferContext = TransferContext(mode: mode, item: mode == .send ? selectedItem : nil,
                                          outputDirectory: outputDirectory, relay: configuredRelay)
        guard let executableURL else {
            fail(CrocRunnerError.executableNotFound.localizedDescription, recovery: .settings)
            return
        }
        guard isCoreReady else {
            fail(coreReadinessMessage ?? "Check the croc executable in Settings.", recovery: .settings)
            return
        }

        cancellationRequested = false
        promptFailureMessage = nil
        failureAllowsRetry = true
        failureRecovery = .retry
        selectionNotice = nil
        completedAt = nil
        transferDuration = nil
        transferStartedAt = Date()
        phase = .preparing
        progress = nil
        progressSnapshot = nil
        receivedItemSummary = nil
        currentFileName = nil
        progressLogIndex = nil
        clipboardNotice = nil
        codePhrase = mode == .send ? "" : codePhrase
        logLines = [
            "[core] \(coreInfo.logLabel)",
            "$ \(executableURL.path) \(command.arguments.joined(separator: " "))"
        ]
        startActivityMonitoring()
        startPowerActivity()

        do {
            try runner.start(
                executable: executableURL,
                command: command,
                onOutput: { [weak self] frame in self?.handle(frame) },
                completion: { [weak self] result in self?.finish(result) }
            )
        } catch {
            fail(error.localizedDescription, recovery: .settings)
            logLines.append("error: \(error.localizedDescription)")
            stopActivityMonitoring()
            stopPowerActivity()
        }
    }

    private func handle(_ frame: CrocOutputFrame) {
        guard phase.isRunning else { return }
        let line = CrocOutputParser.sanitized(frame.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        lastActivityAt = Date()
        secondsSinceLastActivity = 0

        if frame.terminator == .prompt {
            progressLogIndex = nil
            logLines.append(line)
            guard !cancellationRequested else {
                runner.respondToPrompt("n")
                return
            }
            if line.hasPrefix("Resume ") {
                logLines.append("Resuming the existing partial file.")
                runner.respondToPrompt("y")
            } else {
                failureAllowsRetry = false
                promptFailureMessage = "A different file already exists at the destination. Move it or choose another folder, then try again."
                logLines.append("The existing file was left unchanged.")
                runner.respondToPrompt("n")
            }
            return
        }

        let snapshot = CrocOutputParser.progressSnapshot(in: line)
        if snapshot != nil, frame.terminator == .carriageReturn {
            updateProgressLog(with: line)
        } else {
            progressLogIndex = nil
            logLines.append(line)
        }
        guard !cancellationRequested else { return }

        if let code = CrocOutputParser.codePhrase(in: line) {
            codePhrase = code
            progress = nil
            progressSnapshot = nil
            phase = .waiting
        }
        if transferContext?.mode == .receive,
           let summary = CrocOutputParser.receivedItemSummary(in: line) {
            receivedItemSummary = summary
        }
        if let activityPhase = CrocOutputParser.activityPhase(in: line, snapshot: snapshot) {
            if activityPhase != phase {
                progress = nil
                progressSnapshot = nil
                currentFileName = nil
            }
            phase = activityPhase
        }
        if let snapshot {
            progressSnapshot = snapshot
            progress = snapshot.fraction
            currentFileName = CrocOutputParser.currentFileName(in: line)
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        recordCompletion()
        if cancellationRequested {
            phase = .cancelled
        } else if let promptFailureMessage {
            fail(promptFailureMessage, recovery: .chooseDestination)
        } else {
            switch result {
            case .success:
                progress = 1
                if let snapshot = progressSnapshot {
                    progressSnapshot = CrocTransferProgress(
                        fraction: 1,
                        byteSummary: snapshot.byteSummary,
                        speed: snapshot.speed,
                        remainingTime: nil
                    )
                }
                phase = .completed
            case let .failure(error):
                let failure = CrocFailureExplainer.explain(
                    logLines: logLines,
                    fallback: error.localizedDescription
                )
                if failure.recovery == .chooseDestination, transferContext?.mode == .send {
                    fail("croc encountered a read-only location while sending. Check Details for the affected path and its permissions, then try again.", recovery: .retry)
                } else {
                    fail(failure.message, recovery: failure.recovery)
                }
                logLines.append("error: \(error.localizedDescription)")
            }
        }
        codePhrase = ""
        clipboardNotice = nil
        cancellationRequested = false
        promptFailureMessage = nil
        stopActivityMonitoring()
        stopPowerActivity()
    }

    func refreshCoreInfo() {
        coreInspectionTask?.cancel()
        guard let executableURL else {
            coreInfo = CrocCoreInfo(state: .unavailable, version: nil, source: "Not found", path: nil)
            return
        }

        let source = CrocExecutableLocator.source(for: executableURL, overridePath: executableOverride)
        coreInfo = CrocCoreInfo(state: .checking, version: nil, source: source, path: executableURL.path)
        coreInspectionTask = Task { [weak self] in
            let result = await CrocCoreInspector.inspect(executable: executableURL, source: source)
            guard !Task.isCancelled, let self else { return }
            guard self.executableURL == executableURL else {
                refreshCoreInfo()
                return
            }
            coreInfo = result
        }
    }

    private func updateProgressLog(with line: String) {
        if let progressLogIndex, logLines.indices.contains(progressLogIndex) {
            logLines[progressLogIndex] = line
        } else {
            logLines.append(line)
            progressLogIndex = logLines.index(before: logLines.endIndex)
        }
    }

    private func startActivityMonitoring() {
        activityTask?.cancel()
        lastActivityAt = Date()
        secondsSinceLastActivity = 0
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, let lastActivityAt else { continue }
                secondsSinceLastActivity = max(0, Int(Date().timeIntervalSince(lastActivityAt)))
            }
        }
    }

    private func stopActivityMonitoring() {
        activityTask?.cancel()
        activityTask = nil
        lastActivityAt = nil
        secondsSinceLastActivity = nil
    }

    private func startPowerActivity() {
        stopPowerActivity()
        powerActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Keep an active croc file transfer running"
        )
    }

    private func stopPowerActivity() {
        guard let powerActivity else { return }
        ProcessInfo.processInfo.endActivity(powerActivity)
        self.powerActivity = nil
    }

    private func recordCompletion() {
        let now = Date()
        completedAt = now
        transferDuration = transferStartedAt.map { now.timeIntervalSince($0) }
        transferStartedAt = nil
    }

    private var completionSummary: String {
        var parts: [String] = []
        if let completedAt {
            parts.append("Completed at \(completedAt.formatted(date: .omitted, time: .shortened))")
        }
        if let transferDuration {
            parts.append("Duration \(transferDuration.durationLabel)")
        }
        return parts.isEmpty ? "The files arrived safely" : parts.joined(separator: " · ")
    }

    private func activityDetail(base: String) -> String {
        guard let inactivityNotice else { return base }
        return "\(base) · \(inactivityNotice)"
    }

    private func fail(_ message: String, recovery: CrocRecoveryAction) {
        failureRecovery = recovery
        failureAllowsRetry = recovery == .retry
        phase = .failed(message)
    }

    private func copyToPasteboard(_ value: String, notice: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        clipboardNotice = notice
        clipboardNoticeTask?.cancel()
        clipboardNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.clipboardNotice == notice else { return }
            self?.clipboardNotice = nil
        }
    }
}
