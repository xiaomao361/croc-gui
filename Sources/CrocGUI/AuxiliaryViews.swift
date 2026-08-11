import AppKit
import SwiftUI

struct TransferDetailsView: View {
    @ObservedObject var store: TransferStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transfer Details").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CrocButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }

            HStack {
                Label(store.statusTitle, systemImage: store.phase.menuBarSymbol)
                Spacer()
                if store.phase.isRunning {
                    Button { store.cancel() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(CrocButtonStyle(kind: .destructive))
                }
            }

            ScrollView {
                Text(store.logLines.isEmpty ? "No transfer log yet." : store.logLines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))

            Text("Secrets are passed through the environment and are not printed in this log.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 440)
    }
}

struct SettingsView: View {
    @ObservedObject var store: TransferStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                    Text("Changes are saved automatically and apply to the next transfer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(CrocButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }

            Form {
                Section("Relay") {
                    Picker("Connection", selection: $store.useCustomRelay) {
                        Text("Use croc default relay").tag(false)
                        Text("Use a custom relay").tag(true)
                    }
                    .pickerStyle(.radioGroup)

                    if store.useCustomRelay {
                        LabeledContent("Relay address") {
                            TextField("relay.example.com:9009", text: $store.relay)
                                .frame(minWidth: 280)
                        }

                        if store.configuredRelay.isEmpty {
                            Label("Enter a relay address before starting a transfer.", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(CrocPalette.danger)
                        } else {
                            Label("Custom relay saved", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(CrocPalette.forestBright)
                        }
                    } else {
                        Text("croc will choose its built-in public relay.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("croc CLI") {
                    HStack {
                        TextField("Automatically detected", text: $store.executableOverride)
                        Button("Choose…") { chooseExecutable() }
                            .buttonStyle(CrocButtonStyle(kind: .secondary))
                    }
                    Text(store.executableURL?.path ?? "No executable found")
                        .font(.caption)
                        .foregroundStyle(store.executableURL == nil ? CrocPalette.danger : .secondary)
                        .textSelection(.enabled)
                }

                Section("Original croc project") {
                    Text("This app is an independent macOS GUI. Its file-transfer core and bundled command-line program are croc, created by Zack (schollz). This is not the official croc app.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Link(destination: URL(string: "https://github.com/schollz/croc")!) {
                            Label("View croc on GitHub", systemImage: "link")
                        }
                        .buttonStyle(CrocButtonStyle(kind: .secondary))

                        Link(destination: URL(string: "https://getcroc.com/")!) {
                            Label("Visit getcroc.com", systemImage: "globe")
                        }
                        .buttonStyle(CrocButtonStyle(kind: .secondary))

                        Link(destination: URL(string: "https://github.com/schollz/croc/blob/main/LICENSE")!) {
                            Label("Read the MIT license", systemImage: "doc.text")
                        }
                        .buttonStyle(CrocButtonStyle(kind: .secondary))
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(22)
        .frame(minWidth: 600, minHeight: 430)
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose croc"
        if panel.runModal() == .OK, let url = panel.url {
            store.executableOverride = url.path
        }
    }
}
