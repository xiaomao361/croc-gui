import AppKit
import Foundation
import Testing
@testable import CrocGUI

private final class FrameRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CrocOutputFrame] = []

    func append(_ frame: CrocOutputFrame) {
        lock.lock()
        storage.append(frame)
        lock.unlock()
    }

    var frames: [CrocOutputFrame] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Test func sendCommandUsesDefaultRelayAndIgnoresRunnerInputPipe() {
    let command = CrocCommandBuilder.send(
        item: URL(fileURLWithPath: "/tmp/sample.zip"),
        relay: "  "
    )
    #expect(command.arguments == ["--ignore-stdin", "--disable-clipboard", "send", "/tmp/sample.zip"])
    #expect(command.environment.isEmpty)
}

@Test func receiveCommandKeepsSecretOutOfArguments() {
    let command = CrocCommandBuilder.receive(
        code: "copper-lake-seven",
        output: URL(fileURLWithPath: "/tmp/inbox"),
        relay: "relay.example.com:9009"
    )
    #expect(command.arguments == ["--relay", "relay.example.com:9009", "--ignore-stdin", "--yes", "--out", "/tmp/inbox"])
    #expect(command.environment["CROC_SECRET"] == "copper-lake-seven")
    #expect(!command.arguments.contains("copper-lake-seven"))
}

@Test @MainActor func nativeDropReaderAcceptsFileURLPasteboardItems() throws {
    let dropView = NativeFileDropTarget.DropView()
    #expect(dropView.registeredDraggedTypes.contains(.fileURL))

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CrocNativeDropTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let file = directory.appendingPathComponent("sample.sql.gz")
    try Data([0x1f, 0x8b]).write(to: file)
    let pasteboard = NSPasteboard(name: .init("CrocNativeDropTests.\(UUID().uuidString)"))
    pasteboard.clearContents()

    #expect(pasteboard.writeObjects([file as NSURL]))
    #expect(NativeFileDropTarget.DropView.fileURLs(from: pasteboard) == [file.standardizedFileURL])
}

@Test func parserExtractsCodeAndProgress() {
    #expect(CrocOutputParser.codePhrase(in: "Code is: copper-lake-seven") == "copper-lake-seven")
    #expect(CrocOutputParser.codePhrase(in: "Code is: 2060-printer-vampire-flood") == "2060-printer-vampire-flood")
    #expect(CrocOutputParser.progress(in: "Sending 42%") == 0.42)
}

@Test func lineReaderEmitsCarriageReturnProgressWithoutWaitingForNewline() {
    let recorder = FrameRecorder()
    let reader = LineReader(onFrame: recorder.append)

    reader.consume(Data("Preparing\rfile.bin 42%".utf8))
    reader.consume(Data("\r\nComplete\npartial".utf8))
    reader.finish()

    #expect(recorder.frames == [
        CrocOutputFrame(text: "Preparing", terminator: .carriageReturn),
        CrocOutputFrame(text: "file.bin 42%", terminator: .carriageReturn),
        CrocOutputFrame(text: "Complete", terminator: .newline),
        CrocOutputFrame(text: "partial", terminator: .endOfFile)
    ])
}

@Test func lineReaderEmitsResumePromptWithoutWaitingForTerminator() {
    let recorder = FrameRecorder()
    let reader = LineReader(onFrame: recorder.append)

    reader.consume(Data("Resume '/tmp/source.bin' (42.0%)? (y/N)   (use --overwrite to omit) ".utf8))

    #expect(recorder.frames == [
        CrocOutputFrame(
            text: "Resume '/tmp/source.bin' (42.0%)? (y/N)   (use --overwrite to omit) ",
            terminator: .prompt
        )
    ])
}

@Test @MainActor func runnerCanAnswerAnInteractiveResumePrompt() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CrocRunnerPromptTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appendingPathComponent("resume-prompt.sh")
    let script = """
    #!/bin/sh
    printf '%s' "Resume '/tmp/source.bin' (42.0%)? (y/N)   (use --overwrite to omit) "
    IFS= read -r answer
    [ "$answer" = "y" ]
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

    let runner = CrocRunner()
    try await withCheckedThrowingContinuation { continuation in
        do {
            try runner.start(
                executable: executable,
                command: CrocCommand(arguments: [], environment: [:]),
                onOutput: { frame in
                    if frame.terminator == .prompt {
                        runner.respondToPrompt("y")
                    }
                },
                completion: { result in
                    continuation.resume(with: result)
                }
            )
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

@Test func parserExtractsLargeTransferMetrics() {
    let snapshot = CrocOutputParser.progressSnapshot(
        in: "archive.img 42% |████████            | (7.6/18 GB, 12.4 MB/s) [8m:14m]"
    )

    #expect(snapshot?.fraction == 0.42)
    #expect(snapshot?.byteSummary == "7.6/18 GB")
    #expect(snapshot?.speed == "12.4 MB/s")
    #expect(snapshot?.remainingTime == "14m")
    #expect(snapshot?.detailLabel == "42% · 7.6/18 GB · 12.4 MB/s · ETA 14m")
}

@Test func parserTreatsSingleRateMetricAsSpeed() {
    let snapshot = CrocOutputParser.progressSnapshot(
        in: "Hashing archive.img 42% |████                | (23 MB/s) [1s:1s]"
    )

    #expect(snapshot?.byteSummary == nil)
    #expect(snapshot?.speed == "23 MB/s")
}

@Test func parserAcceptsOldAndNewCoreVersionFormats() {
    #expect(CrocOutputParser.coreVersion(in: "croc version v10.3.1") == "10.3.1")
    #expect(CrocOutputParser.coreVersion(in: "croc version 10.7.0") == "10.7.0")
}

@Test func parserRemovesAnsiSequences() {
    let line = "\u{001B}[32mCode is: apple-river-blue\u{001B}[0m"
    #expect(CrocOutputParser.codePhrase(in: line) == "apple-river-blue")
}

@Test func failureExplainerTurnsSecureChannelOutputIntoRecoveryGuidance() {
    let message = CrocFailureExplainer.message(
        logLines: ["securing channel...", "room (secure channel) not ready, maybe peer disconnected"],
        fallback: "croc exited with status 1"
    )

    #expect(message.contains("secure channel could not be established"))
    #expect(message.contains("compatible croc version"))
}

@Test func failureExplainerPreservesUnknownFallback() {
    #expect(CrocFailureExplainer.message(
        logLines: ["unexpected core output"],
        fallback: "croc exited with status 1"
    ) == "croc exited with status 1")
}

@Test @MainActor func receiveInstructionsMatchCrocCLIUsage() {
    let suiteName = "CrocGUITests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = TransferStore(defaults: defaults)
    store.codePhrase = "8527-credit-tuna-radio"

    #expect(store.windowsReceiveCommand == "croc 8527-credit-tuna-radio")
    #expect(store.unixReceiveCommand == "CROC_SECRET=\"8527-credit-tuna-radio\" croc")
    #expect(store.receiveInstructions?.contains("For Windows:") == true)
    #expect(store.receiveInstructions?.contains("For Linux/macOS:") == true)
}

@Test @MainActor func cancellingWaitsForProcessExitAndClearsHandoffState() {
    let suiteName = "CrocGUITests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = TransferStore(defaults: defaults)
    store.phase = .waiting
    store.codePhrase = "8527-credit-tuna-radio"
    store.progress = 0.3
    store.clipboardNotice = "Code copied to clipboard!"

    store.cancel()

    #expect(store.phase == .cancelling)
    #expect(store.codePhrase.isEmpty)
    #expect(store.progress == 0.3)
    #expect(store.clipboardNotice == nil)
}

@Test func transferDurationUsesCompactReadableLabels() {
    #expect(TimeInterval(5).durationLabel == "5s")
    #expect(TimeInterval(125).durationLabel == "2m 5s")
    #expect(TimeInterval(7_260).durationLabel == "2h 1m")
}

@Test @MainActor func relaySelectionDistinguishesDefaultAndCustomConfiguration() {
    let suiteName = "CrocGUITests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = TransferStore(defaults: defaults)

    store.relay = "relay.example.com:9009"
    store.useCustomRelay = false
    #expect(store.configuredRelay.isEmpty)
    #expect(store.isRelayConfigurationValid)

    store.useCustomRelay = true
    #expect(store.configuredRelay == "relay.example.com:9009")
    #expect(store.isRelayConfigurationValid)

    store.relay = "  "
    #expect(store.configuredRelay.isEmpty)
    #expect(!store.isRelayConfigurationValid)
}

@Test func downloadDirectoryUsesHomeRelativeDisplayPath() {
    let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    #expect(downloads.abbreviatedDirectoryPath == "~/Downloads/")
}
