import Foundation
import Testing
@testable import CrocGUI

@Test func sendCommandUsesDefaultRelayWhenBlank() {
    let command = CrocCommandBuilder.send(
        item: URL(fileURLWithPath: "/tmp/sample.zip"),
        relay: "  "
    )
    #expect(command.arguments == ["--disable-clipboard", "send", "/tmp/sample.zip"])
    #expect(command.environment.isEmpty)
}

@Test func receiveCommandKeepsSecretOutOfArguments() {
    let command = CrocCommandBuilder.receive(
        code: "copper-lake-seven",
        output: URL(fileURLWithPath: "/tmp/inbox"),
        relay: "relay.example.com:9009"
    )
    #expect(command.arguments == ["--relay", "relay.example.com:9009", "--yes", "--out", "/tmp/inbox"])
    #expect(command.environment["CROC_SECRET"] == "copper-lake-seven")
    #expect(!command.arguments.contains("copper-lake-seven"))
}

@Test func parserExtractsCodeAndProgress() {
    #expect(CrocOutputParser.codePhrase(in: "Code is: copper-lake-seven") == "copper-lake-seven")
    #expect(CrocOutputParser.codePhrase(in: "Code is: 2060-printer-vampire-flood") == "2060-printer-vampire-flood")
    #expect(CrocOutputParser.progress(in: "Sending 42%") == 0.42)
}

@Test func parserRemovesAnsiSequences() {
    let line = "\u{001B}[32mCode is: apple-river-blue\u{001B}[0m"
    #expect(CrocOutputParser.codePhrase(in: line) == "apple-river-blue")
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

@Test @MainActor func cancellingClearsTransientHandoffState() {
    let suiteName = "CrocGUITests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = TransferStore(defaults: defaults)
    store.phase = .waiting
    store.codePhrase = "8527-credit-tuna-radio"
    store.progress = 0.3
    store.clipboardNotice = "Code copied to clipboard!"

    store.cancel()

    #expect(store.phase == .cancelled)
    #expect(store.codePhrase.isEmpty)
    #expect(store.progress == nil)
    #expect(store.clipboardNotice == nil)
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
