import Foundation
import Darwin
import Testing
@testable import CrocGUI

private struct ReliabilityFixture {
    let directory: URL
    let executable: URL

    init(body: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrocReliability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent("mock-croc")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class ReliabilityOutputRecorder {
    var frames: [CrocOutputFrame] = []
    var completed = false
    var receivedLateOutput = false
    var countAtCompletion = 0
}

@MainActor
private func reliabilityRun(
    _ runner: CrocRunner,
    executable: URL,
    onCompletion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void = { _ in },
    onOutput: @escaping @MainActor @Sendable (CrocOutputFrame) -> Void
) async throws -> Result<Void, Error> {
    try await withCheckedThrowingContinuation { continuation in
        do {
            try runner.start(executable: executable, command: CrocCommand(arguments: [], environment: [:]),
                             onOutput: onOutput, completion: {
                                 onCompletion($0)
                                 continuation.resume(returning: $0)
                             })
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

@Test(arguments: [0, 23]) @MainActor
func runnerDeliversOrderedOutputAndFinalPartialLineBeforeCompletion(exitStatus: Int) async throws {
    let fixture = try ReliabilityFixture(body: """
    i=0
    while [ "$i" -lt 2000 ]; do
        printf 'line-%s\\n' "$i"
        i=$((i + 1))
    done
    printf 'FINAL read-only file system'
    exit \(exitStatus)
    """)
    defer { fixture.cleanup() }
    let runner = CrocRunner()
    let recorder = ReliabilityOutputRecorder()
    let result = try await reliabilityRun(runner, executable: fixture.executable, onCompletion: { _ in
        recorder.completed = true
        recorder.countAtCompletion = recorder.frames.count
    }) { frame in
        if recorder.completed { recorder.receivedLateOutput = true }
        recorder.frames.append(frame)
    }
    #expect(!runner.isRunning)
    #expect(recorder.countAtCompletion == 2001)
    #expect(recorder.frames.count == 2001)
    #expect(Array(recorder.frames.dropLast()).map(\.text) == (0..<2000).map { "line-\($0)" })
    #expect(recorder.frames.last == CrocOutputFrame(text: "FINAL read-only file system", terminator: .endOfFile))
    switch result {
    case .success: #expect(exitStatus == 0)
    case let .failure(error): #expect((error as NSError).code == exitStatus && exitStatus != 0)
    }
    await Task.yield()
    #expect(!recorder.receivedLateOutput)
}

@Test @MainActor func runnerAnswersPromptBeforeWaitingForEOF() async throws {
    let fixture = try ReliabilityFixture(body: """
    printf '%s' "Resume '/tmp/reliability.bin' (42.0%)? (y/N) (use --overwrite to omit) "
    IFS= read -r answer
    [ "$answer" = y ] || exit 41
    printf 'resumed'
    """)
    defer { fixture.cleanup() }
    let runner = CrocRunner()
    var sawPrompt = false
    var finalFrame: CrocOutputFrame?
    let result = try await reliabilityRun(runner, executable: fixture.executable) { frame in
        if frame.terminator == .prompt {
            sawPrompt = true
            runner.respondToPrompt("y")
        }
        finalFrame = frame
    }
    try result.get()
    #expect(sawPrompt)
    #expect(finalFrame == CrocOutputFrame(text: "resumed", terminator: .endOfFile))
}

@Test @MainActor func runnerCanRestartAfterLaunchFailureAndCompletedAttempt() async throws {
    let fixture = try ReliabilityFixture(body: "printf 'only-this-attempt'")
    defer { fixture.cleanup() }
    let runner = CrocRunner()
    do {
        try runner.start(executable: fixture.directory.appendingPathComponent("missing"),
                         command: CrocCommand(arguments: [], environment: [:]),
                         onOutput: { _ in }, completion: { _ in Issue.record("An unlaunched process completed") })
        Issue.record("A missing executable started")
    } catch {
        #expect(!runner.isRunning)
    }
    for _ in 0..<2 {
        var frames: [String] = []
        let result = try await reliabilityRun(runner, executable: fixture.executable) { frames.append($0.text) }
        try result.get()
        #expect(frames == ["only-this-attempt"])
        #expect(!runner.isRunning)
    }
}

@Test @MainActor func runnerForceStopsAnUnresponsiveCoreWithoutReportingSuccess() async throws {
    let fixture = try ReliabilityFixture(body: """
    trap '' TERM
    echo ready
    exec /bin/sleep 30
    """)
    defer { fixture.cleanup() }
    let runner = CrocRunner()
    let result = try await reliabilityRun(runner, executable: fixture.executable) { frame in
        if frame.text == "ready" { runner.cancel() }
    }
    #expect(!runner.isRunning)
    if case .success = result { Issue.record("A forcibly stopped core was reported as successful") }
}

@Test func invalidExplicitCorePathsNeverFallBackToAnotherInstallation() throws {
    let fixture = try ReliabilityFixture(body: "exit 0")
    defer { fixture.cleanup() }
    let missing = fixture.directory.appendingPathComponent("missing").path
    #expect(CrocExecutableLocator.locate(overridePath: missing,
        environment: ["CROC_EXECUTABLE": fixture.executable.path]) == nil)
    #expect(CrocExecutableLocator.locate(overridePath: "",
        environment: ["CROC_EXECUTABLE": missing]) == nil)
    #expect(CrocExecutableLocator.locate(overridePath: fixture.executable.path,
        environment: ["CROC_EXECUTABLE": missing]) == fixture.executable)
    #expect(CrocExecutableLocator.source(for: fixture.executable, overridePath: fixture.executable.path,
        environment: ["CROC_EXECUTABLE": fixture.executable.path]) == "Custom")
    #expect(CrocExecutableLocator.source(for: fixture.executable, overridePath: "",
        environment: ["CROC_EXECUTABLE": fixture.executable.path]) == "Environment")
}

@Test(arguments: [true, false])
func coreInspectionDrainsLargeOutputAndRetainsVersion(versionFirst: Bool) async throws {
    let fixture = try ReliabilityFixture(body: """
    \(versionFirst ? "echo 'croc version 10.7.0'" : "")
    /usr/bin/head -c 1048576 /dev/zero | /usr/bin/tr '\\000' x
    printf '\\n'
    \(versionFirst ? "" : "echo 'croc version 10.7.0'")
    """)
    defer { fixture.cleanup() }
    let info = await CrocCoreInspector.inspect(executable: fixture.executable, source: "Custom")
    #expect(info.state == .available)
    #expect(info.version == "10.7.0")
}

@Test(arguments: ["echo 'other program version 10.7.0'", "echo 'croc version 10.7.0'; exit 17", "kill -KILL $$"])
func coreInspectionPreservesUnrecognizedAndFailedResults(body: String) async throws {
    let fixture = try ReliabilityFixture(body: body)
    defer { fixture.cleanup() }
    let info = await CrocCoreInspector.inspect(executable: fixture.executable, source: "Custom")
    #expect(info.state == .unavailable)
    #expect(info.version == nil)
}

private func reliabilityProcessID(at url: URL) -> Int32? {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
}

@Test func coreInspectionTimeoutStopsItsProcess() async throws {
    let fixture = try ReliabilityFixture(body: "echo $$ > \"$0.pid\"; exec /bin/sleep 30")
    defer { fixture.cleanup() }
    let info = await CrocCoreInspector.inspect(executable: fixture.executable, source: "Custom", timeout: .milliseconds(150))
    #expect(info.state == .unavailable)
    let pid = try #require(reliabilityProcessID(at: URL(fileURLWithPath: fixture.executable.path + ".pid")))
    #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH)
}

@Test func cancellingCoreInspectionStopsItsProcess() async throws {
    let fixture = try ReliabilityFixture(body: "echo $$ > \"$0.pid\"; exec /bin/sleep 30")
    defer { fixture.cleanup() }
    let task = Task {
        await CrocCoreInspector.inspect(executable: fixture.executable, source: "Custom", timeout: .seconds(10))
    }
    let pidURL = URL(fileURLWithPath: fixture.executable.path + ".pid")
    let deadline = ContinuousClock.now + .seconds(2)
    while reliabilityProcessID(at: pidURL) == nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    task.cancel()
    let info = await task.value
    #expect(info.state == .unavailable)
    let pid = try #require(reliabilityProcessID(at: pidURL))
    #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH)
}
