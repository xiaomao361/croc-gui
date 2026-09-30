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
                    .keyboardShortcut(.cancelAction)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label(store.statusTitle, systemImage: store.phase.menuBarSymbol)
                    Text(store.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if store.phase.isRunning, store.phase != .cancelling {
                    Button { store.cancel() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(CrocButtonStyle(kind: .destructive))
                }
            }

            if let progress = store.progress, store.phase.isRunning {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(store.phase == .cancelling ? Color.secondary : CrocPalette.forestBright)
                    .accessibilityLabel(store.statusTitle)
                    .accessibilityValue("\(Int(progress * 100)) percent")
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

            Text("The received code is omitted from command arguments. Core output may include the sender's code; review before sharing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(minWidth: 520, minHeight: 400)
    }
}

struct SettingsView: View {
    @ObservedObject var store: TransferStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var relayAddressFocused: Bool

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
                    .keyboardShortcut(.cancelAction)
            }

            Form {
                Section("Relay") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection")
                        Picker("Connection", selection: $store.useCustomRelay) {
                            Text("Use croc default relay").tag(false)
                            Text("Use a custom relay").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }

                    if store.useCustomRelay {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Relay address")
                            TextField("Relay address", text: $store.relay,
                                      prompt: Text("relay.example.com:9009"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Relay address")
                                .focused($relayAddressFocused)
                            Text("Use the same relay address on both computers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    settingsValueRow(label: "Core version") {
                        Text(store.coreInfo.displayLabel)
                            .foregroundStyle(store.coreInfo.state == .unavailable ? CrocPalette.danger : .secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                    }

                    settingsValueRow(label: "App version") {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Executable")
                                    .font(.body)
                                Text(store.executableOverride.isEmpty ? "Selected automatically" : "Custom executable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 16)

                            if !store.executableOverride.isEmpty {
                                Button("Use automatic") { store.executableOverride = "" }
                                    .buttonStyle(CrocButtonStyle(kind: .secondary))
                                    .fixedSize()
                            }

                            Button("Choose…") { chooseExecutable() }
                                .buttonStyle(CrocButtonStyle(kind: .secondary))
                                .fixedSize()
                        }

                        Text(store.executableURL?.path ?? "No executable found")
                            .font(.caption.monospaced())
                            .foregroundStyle(store.executableURL == nil ? CrocPalette.danger : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(store.executableURL?.path ?? "No executable found")
                    }
                }

                Section("Original croc project") {
                    Text("This app is an independent macOS GUI. Its file-transfer core and bundled command-line program are croc, created by Zack (schollz). This is not the official croc app.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { projectLinks }
                        VStack(alignment: .leading, spacing: 10) { projectLinks }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(22)
        .frame(width: 520, height: 520)
        .onChange(of: store.useCustomRelay) { _, useCustomRelay in
            relayAddressFocused = useCustomRelay
        }
    }

    private var projectLinks: some View {
        Group {
            Link(destination: URL(string: "https://github.com/schollz/croc")!) {
                Label("croc GitHub", systemImage: "link")
            }
            Link(destination: URL(string: "https://getcroc.com/")!) {
                Label("croc website", systemImage: "globe")
            }
            Link(destination: URL(string: "https://github.com/schollz/croc/blob/main/LICENSE")!) {
                Label("MIT license", systemImage: "doc.text")
            }
        }
        .buttonStyle(CrocButtonStyle(kind: .secondary))
        .fixedSize()
    }

    private func settingsValueRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 16) {
            Text(label)
            Spacer(minLength: 24)
            content()
        }
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
