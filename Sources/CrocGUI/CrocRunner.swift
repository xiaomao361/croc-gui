import Foundation
import Darwin

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

    static func source(for executable: URL, overridePath: String) -> String {
        if !overridePath.isEmpty,
           URL(fileURLWithPath: overridePath).standardizedFileURL == executable.standardizedFileURL {
            return "Custom"
        }
        if let environmentPath = ProcessInfo.processInfo.environment["CROC_EXECUTABLE"],
           URL(fileURLWithPath: environmentPath).standardizedFileURL == executable.standardizedFileURL {
            return "Environment"
        }
        if let bundledPath = Bundle.main.path(forResource: "croc", ofType: nil),
           URL(fileURLWithPath: bundledPath).standardizedFileURL == executable.standardizedFileURL {
            return "Bundled"
        }
        return "System"
    }
}

struct CrocOutputFrame: Equatable, Sendable {
    enum Terminator: Equatable, Sendable {
        case carriageReturn
        case newline
        case prompt
        case endOfFile
    }

    let text: String
    let terminator: Terminator
}

final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var ignoresNextLineFeed = false
    private let onFrame: @Sendable (CrocOutputFrame) -> Void

    init(onFrame: @escaping @Sendable (CrocOutputFrame) -> Void) {
        self.onFrame = onFrame
    }

    func consume(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        for byte in data {
            if ignoresNextLineFeed, byte == 0x0A {
                ignoresNextLineFeed = false
                continue
            }
            ignoresNextLineFeed = false

            switch byte {
            case 0x0D:
                emit(terminator: .carriageReturn)
                ignoresNextLineFeed = true
            case 0x0A:
                emit(terminator: .newline)
            default:
                buffer.append(byte)
            }
        }

        emitInteractivePromptIfComplete()
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return }
        emit(terminator: .endOfFile)
    }

    private func emit(terminator: CrocOutputFrame.Terminator) {
        guard let line = String(data: buffer, encoding: .utf8) else {
            buffer.removeAll(keepingCapacity: true)
            return
        }
        buffer.removeAll(keepingCapacity: true)
        onFrame(CrocOutputFrame(text: line, terminator: terminator))
    }

    private func emitInteractivePromptIfComplete() {
        guard let line = String(data: buffer, encoding: .utf8),
              line.contains("(y/N)"),
              line.contains("use --overwrite to omit"),
              line.contains("Resume ") || line.contains("Overwrite ") else { return }
        emit(terminator: .prompt)
    }
}

@MainActor
final class CrocRunner {
    private var process: Process?
    private var outputHandle: FileHandle?
    private var inputHandle: FileHandle?
    private var reader: LineReader?
    private var forceCancelTask: Task<Void, Never>?

    var isRunning: Bool { process?.isRunning == true }

    func start(
        executable: URL,
        command: CrocCommand,
        onOutput: @escaping @MainActor @Sendable (CrocOutputFrame) -> Void,
        completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void
    ) throws {
        guard !isRunning else { throw CrocRunnerError.alreadyRunning }

        let process = Process()
        let pipe = Pipe()
        let inputPipe = Pipe()
        process.executableURL = executable
        process.arguments = command.arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = inputPipe
        process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in new }

        let reader = LineReader { frame in
            Task { @MainActor in onOutput(frame) }
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
                try? self?.inputHandle?.close()
                self?.outputHandle = nil
                self?.inputHandle = nil
                self?.reader = nil
                self?.process = nil
                self?.forceCancelTask?.cancel()
                self?.forceCancelTask = nil
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
        inputHandle = inputPipe.fileHandleForWriting
        self.reader = reader
        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            self.process = nil
            outputHandle = nil
            inputHandle = nil
            self.reader = nil
            throw error
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        process.terminate()
        forceCancelTask?.cancel()
        let processID = process.processIdentifier
        forceCancelTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  let current = self?.process,
                  current.processIdentifier == processID,
                  current.isRunning else { return }
            Darwin.kill(processID, SIGKILL)
        }
    }

    func respondToPrompt(_ response: String) {
        guard let data = "\(response)\n".data(using: .utf8) else { return }
        try? inputHandle?.write(contentsOf: data)
    }
}
