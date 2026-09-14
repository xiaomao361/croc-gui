import AppKit
import Foundation
import Testing
@testable import CrocGUI

@MainActor
private struct TransferFixture {
    let directory: URL
    let source: URL
    let output: URL
    let defaults: UserDefaults
    let suite: String
    let store: TransferStore

    init(body: String = "sleep 0.2") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrocLifecycle-\(UUID().uuidString)")
        source = directory.appendingPathComponent("sample.zip")
        output = directory.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("test content".utf8).write(to: source)
        let executable = directory.appendingPathComponent("fake-croc")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
            echo 'croc version 10.7.0'
            exit 0
        fi
        \(body)
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        suite = "CrocLifecycle.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(executable.path, forKey: "executableOverride")
        defaults.set(output.path, forKey: "outputDirectory")
        store = TransferStore(defaults: defaults)
    }

    func cleanup() {
        store.cancel()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(4)
    while !condition(), Date() < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    try #require(condition())
}

@Test @MainActor func repeatedReceiveKeepsOriginalTaskAndDestination() async throws {
    let fixture = try TransferFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    store.changeMode(to: .receive)
    store.receiveCode = "sample-test-code"
    #expect(store.canBeginReceive)
    store.beginReceive()
    let originalLog = store.logLines
    #expect(!store.canBeginReceive)
    store.beginReceive()
    store.setOutputDirectory(fixture.directory)
    #expect(store.phase == .preparing)
    #expect(store.isBusy)
    #expect(store.outputDirectory == fixture.output)
    #expect(store.logLines == originalLog)
    try await eventually { store.phase.isTerminal }
    #expect(store.phase == .completed)
    store.setOutputDirectory(fixture.directory)
    #expect(store.completionLocationURL == fixture.output)
    #expect(store.completionLocationDetail == "Saved to \(fixture.output.abbreviatedDirectoryPath)")
}

@Test @MainActor func repeatedSendKeepsFileAndActiveRelayInstructions() async throws {
    let fixture = try TransferFixture(body: "echo 'Code is: sample-test-code'\nsleep 0.3")
    defer { fixture.cleanup() }
    let store = fixture.store
    store.select(fixture.source)
    store.useCustomRelay = true
    store.relay = "relay.example.com:9009"
    store.beginSend()
    store.beginSend()
    store.clearSelectedItem()
    store.changeMode(to: .receive)
    try await eventually { store.phase == .waiting }
    store.useCustomRelay = false
    store.relay = "next.example.com:9010"
    #expect(store.mode == .send)
    #expect(store.selectedItem?.url == fixture.source)
    #expect(store.unixReceiveCommand == "CROC_SECRET='sample-test-code' croc --relay 'relay.example.com:9009'")
    #expect(store.windowsReceiveCommand == "croc --relay 'relay.example.com:9009' 'sample-test-code'")
    try await eventually { store.phase.isTerminal }
    #expect(store.phase == .completed)
    #expect(store.codePhrase.isEmpty)
}

@Test @MainActor func missingDestinationIsActionableAndCodeSurvivesEditing() throws {
    let fixture = try TransferFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    store.changeMode(to: .receive)
    store.receiveCode = "sample-test-code"
    store.setOutputDirectory(fixture.directory.appendingPathComponent("missing"))
    store.beginReceive()
    #expect(store.phase.isTerminal)
    #expect(store.phase != .completed)
    #expect(store.failureRecovery == .chooseDestination)
    #expect(!store.isBusy)
    store.setOutputDirectory(fixture.output)
    store.editTransfer()
    #expect(store.receiveCode == "sample-test-code")
    #expect(store.outputDirectory == fixture.output)
    #expect(store.canBeginReceive)
}

@Test @MainActor func multipleDroppedFilesNeverSilentlySelectOnlyOne() throws {
    let fixture = try TransferFixture()
    defer { fixture.cleanup() }
    let store = fixture.store
    store.select(fixture.source)
    let second = fixture.directory.appendingPathComponent("another.txt")
    try Data("another".utf8).write(to: second)
    let pasteboard = NSPasteboard(name: .init("CrocDrop.\(UUID().uuidString)"))
    #expect(pasteboard.writeObjects([fixture.source as NSURL, second as NSURL]))
    let urls = NativeFileDropTarget.DropView.fileURLs(from: pasteboard)
    #expect(urls.count == 2)
    #expect(!store.acceptDrop(urls))
    #expect(store.selectedItem?.url == fixture.source)
    #expect(store.selectionNotice?.contains("one file or folder") == true)
    #expect(store.acceptDrop([second]))
    #expect(store.selectedItem?.url == second)
    #expect(store.selectionNotice == nil)
}

@Test @MainActor func unavailableDropKeepsPreviousSelectionAndReportsFailure() throws {
    let fixture = try TransferFixture()
    defer { fixture.cleanup() }
    fixture.store.select(fixture.source)
    #expect(!fixture.store.acceptDrop([fixture.directory.appendingPathComponent("missing")]))
    #expect(fixture.store.selectionNotice != nil)
    #expect(fixture.store.selectedItem?.url == fixture.source)
}

@Test @MainActor func refusedRelayStaysFailedWithSettingsRecovery() async throws {
    let fixture = try TransferFixture(body: "echo 'connection refused'\nsleep 0.05\nexit 1")
    defer { fixture.cleanup() }
    let store = fixture.store
    store.select(fixture.source)
    store.beginSend()
    try await eventually { store.phase.isTerminal }
    #expect(store.failureRecovery == .settings)
    #expect(store.phase != .completed)
    #expect(store.statusDetail.contains("relay could not be reached"))
    #expect(store.logLines.contains("connection refused"))
}

@Test(arguments: [0, 1]) @MainActor func overwriteRefusalNeverBecomesSuccess(exitStatus: Int) async throws {
    let fixture = try TransferFixture(body: """
    printf '%s' "Overwrite '/tmp/example.txt'? (y/N) (use --overwrite to omit) "
    IFS= read -r answer
    [ "$answer" = n ] || exit 99
    exit \(exitStatus)
    """)
    defer { fixture.cleanup() }
    let store = fixture.store
    store.changeMode(to: .receive)
    store.receiveCode = "sample-test-code"
    store.beginReceive()
    try await eventually { store.phase.isTerminal }
    #expect(store.phase != .completed)
    #expect(store.failureRecovery == .chooseDestination)
    #expect(!store.failureAllowsRetry)
    #expect(store.statusDetail.contains("already exists"))
    #expect(store.completedAt != nil)
    #expect(store.receiveCode == "sample-test-code")
}

@Test @MainActor func cancellationRemainsCancelledWhenCoreExitsZero() async throws {
    let fixture = try TransferFixture(body: """
    trap 'exit 0' TERM
    echo 'Code is: sample-test-code'
    while :; do sleep 0.05; done
    """)
    defer { fixture.cleanup() }
    let store = fixture.store
    store.select(fixture.source)
    store.beginSend()
    try await eventually { store.phase == .waiting }
    store.cancel()
    #expect(store.phase == .cancelling)
    #expect(store.codePhrase.isEmpty)
    try await eventually { store.phase.isTerminal }
    #expect(store.phase == .cancelled)
}

@Test func copiedUnixInstructionPreservesArgumentsWithoutExecutingShellContent() throws {
    let code = "test'$(printf BAD)-code"
    let relay = "relay'$(printf BAD).example:9009"
    let instruction = CrocCommandBuilder.unixReceiveInstruction(code: code, relay: relay)
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "croc() { printf '%s\\n' \"$CROC_SECRET\" \"$@\"; }; " + instruction]
    process.standardOutput = pipe
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #expect(output == "\(code)\n--relay\n\(relay)\n")
}

@Test func windowsInstructionQuotesPowerShellMetacharacters() {
    #expect(CrocCommandBuilder.windowsReceiveInstruction(code: "test'code", relay: "host';$env:PATH") ==
            "croc --relay 'host'';$env:PATH' 'test''code'")
}

@Test @MainActor func fullProgressStillWaitsForCoreExit() async throws {
    let fixture = try TransferFixture(body: "echo 'Sending sample.zip'\necho 'sample.zip 100% |████| (2.0/2.0 MB, 10 MB/s)'\nsleep 0.3\nexit 1")
    defer { fixture.cleanup() }
    let store = fixture.store
    store.select(fixture.source)
    store.beginSend()
    try await eventually { store.progress == 1 }
    #expect(store.isBusy)
    #expect(store.phase != .completed)
    try await eventually { store.phase.isTerminal }
    #expect(store.phase != .completed)
}

@Test @MainActor func sendWriteFailureDoesNotOfferReceiveFolderRecovery() async throws {
    let fixture = try TransferFixture(body: "echo 'read-only file system'\nsleep 0.05\nexit 1")
    defer { fixture.cleanup() }
    fixture.store.select(fixture.source)
    fixture.store.beginSend()
    try await eventually { fixture.store.phase.isTerminal }
    #expect(fixture.store.failureRecovery == .retry)
    #expect(fixture.store.statusDetail.contains("while sending"))
}
