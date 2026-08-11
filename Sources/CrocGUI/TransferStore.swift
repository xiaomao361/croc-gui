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
        didSet { defaults.set(executableOverride, forKey: Keys.executable) }
    }

    private let defaults: UserDefaults
    private let runner = CrocRunner()
    private var cancellationRequested = false

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

    var windowsReceiveCommand: String? {
        guard !codePhrase.isEmpty else { return nil }
        return "croc \(codePhrase)"
    }

    var unixReceiveCommand: String? {
        guard !codePhrase.isEmpty else { return nil }
        return "CROC_SECRET=\"\(codePhrase)\" croc"
    }

    var receiveInstructions: String? {
        guard let windowsReceiveCommand, let unixReceiveCommand else { return nil }
        return """
        For Windows:
            \(windowsReceiveCommand)

        For Linux/macOS:
            \(unixReceiveCommand)
        """
    }

    var statusTitle: String {
        switch phase {
        case .idle: selectedItem == nil && mode == .send ? "Ready" : "Ready to transfer"
        case .preparing: "Starting croc"
        case .waiting: "Waiting for the receiver"
        case .transferring: mode == .send ? "Sending securely" : "Receiving securely"
        case .completed: "Transfer complete"
        case .cancelled: "Transfer cancelled"
        case .failed: "Transfer failed"
        }
    }

    var statusDetail: String {
        switch phase {
        case .idle: "End-to-end encrypted · No account or cloud storage"
        case .preparing: "Preparing the encrypted handoff"
        case .waiting: "Share the code phrase with the receiver"
        case .transferring: progress.map { "\(Int($0 * 100))% complete" } ?? "Transfer in progress"
        case .completed: "The files arrived safely"
        case .cancelled: "Nothing else will be sent or received"
        case let .failed(message): message
        }
    }

    func select(_ url: URL) {
        guard !phase.isRunning else { return }
        selectedItem = .inspect(url)
        codePhrase = ""
        phase = .idle
        progress = nil
        clipboardNotice = nil
    }

    func clearSelectedItem() {
        guard !phase.isRunning else { return }
        selectedItem = nil
        codePhrase = ""
        phase = .idle
        progress = nil
        clipboardNotice = nil
    }

    func changeMode(to newMode: TransferMode) {
        guard !phase.isRunning, mode != newMode else { return }
        mode = newMode
        phase = .idle
        codePhrase = ""
        progress = nil
        clipboardNotice = nil
    }

    func setOutputDirectory(_ url: URL) {
        outputDirectory = url
        defaults.set(url.path, forKey: Keys.outputDirectory)
    }

    func beginSend() {
        guard let selectedItem else { return }
        guard isRelayConfigurationValid else {
            phase = .failed("Enter a custom relay address in Settings.")
            return
        }
        start(command: CrocCommandBuilder.send(item: selectedItem.url, relay: configuredRelay))
    }

    func beginReceive() {
        let code = receiveCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            phase = .failed("Enter the sender's code phrase first.")
            return
        }
        guard isRelayConfigurationValid else {
            phase = .failed("Enter a custom relay address in Settings.")
            return
        }
        start(command: CrocCommandBuilder.receive(code: code, output: outputDirectory, relay: configuredRelay))
    }

    func cancel() {
        guard phase.isRunning else { return }
        cancellationRequested = true
        codePhrase = ""
        progress = nil
        clipboardNotice = nil
        phase = .cancelled
        logLines.append("Transfer cancelled by user.")
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
        guard !phase.isRunning else { return }
        phase = .idle
        codePhrase = ""
        receiveCode = ""
        progress = nil
        clipboardNotice = nil
        logLines = []
        if mode == .send {
            selectedItem = nil
        }
    }

    private func start(command: CrocCommand) {
        guard let executableURL else {
            phase = .failed(CrocRunnerError.executableNotFound.localizedDescription)
            return
        }

        cancellationRequested = false
        phase = .preparing
        progress = nil
        clipboardNotice = nil
        codePhrase = mode == .send ? "" : codePhrase
        logLines = ["$ \(executableURL.path) \(command.arguments.joined(separator: " "))"]

        do {
            try runner.start(
                executable: executableURL,
                command: command,
                onLine: { [weak self] line in self?.handle(line) },
                completion: { [weak self] result in self?.finish(result) }
            )
        } catch {
            phase = .failed(error.localizedDescription)
            logLines.append("error: \(error.localizedDescription)")
        }
    }

    private func handle(_ rawLine: String) {
        let line = CrocOutputParser.sanitized(rawLine)
        guard !line.isEmpty else { return }
        logLines.append(line)
        guard !cancellationRequested else { return }

        if let code = CrocOutputParser.codePhrase(in: line) {
            codePhrase = code
            phase = .waiting
        }
        if let value = CrocOutputParser.progress(in: line) {
            progress = value
            phase = .transferring
        }
        if line.localizedCaseInsensitiveContains("sending") ||
            line.localizedCaseInsensitiveContains("receiving") {
            phase = .transferring
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            progress = 1
            phase = .completed
        case let .failure(error):
            if cancellationRequested {
                phase = .cancelled
            } else {
                phase = .failed(error.localizedDescription)
                logLines.append("error: \(error.localizedDescription)")
            }
        }
        codePhrase = ""
        clipboardNotice = nil
        cancellationRequested = false
    }

    private func copyToPasteboard(_ value: String, notice: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        clipboardNotice = notice
    }
}
