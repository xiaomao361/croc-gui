import Foundation

enum TransferMode: String, CaseIterable, Identifiable {
    case send
    case receive

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum TransferPhase: Equatable {
    case idle
    case preparing
    case waiting
    case transferring
    case cancelling
    case completed
    case cancelled
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .preparing, .waiting, .transferring, .cancelling: true
        default: false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed: true
        default: false
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .preparing: "ellipsis.circle"
        case .waiting: "hourglass.circle"
        case .transferring: "arrow.left.arrow.right.circle.fill"
        case .cancelling: "xmark.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "arrow.left.arrow.right.circle"
        }
    }
}

struct SelectedTransferItem: Equatable {
    let url: URL
    let isDirectory: Bool
    let byteCount: Int64?
    let modifiedAt: Date?

    var name: String { url.lastPathComponent }
    var parentPath: String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    static func inspect(_ url: URL) -> SelectedTransferItem {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let values = try? url.resourceValues(forKeys: keys)
        return SelectedTransferItem(
            url: url,
            isDirectory: values?.isDirectory ?? false,
            byteCount: values?.fileSize.map(Int64.init),
            modifiedAt: values?.contentModificationDate
        )
    }
}

struct CrocCommand: Equatable {
    let arguments: [String]
    let environment: [String: String]
}

struct CrocTransferProgress: Equatable, Sendable {
    let fraction: Double
    let byteSummary: String?
    let speed: String?
    let remainingTime: String?

    var detailLabel: String {
        var parts = ["\(Int(fraction * 100))%"]
        if let byteSummary { parts.append(byteSummary) }
        if let speed { parts.append(speed) }
        if let remainingTime { parts.append("ETA \(remainingTime)") }
        return parts.joined(separator: " · ")
    }
}

struct CrocCoreInfo: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case checking
        case available
        case unavailable
    }

    let state: State
    let version: String?
    let source: String
    let path: String?

    var displayLabel: String {
        switch state {
        case .checking: "Checking version…"
        case .available: "croc \(version ?? "unknown") · \(source)"
        case .unavailable: "Version unavailable · \(source)"
        }
    }

    var logLabel: String {
        switch state {
        case .available: "croc core \(version ?? "unknown") · \(source.lowercased())"
        case .checking: "croc core version pending · \(source.lowercased())"
        case .unavailable: "croc core version unavailable · \(source.lowercased())"
        }
    }
}

enum CrocFailureExplainer {
    static func message(logLines: [String], fallback: String) -> String {
        let recentOutput = logLines.suffix(24).joined(separator: "\n").lowercased()

        if recentOutput.contains("secure channel") &&
            (recentOutput.contains("not ready") || recentOutput.contains("peer disconnected")) {
            return "The secure channel could not be established. Confirm the other computer is still waiting and uses a compatible croc version, then try again."
        }

        if recentOutput.contains("connection refused") ||
            recentOutput.contains("could not connect") ||
            recentOutput.contains("unable to connect") {
            return "The relay could not be reached. Check the network and relay settings, then try again."
        }

        if recentOutput.contains("read-only file system") {
            return "croc could not write to the selected location. Choose a writable folder, then try again."
        }

        return fallback
    }
}

enum CrocCoreInspector {
    static func inspect(executable: URL, source: String) -> CrocCoreInfo {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0,
                  let version = CrocOutputParser.coreVersion(in: output) else {
                return CrocCoreInfo(state: .unavailable, version: nil, source: source, path: executable.path)
            }
            return CrocCoreInfo(state: .available, version: version, source: source, path: executable.path)
        } catch {
            return CrocCoreInfo(state: .unavailable, version: nil, source: source, path: executable.path)
        }
    }
}

enum CrocCommandBuilder {
    static func send(item: URL, relay: String) -> CrocCommand {
        var arguments = relayArguments(relay)
        arguments += ["--ignore-stdin", "--disable-clipboard", "send", item.path]
        return CrocCommand(arguments: arguments, environment: [:])
    }

    static func receive(code: String, output: URL, relay: String) -> CrocCommand {
        var arguments = relayArguments(relay)
        arguments += ["--ignore-stdin", "--yes", "--out", output.path]
        return CrocCommand(arguments: arguments, environment: ["CROC_SECRET": code])
    }

    private static func relayArguments(_ relay: String) -> [String] {
        let trimmed = relay.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : ["--relay", trimmed]
    }
}

enum CrocOutputParser {
    static func sanitized(_ line: String) -> String {
        line.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }

    static func codePhrase(in line: String) -> String? {
        firstCapture(in: sanitized(line), pattern: #"Code is:\s*(\S+)"#)
    }

    static func progress(in line: String) -> Double? {
        progressSnapshot(in: line)?.fraction
    }

    static func progressSnapshot(in line: String) -> CrocTransferProgress? {
        let clean = sanitized(line)
        guard let raw = firstCapture(in: clean, pattern: #"\b(\d{1,3})%"#),
              let percent = Double(raw) else { return nil }

        let metrics = firstCapture(in: clean, pattern: #"\b\d{1,3}%.*?\(([^()]*)\)"#)?
            .split(separator: ",", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let timing = firstCapture(in: clean, pattern: #"\b\d{1,3}%.*?\[([^\]]+)\]"#)
        let remaining = timing.flatMap { value -> String? in
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count > 1 else { return nil }
            return String(parts.last!).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let firstMetric = metrics?.first
        let hasOnlySpeed = metrics?.count == 1 && firstMetric?.hasSuffix("/s") == true

        return CrocTransferProgress(
            fraction: min(max(percent / 100, 0), 1),
            byteSummary: hasOnlySpeed ? nil : firstMetric,
            speed: hasOnlySpeed ? firstMetric : (metrics?.count == 2 ? metrics?[1] : nil),
            remainingTime: remaining
        )
    }

    static func coreVersion(in output: String) -> String? {
        firstCapture(in: output, pattern: #"\b(?:version\s+)?v?(\d+\.\d+\.\d+(?:[-+][^\s]+)?)\b"#)
    }

    private static func firstCapture(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }
}

extension Int64 {
    var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Date {
    var transferLabel: String {
        formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

extension TimeInterval {
    var durationLabel: String {
        let totalSeconds = max(0, Int(self.rounded()))
        if totalSeconds < 60 { return "\(totalSeconds)s" }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 { return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }
}

extension URL {
    var abbreviatedDirectoryPath: String {
        let abbreviated = (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        return abbreviated.hasSuffix("/") ? abbreviated : "\(abbreviated)/"
    }
}
