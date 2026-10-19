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
    static func locate(
        overridePath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let manager = FileManager.default
        if !overridePath.isEmpty {
            return manager.isExecutableFile(atPath: overridePath) ? URL(fileURLWithPath: overridePath) : nil
        }
        if let environmentPath = environment["CROC_EXECUTABLE"], !environmentPath.isEmpty {
            return manager.isExecutableFile(atPath: environmentPath) ? URL(fileURLWithPath: environmentPath) : nil
        }
        let candidates: [String?] = [
            Bundle.main.path(forResource: "croc", ofType: nil),
            "/opt/homebrew/bin/croc",
            "/usr/local/bin/croc"
        ]

        for case let path? in candidates where manager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent("croc").path
            if manager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static func source(
        for executable: URL,
        overridePath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if !overridePath.isEmpty,
           URL(fileURLWithPath: overridePath).standardizedFileURL == executable.standardizedFileURL {
            return "Custom"
        }
        if let environmentPath = environment["CROC_EXECUTABLE"],
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
    private enum Event: Sendable {
        case output(CrocOutputFrame)
        case endOfOutput
        case outputFailed(String)
        case exited(status: Int32, signalled: Bool)
    }

    private var attemptID: UUID?
    private var process: Process?
    private var outputHandle: FileHandle?
    private var inputHandle: FileHandle?
    private var eventTask: Task<Void, Never>?
    private var forceCancelTask: Task<Void, Never>?

    // An exited process still owns the attempt until its final output has been delivered.
    var isRunning: Bool { attemptID != nil }

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

        let id = UUID()
        let eventCapacity = 256
        let pendingEvents = DispatchSemaphore(value: eventCapacity)
        let (events, continuation) = AsyncStream.makeStream(of: Event.self,
            bufferingPolicy: .bufferingOldest(eventCapacity))
        let emit: @Sendable (Event) -> Void = { event in
            // Apply backpressure on the background producers instead of dropping
            // frames or accumulating an unbounded MainActor backlog.
            pendingEvents.wait()
            if case .terminated = continuation.yield(event) { pendingEvents.signal() }
        }
        let reader = LineReader { frame in
            emit(.output(frame))
        }
        let handle = pipe.fileHandleForReading
        process.terminationHandler = { process in
            emit(.exited(status: process.terminationStatus,
                         signalled: process.terminationReason != .exit))
        }

        attemptID = id
        self.process = process
        outputHandle = handle
        inputHandle = inputPipe.fileHandleForWriting
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            continuation.finish()
            try? handle.close()
            try? inputPipe.fileHandleForWriting.close()
            try? pipe.fileHandleForWriting.close()
            try? inputPipe.fileHandleForReading.close()
            attemptID = nil
            self.process = nil
            outputHandle = nil
            inputHandle = nil
            throw error
        }

        try? pipe.fileHandleForWriting.close()
        try? inputPipe.fileHandleForReading.close()

        // One reader owns the byte stream. One MainActor consumer delivers every
        // frame in order, including the final unterminated line, before completion.
        DispatchQueue.global(qos: .utility).async {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                // Unlike read(upToCount:), one POSIX read returns as soon as
                // bytes are available. Prompts and progress must not wait for EOF.
                let count = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.read(handle.fileDescriptor, bytes.baseAddress, bytes.count)
                }
                if count > 0 {
                    reader.consume(Data(buffer.prefix(count)))
                } else if count == 0 {
                    break
                } else if errno != EINTR {
                    let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    emit(.outputFailed(error.localizedDescription))
                    break
                }
            }
            reader.finish()
            emit(.endOfOutput)
        }

        eventTask = Task { [weak self] in
            defer { continuation.finish() }
            var reachedEOF = false
            var exit: (status: Int32, signalled: Bool)?
            var outputError: String?
            for await event in events {
                pendingEvents.signal()
                guard let self, attemptID == id else { break }
                switch event {
                case let .output(frame):
                    onOutput(frame)
                case .endOfOutput:
                    reachedEOF = true
                case let .outputFailed(message):
                    outputError = message
                    cancel()
                case let .exited(status, signalled):
                    exit = (status, signalled)
                }
                guard reachedEOF, let exit else { continue }
                continuation.finish()
                self.process?.terminationHandler = nil
                try? outputHandle?.close()
                try? inputHandle?.close()
                outputHandle = nil
                inputHandle = nil
                self.process = nil
                attemptID = nil
                forceCancelTask?.cancel()
                forceCancelTask = nil
                eventTask = nil
                if let outputError {
                    completion(.failure(NSError(domain: "CrocRunner", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Could not read croc output: \(outputError)"])))
                } else if exit.status == 0, !exit.signalled {
                    completion(.success(()))
                } else {
                    let description = exit.signalled
                        ? "croc stopped after signal \(exit.status)"
                        : "croc exited with status \(exit.status)"
                    completion(.failure(NSError(domain: "CrocRunner", code: Int(exit.status),
                        userInfo: [NSLocalizedDescriptionKey: description])))
                }
                break
            }
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        process.terminate()
        forceCancelTask?.cancel()
        let id = attemptID
        let processID = process.processIdentifier
        forceCancelTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  let current = self?.process,
                  self?.attemptID == id,
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
