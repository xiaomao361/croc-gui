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

            if store.phase == .cancelling {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(store.statusTitle)
            } else if let progress = store.progress, store.phase.isRunning {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(CrocPalette.forestBright)
                    .accessibilityLabel(store.isFileProgress ? "Current file progress" : store.statusTitle)
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }

            TransferLogView(lines: store.logLines)
                .equatable()
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

private struct TransferLogView: View, Equatable {
    let lines: [String]
    @State private var followsLatestOutput = true
    @State private var previousContentFrame: CGRect?
    private let bottomID = "transfer-log-bottom"
    private let coordinateSpace = "transfer-log-viewport"

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.lines == rhs.lines
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TransferLogText(lines: lines)
                            .equatable()
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(
                                key: LogContentFrameKey.self,
                                value: content.frame(in: .named(coordinateSpace))
                            )
                        }
                    }
                }
                .coordinateSpace(name: coordinateSpace)
                .onPreferenceChange(LogContentFrameKey.self) { frame in
                    guard frame.height > 0 else { return }
                    let bottomIsVisible = frame.maxY <= viewport.size.height + 2
                    let contentHeightChanged = previousContentFrame.map { abs(frame.height - $0.height) > 0.5 } ?? true
                    let movedUp = previousContentFrame.map { frame.minY > $0.minY + 0.5 } ?? false

                    if bottomIsVisible {
                        followsLatestOutput = true
                    } else if movedUp {
                        // A scroll toward earlier output wins even when new output arrives.
                        followsLatestOutput = false
                    } else if followsLatestOutput && contentHeightChanged {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                    previousContentFrame = frame
                }
                .onChange(of: viewport.size.height) { _, _ in
                    if followsLatestOutput { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
                .onChange(of: lines.isEmpty) { _, isEmpty in
                    if isEmpty {
                        followsLatestOutput = true
                        previousContentFrame = nil
                    }
                }
            }
        }
    }
}

private struct TransferLogText: View, Equatable {
    let lines: [String]

    var body: some View {
        Text(lines.isEmpty ? "No transfer log yet." : lines.joined(separator: "\n"))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
    }
}

private struct LogContentFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
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

                    VStack(alignment: .leading, spacing: 8) {
                        if store.coreInfo.state != .checking, let message = store.coreReadinessMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(CrocPalette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Check again", action: store.refreshCoreInfo)
                            .buttonStyle(CrocButtonStyle(kind: .secondary))
                            .disabled(store.coreInfo.state == .checking && store.coreInfo.path == store.executableURL?.path)
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
