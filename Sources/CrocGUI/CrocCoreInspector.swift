import Foundation
import Darwin

enum CrocCoreInspector {
    static func inspect(
        executable: URL,
        source: String,
        timeout: Duration = .seconds(3)
    ) async -> CrocCoreInfo {
        let inspection = CoreInspection(executable: executable, source: source)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                inspection.start(timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            inspection.stop()
        }
    }
}

/// The lock protects callbacks from Process, FileHandle, timeout, and task cancellation.
private final class CoreInspection: @unchecked Sendable {
    private struct Delivery {
        let continuation: CheckedContinuation<CrocCoreInfo, Never>
        let info: CrocCoreInfo
        let timer: Task<Void, Never>?
    }

    private let lock = NSLock()
    private let process = Process()
    private let pipe = Pipe()
    private let executable: URL
    private let source: String
    private let outputLimit = 64 * 1024
    private var output = Data()
    private var discardingOversizedLine = false
    private var detectedVersion: String?
    private var continuation: CheckedContinuation<CrocCoreInfo, Never>?
    private var timer: Task<Void, Never>?
    private var started = false
    private var stopped = false
    private var completed = false
    private var reachedEOF = false
    private var exitStatus: Int32?
    private var exitedNormally = false

    init(executable: URL, source: String) {
        self.executable = executable
        self.source = source
    }

    func start(timeout: Duration, continuation: CheckedContinuation<CrocCoreInfo, Never>) {
        lock.lock()
        self.continuation = continuation
        if stopped {
            let delivery = takeDeliveryIfReady()
            lock.unlock()
            deliver(delivery)
            return
        }
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.read(handle.fileDescriptor, bytes.baseAddress, bytes.count)
                }
                if count >= 0 {
                    self?.consume(Data(buffer.prefix(count)))
                    break
                } else if errno != EINTR {
                    self?.stop()
                    break
                }
            }
        }
        process.terminationHandler = { [weak self] process in
            self?.exited(status: process.terminationStatus, normally: process.terminationReason == .exit)
        }
        do {
            // Keep launch and cancellation atomic: a cancelled task must never
            // launch its child after the cancellation callback has returned.
            try process.run()
            started = true
            lock.unlock()
            try? pipe.fileHandleForWriting.close()
        } catch {
            stopped = true
            let delivery = takeDeliveryIfReady()
            lock.unlock()
            deliver(delivery)
            return
        }

        let timer = Task.detached(priority: .utility) { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.stop()
        }
        lock.lock()
        if completed {
            lock.unlock()
            timer.cancel()
        } else {
            self.timer = timer
            lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        stopped = true
        // A version probe has no work to preserve. Kill only this probe's live
        // process, then wait for its termination callback before returning.
        if started, process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        let delivery = takeDeliveryIfReady()
        lock.unlock()
        deliver(delivery)
    }

    private func consume(_ data: Data) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        if data.isEmpty {
            finishVersionLine()
            reachedEOF = true
        } else if detectedVersion == nil {
            var start = data.startIndex
            for index in data.indices where data[index] == 0x0A || data[index] == 0x0D {
                appendVersionBytes(data[start..<index])
                finishVersionLine()
                start = data.index(after: index)
            }
            appendVersionBytes(data[start..<data.endIndex])
        }
        let delivery = takeDeliveryIfReady()
        lock.unlock()
        deliver(delivery)
    }

    private func appendVersionBytes(_ bytes: Data.SubSequence) {
        guard detectedVersion == nil, !discardingOversizedLine else { return }
        guard output.count + bytes.count <= outputLimit else {
            // Never interpret the arbitrary tail of an oversized line as a new
            // branded line. Continue draining until its real delimiter arrives.
            output.removeAll(keepingCapacity: true)
            discardingOversizedLine = true
            return
        }
        output.append(contentsOf: bytes)
    }

    private func finishVersionLine() {
        if detectedVersion == nil, !discardingOversizedLine {
            detectedVersion = CrocOutputParser.coreVersion(in: String(decoding: output, as: UTF8.self))
        }
        output.removeAll(keepingCapacity: true)
        discardingOversizedLine = false
    }

    private func exited(status: Int32, normally: Bool) {
        lock.lock()
        exitStatus = status
        exitedNormally = normally
        let delivery = takeDeliveryIfReady()
        lock.unlock()
        deliver(delivery)
    }

    /// Called with the lock held. A normal result needs both EOF and exit;
    /// cancellation may finish after exit even if a wrapper left its pipe open.
    private func takeDeliveryIfReady() -> Delivery? {
        guard !completed, let continuation,
              (stopped && (!started || exitStatus != nil)) || (reachedEOF && exitStatus != nil) else { return nil }
        completed = true
        self.continuation = nil
        let version = !stopped && exitedNormally && exitStatus == 0
            ? detectedVersion : nil
        let info = CrocCoreInfo(state: version == nil ? .unavailable : .available,
                                version: version, source: source, path: executable.path)
        let delivery = Delivery(continuation: continuation, info: info, timer: timer)
        timer = nil
        return delivery
    }

    private func deliver(_ delivery: Delivery?) {
        guard let delivery else { return }
        delivery.timer?.cancel()
        pipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
        delivery.continuation.resume(returning: delivery.info)
    }
}
