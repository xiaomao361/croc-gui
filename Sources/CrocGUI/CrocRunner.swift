import Foundation

enum CrocRunnerError: LocalizedError {
    case executableNotFound
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "croc CLI was not found. Choose it in Settings or install croc first."
        case .alreadyRunning:
            "A transfer is already running."
        }
    }
}

enum CrocExecutableLocator {
    static func locate(overridePath: String) -> URL? {
        let manager = FileManager.default
        let candidates: [String?] = [
            overridePath.isEmpty ? nil : overridePath,
            ProcessInfo.processInfo.environment["CROC_EXECUTABLE"],
            Bundle.main.path(forResource: "croc", ofType: nil),
            "/opt/homebrew/bin/croc",
            "/usr/local/bin/croc"
        ]

        for case let path? in candidates where manager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent("croc").path
            if manager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}

private final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func consume(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                onLine(line.trimmingCharacters(in: .newlines))
            }
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) else { return }
        buffer.removeAll()
        onLine(line)
    }
}

@MainActor
final class CrocRunner {
    private var process: Process?
    private var outputHandle: FileHandle?
    private var reader: LineReader?

    var isRunning: Bool { process?.isRunning == true }

    func start(
        executable: URL,
        command: CrocCommand,
        onLine: @escaping @MainActor @Sendable (String) -> Void,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
    ) throws {
        guard !isRunning else { throw CrocRunnerError.alreadyRunning }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = command.arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in new }

        let reader = LineReader { line in
            Task { @MainActor in onLine(line) }
        }
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                reader.finish()
                handle.readabilityHandler = nil
            } else {
                reader.consume(data)
            }
        }

        process.terminationHandler = { [weak self] process in
            reader.finish()
            Task { @MainActor in
                self?.outputHandle?.readabilityHandler = nil
                self?.outputHandle = nil
                self?.reader = nil
                self?.process = nil
                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    let error = NSError(
                        domain: "CrocRunner",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "croc exited with status \(process.terminationStatus)"]
                    )
                    completion(.failure(error))
                }
            }
        }

        self.process = process
        outputHandle = handle
        self.reader = reader
        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            self.process = nil
            outputHandle = nil
            self.reader = nil
            throw error
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }
}
