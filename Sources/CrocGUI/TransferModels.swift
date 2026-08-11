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
    case completed
    case cancelled
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .preparing, .waiting, .transferring: true
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

enum CrocCommandBuilder {
    static func send(item: URL, relay: String) -> CrocCommand {
        var arguments = relayArguments(relay)
        arguments += ["--disable-clipboard", "send", item.path]
        return CrocCommand(arguments: arguments, environment: [:])
    }

    static func receive(code: String, output: URL, relay: String) -> CrocCommand {
        var arguments = relayArguments(relay)
        arguments += ["--yes", "--out", output.path]
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
        guard let raw = firstCapture(in: sanitized(line), pattern: #"\b(\d{1,3})%"#),
              let percent = Double(raw) else { return nil }
        return min(max(percent / 100, 0), 1)
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

extension URL {
    var abbreviatedDirectoryPath: String {
        let abbreviated = (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        return abbreviated.hasSuffix("/") ? abbreviated : "\(abbreviated)/"
    }
}
