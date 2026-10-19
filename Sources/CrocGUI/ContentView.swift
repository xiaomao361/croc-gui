import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TransferStore
    @State private var isDropTargeted = false
    @State private var showsSettings = false
    @FocusState private var receiveCodeFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    workspace
                        .frame(maxWidth: 600)
                        .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 48))
                        .padding(24)
                }
            }
            footer
        }
        .background(CrocPalette.canvas)
        .background(WindowLayoutConfigurator(preventsClosing: store.isBusy))
        .tint(CrocPalette.forestBright)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !store.isBusy {
                    Picker("Transfer mode", selection: Binding(
                        get: { store.mode }, set: { store.changeMode(to: $0) }
                    )) {
                        ForEach(TransferMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
            ToolbarItem {
                Button { showsSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .sheet(isPresented: $store.showDetails) { TransferDetailsView(store: store) }
        .sheet(isPresented: $showsSettings) { SettingsView(store: store) }
        .onChange(of: store.mode) { _, mode in
            receiveCodeFocused = mode == .receive
        }
        .onChange(of: store.phase) { _, phase in
            if phase == .idle && store.mode == .receive { receiveCodeFocused = true }
        }
    }

    @ViewBuilder
    private var workspace: some View {
        if store.phase.isTerminal {
            outcome
        } else if store.isBusy {
            activeTransfer
        } else if store.mode == .send {
            sendSetup
        } else {
            receiveSetup
        }
    }

    private var sendSetup: some View {
        VStack(spacing: 22) {
            if let item = store.selectedItem {
                Image(systemName: item.isDirectory ? "folder" : "doc.zipper")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(CrocPalette.forestBright)
                    .accessibilityHidden(true)
                fileIdentity(item)
                Button(action: store.beginSend) { Text("Send").frame(minWidth: 108) }
                    .buttonStyle(CrocButtonStyle(kind: .primary))
                    .disabled(!store.canBeginSend)
                    .keyboardShortcut(.defaultAction)
                Menu("Change selection") {
                    Button("Choose file…") { chooseTransferItem(folder: false) }
                        .keyboardShortcut("o", modifiers: .command)
                    Button("Choose folder…") { chooseTransferItem(folder: true) }
                        .keyboardShortcut("o", modifiers: [.command, .shift])
                    Divider()
                    Button("Remove selection", action: store.clearSelectedItem)
                }
                .fixedSize()
                .menuStyle(.borderlessButton)
                .foregroundStyle(CrocPalette.olive)
            } else {
                Image(systemName: "tray.and.arrow.up")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(CrocPalette.forestBright)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Drop a file or folder")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(CrocPalette.ink)
                    Text("Choose what to send. Then share a code.")
                        .font(.callout)
                        .foregroundStyle(CrocPalette.olive)
                }
                HStack(spacing: 10) {
                    Button("Choose file…") { chooseTransferItem(folder: false) }
                        .buttonStyle(CrocButtonStyle(kind: .primary))
                        .keyboardShortcut("o", modifiers: .command)
                    Button("Choose folder…") { chooseTransferItem(folder: true) }
                        .buttonStyle(CrocButtonStyle(kind: .secondary))
                        .keyboardShortcut("o", modifiers: [.command, .shift])
                }
            }
            if let notice = store.selectionNotice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(CrocPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            setupWarning
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(isDropTargeted ? CrocPalette.forestBright.opacity(0.05) : .clear)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDropTargeted ? CrocPalette.forestBright : .clear,
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .background {
            NativeFileDropTarget(isEnabled: !store.isBusy, isTargeted: $isDropTargeted,
                                 onDrop: store.acceptDrop)
        }
        .accessibilityHint("Accepts one file or folder at a time")
    }

    private var receiveSetup: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Receive a file")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(CrocPalette.ink)
                Text("Enter the code shared by the sender.")
                    .font(.callout)
                    .foregroundStyle(CrocPalette.olive)
            }
            TextField("8527-credit-tuna-radio", text: $store.receiveCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 19, design: .monospaced))
                .controlSize(.large)
                .focused($receiveCodeFocused)
                .accessibilityLabel("Receive code phrase")
                .disabled(store.isBusy)
                .onSubmit { if store.canBeginReceive { store.beginReceive() } }
            destinationRow
            HStack {
                Button(action: store.beginReceive) { Text("Receive").frame(minWidth: 108) }
                    .buttonStyle(CrocButtonStyle(kind: .primary))
                    .disabled(!store.canBeginReceive)
                    .keyboardShortcut(.defaultAction)
                Spacer()
            }
            setupWarning
        }
        .frame(maxWidth: 440)
    }

    private var destinationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(CrocPalette.olive)
            VStack(alignment: .leading, spacing: 3) {
                Text("Save to").font(.caption).foregroundStyle(CrocPalette.olive)
                Text(store.outputDirectory.abbreviatedDirectoryPath)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(store.outputDirectory.path)
            }
            Spacer(minLength: 8)
            Button("Change…") { chooseOutputDirectory() }
                .buttonStyle(.borderless)
                .disabled(store.isBusy)
        }
    }

    private var activeTransfer: some View {
        VStack(spacing: store.phase == .waiting ? 16 : 22) {
            taskIdentity
            VStack(spacing: 14) {
                Text(store.statusTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(CrocPalette.olive)

                if store.phase == .cancelling {
                    ProgressView().controlSize(.regular)
                        .padding(.vertical, 20)
                        .accessibilityLabel(store.statusTitle)
                    Text("Waiting for croc to stop safely.")
                        .font(.callout)
                        .foregroundStyle(CrocPalette.olive)
                } else if store.phase == .waiting && !store.codePhrase.isEmpty {
                    Text(store.codePhrase)
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(CrocPalette.ink)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .help(store.codePhrase)
                    CopyFeedbackButton("Copy code", kind: .primary, action: store.copyCode)
                } else if let progress = store.progress {
                    if store.isFileProgress {
                        Text(store.currentFileName.map { "Current file: \($0)" } ?? "Current file progress")
                            .font(.caption)
                            .foregroundStyle(CrocPalette.olive)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(store.currentFileName ?? "Current file progress")
                    }
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 60, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(CrocPalette.ink)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: progress)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 320)
                        .accessibilityLabel(store.isFileProgress ? "Current file progress" : store.statusTitle)
                    if progress >= 1 {
                        Text(store.isFileProgress ? "Current file finished — waiting for croc." : "Waiting for croc to continue.")
                            .font(.callout).foregroundStyle(CrocPalette.olive)
                    } else if let remaining = store.progressSnapshot?.remainingTime, !remaining.isEmpty {
                        Text(store.isFileProgress ? "Estimated remaining for this file: \(remaining)" : "Estimated remaining for this step: \(remaining)")
                            .font(.callout).foregroundStyle(CrocPalette.olive)
                    }
                    if let snapshot = store.progressSnapshot {
                        Text([snapshot.byteSummary, snapshot.speed].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(CrocPalette.olive)
                    }
                } else {
                    ProgressView().controlSize(.regular)
                        .padding(.vertical, 20)
                        .accessibilityLabel(store.statusTitle)
                    Text("Connecting and preparing the transfer…")
                        .font(.callout)
                        .foregroundStyle(CrocPalette.olive)
                }
            }
            .frame(maxWidth: .infinity, minHeight: store.phase == .waiting ? 0 : 172)

            if store.phase == .waiting && !store.codePhrase.isEmpty {
                terminalInstructions.frame(maxWidth: 440)
            }
            if let inactivityNotice = store.inactivityNotice {
                Label(inactivityNotice, systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(CrocPalette.olive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var taskIdentity: some View {
        if let item = store.displayedItem, (store.transferContext?.mode ?? store.mode) == .send {
            fileIdentity(item)
        } else {
            VStack(spacing: 4) {
                Text(store.receivedItemSummary ?? "File details unavailable")
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(store.receivedItemSummary ?? "croc has not provided the file details.")
                Text("To \(store.displayedOutputDirectory.abbreviatedDirectoryPath)")
                    .font(.caption).foregroundStyle(CrocPalette.olive)
                    .lineLimit(1).truncationMode(.middle)
                    .help(store.displayedOutputDirectory.path)
            }
        }
    }

    private func fileIdentity(_ item: SelectedTransferItem) -> some View {
        VStack(spacing: 5) {
            Text(item.name)
                .font(.callout.weight(.medium))
                .foregroundStyle(CrocPalette.ink)
                .lineLimit(1).truncationMode(.middle)
                .help(item.url.path)
            Text(item.isDirectory ? "Folder · \(item.parentPath)" : "\(item.byteCount?.fileSizeLabel ?? "Size unavailable") · \(item.parentPath)")
                .font(.caption)
                .foregroundStyle(CrocPalette.olive)
                .lineLimit(1).truncationMode(.middle)
                .help(item.url.path)
        }
    }

    private var terminalInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let command = store.unixReceiveCommand {
                commandRow(platform: "macOS / Linux", command: command, copy: store.copyUnixCommand)
            }
            if let command = store.windowsReceiveCommand {
                commandRow(platform: "Windows (PowerShell)", command: command, copy: store.copyWindowsCommand)
            }
            if let relay = store.transferContext?.relay, !relay.isEmpty {
                Text("Both devices must use the same relay: \(relay)")
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(CrocPalette.olive)
        .padding(12)
        .background(CrocPalette.chrome, in: .rect(cornerRadius: 8))
    }

    private func commandRow(platform: String, command: String, copy: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(platform).font(.caption.weight(.medium))
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(command)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CopyFeedbackButton("Copy", kind: .secondary, action: copy)
                .accessibilityLabel("Copy \(platform) command")
        }
    }

    private var outcome: some View {
        VStack(spacing: 20) {
            taskIdentity
            Image(systemName: store.phase.menuBarSymbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(outcomeColor)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(store.statusTitle)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(CrocPalette.ink)
                Text(store.statusDetail)
                    .font(.callout)
                    .foregroundStyle(CrocPalette.olive)
                    .fixedSize(horizontal: false, vertical: true)
                if let location = store.completionLocationDetail {
                    Text(location).font(.callout).foregroundStyle(CrocPalette.olive)
                        .textSelection(.enabled)
                }
            }
            .multilineTextAlignment(.center)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { outcomeActions }
                VStack(spacing: 10) { outcomeActions }
            }
        }
    }

    @ViewBuilder
    private var outcomeActions: some View {
        if store.phase == .completed {
            Button(store.transferContext?.mode == .receive ? "Open folder" : "Show in Finder", action: store.revealCompletionLocation)
                .buttonStyle(CrocButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            Button("New transfer", action: store.prepareNewTransfer)
                .buttonStyle(CrocButtonStyle(kind: .secondary))
        } else {
            if case .failed = store.phase {
                switch store.failureRecovery {
                case .chooseDestination:
                    Button("Change save folder…") { chooseOutputDirectory() }
                        .buttonStyle(CrocButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                case .settings:
                    Button("Check settings…") { showsSettings = true }
                        .buttonStyle(CrocButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                    Button("Try again", action: retry)
                        .buttonStyle(CrocButtonStyle(kind: .secondary))
                case .editCode:
                    Button("Edit code", action: store.editTransfer)
                        .buttonStyle(CrocButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                case .retry:
                    Button("Try again", action: retry)
                        .buttonStyle(CrocButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Button("Try again", action: retry)
                    .buttonStyle(CrocButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            if store.failureRecovery != .editCode {
                Button(store.mode == .receive ? "Edit details" : "Change selection", action: store.editTransfer)
                    .buttonStyle(CrocButtonStyle(kind: .secondary))
            }
        }
    }

    private var outcomeColor: Color {
        switch store.phase {
        case .failed: CrocPalette.danger
        case .cancelled: CrocPalette.olive
        default: CrocPalette.forestBright
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("End-to-end encrypted")
                .font(.caption)
                .foregroundStyle(CrocPalette.olive)
            Spacer(minLength: 8)
            Button("Details") { store.showDetails = true }
                .disabled(store.logLines.isEmpty)
                .buttonStyle(.borderless)
            if store.isBusy {
                Button(store.phase == .cancelling ? "Cancelling…" : "Cancel", action: store.cancel)
                    .disabled(store.phase == .cancelling)
                    .buttonStyle(.borderless)
            }
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .frame(height: 44)
        .background(CrocPalette.chrome)
    }

    @ViewBuilder
    private var setupWarning: some View {
        if let message = setupBlockingMessage {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if store.coreInfo.state == .checking {
                        ProgressView().controlSize(.small)
                    }
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(store.coreInfo.state == .checking ? CrocPalette.olive : CrocPalette.danger)
                        .multilineTextAlignment(.center)
                }
                if store.coreInfo.state != .checking {
                    Button("Open settings…") { showsSettings = true }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var setupBlockingMessage: String? {
        if !store.isCoreReady { return store.coreReadinessMessage }
        if !store.isRelayConfigurationValid { return "Enter a custom relay address in Settings." }
        return nil
    }

    private func retry() {
        store.mode == .send ? store.beginSend() : store.beginReceive()
    }

    private func chooseTransferItem(folder: Bool) {
        guard !store.isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folder
        panel.canChooseDirectories = folder
        panel.allowsMultipleSelection = false
        panel.prompt = folder ? "Choose folder" : "Choose file"
        if panel.runModal() == .OK, let url = panel.url { store.select(url) }
    }

    private func chooseOutputDirectory() {
        guard !store.isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.outputDirectory
        panel.prompt = "Save Here"
        if panel.runModal() == .OK, let url = panel.url {
            store.setOutputDirectory(url)
            if store.phase.isTerminal { store.editTransfer() }
        }
    }
}

private struct CopyFeedbackButton: View {
    let title: String
    let kind: CrocButtonKind
    let action: () -> Void
    @State private var isCopied = false
    @State private var resetTask: Task<Void, Never>?

    init(_ title: String, kind: CrocButtonKind, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.action = action
    }

    var body: some View {
        Button {
            action()
            isCopied = true
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                isCopied = false
            }
        } label: {
            Label(isCopied ? "Copied" : title, systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .frame(minWidth: kind == .primary ? 108 : 44)
        }
        .buttonStyle(CrocButtonStyle(kind: isCopied ? .success : kind))
        .accessibilityLabel(isCopied ? "Copied" : title)
        .onDisappear { resetTask?.cancel() }
    }
}
