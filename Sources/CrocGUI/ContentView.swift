import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TransferStore
    @State private var isDropTargeted = false
    @State private var showsSettings = false

    var body: some View {
        VStack(spacing: 0) {
            commandToolbar

            transferWorkspace

            statusFooter
        }
        .background(CrocPalette.canvas)
        .background(WindowLayoutConfigurator(preventsClosing: store.phase.isRunning))
        .tint(CrocPalette.forestBright)
        .onAppear { NSApp.activate() }
        .sheet(isPresented: $store.showDetails) {
            TransferDetailsView(store: store)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(store: store)
        }
    }

    @ViewBuilder
    private var transferWorkspace: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if store.mode == .send {
                        sendBody(expandedHeight: max(240, geometry.size.height - 48))
                    } else {
                        receiveBody(expandedHeight: max(240, geometry.size.height - 48))
                    }
                }
                    .frame(maxWidth: 860)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var commandToolbar: some View {
        HStack(spacing: 12) {
            modeSwitcher

            Spacer(minLength: 24)

            Button {
                showsSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(CrocButtonStyle(kind: .secondary))

            Button {
                store.showDetails = true
            } label: {
                Label("Details", systemImage: "text.alignleft")
            }
            .buttonStyle(CrocButtonStyle(kind: .secondary))
            .disabled(store.logLines.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(CrocPalette.canvas)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(TransferMode.allCases) { mode in
                Button {
                    store.changeMode(to: mode)
                } label: {
                    Label(mode.title, systemImage: mode == .send ? "paperplane" : "tray.and.arrow.down")
                        .frame(minWidth: 92)
                }
                .buttonStyle(CrocButtonStyle(kind: .mode(selected: store.mode == mode)))
                .disabled(store.phase.isRunning)
                .accessibilityLabel("\(mode.title) mode")
                .accessibilityAddTraits(store.mode == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(CrocPalette.chrome)
        .clipShape(.rect(cornerRadius: 11))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transfer mode")
    }

    private func sendBody(expandedHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            selectedTransferCard(expandedHeight: store.selectedItem == nil && !store.phase.isTerminal ? expandedHeight : nil)

            if store.phase.isTerminal {
                terminalOutcomeCard
            } else if store.codePhrase.isEmpty, store.selectedItem != nil {
                sendSetupCard
            } else {
                if !store.codePhrase.isEmpty {
                    handoffCard
                }
            }
        }
    }

    private func selectedTransferCard(expandedHeight: CGFloat? = nil) -> some View {
        let isEmpty = store.selectedItem == nil

        return VStack(alignment: .leading, spacing: 18) {
            if let item = store.selectedItem {
                HStack(spacing: 18) {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(CrocPalette.forestMuted)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.07))
                        .clipShape(.rect(cornerRadius: 11))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.isDirectory ? "Folder selected" : "File selected")
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(CrocPalette.forestMuted)

                        Text(item.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(item.name)
                        Text(itemMetadata(item))
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.62))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(itemMetadata(item))
                    }

                    Spacer(minLength: 16)

                    if !store.phase.isRunning {
                        Button {
                            store.clearSelectedItem()
                        } label: {
                            Label("Remove", systemImage: "xmark")
                        }
                        .buttonStyle(CrocButtonStyle(kind: .destructiveFilled))
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 18) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(CrocPalette.forestBright)
                        .frame(width: 58, height: 58)
                        .background(CrocPalette.forestBright.opacity(0.09))
                        .clipShape(.rect(cornerRadius: 13))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Drop a file or folder here")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(CrocPalette.ink)
                        Text("Folders are sent directly with their structure intact.")
                            .font(.callout)
                            .foregroundStyle(CrocPalette.olive)
                    }
                }
            }

            if store.phase.isRunning {
                Label("File selection is locked during transfer", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.72))
            } else {
                HStack(spacing: 12) {
                    Button {
                        chooseTransferFolder()
                    } label: {
                        Label(store.selectedItem == nil ? "Choose folder" : "Choose another folder", systemImage: "folder.fill")
                    }
                    .buttonStyle(CrocButtonStyle(kind: .primary))
                    .keyboardShortcut("o", modifiers: [.command, .shift])

                    Button {
                        chooseTransferFile()
                    } label: {
                        Label(store.selectedItem == nil ? "Choose file" : "Choose another file", systemImage: "doc")
                    }
                    .buttonStyle(CrocButtonStyle(kind: .secondary))
                    .keyboardShortcut("o", modifiers: .command)

                    Spacer()

                    Label("Drag and drop supported", systemImage: "arrow.down.to.line")
                        .font(.caption)
                        .foregroundStyle(isEmpty ? CrocPalette.olive : Color.white.opacity(0.62))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: expandedHeight, alignment: .center)
        .background(isEmpty ? CrocPalette.cream : CrocPalette.forest)
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isDropTargeted
                        ? CrocPalette.forestBright
                        : (isEmpty ? CrocPalette.forestBright.opacity(0.32) : .clear),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 3 : 1.5, dash: isEmpty ? [8, 6] : [])
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .background {
            NativeFileDropTarget(isEnabled: !store.phase.isRunning, isTargeted: $isDropTargeted) { url in
                store.select(url)
            }
        }
        .accessibilityHint("Accepts a dropped file or folder")
    }

    private var sendSetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Private handoff", systemImage: "lock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CrocPalette.olive)

            Text("Ready to start the transfer")
                .font(.title.weight(.bold))
                .foregroundStyle(CrocPalette.ink)

            Text("Starting croc creates the code phrase and waits for the receiver. Nothing is uploaded to cloud storage.")
                .font(.body)
                .foregroundStyle(CrocPalette.olive)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    store.beginSend()
                } label: {
                    Label("Start transfer", systemImage: "paperplane.fill")
                }
                .buttonStyle(CrocButtonStyle(kind: .primary))
                .disabled(store.executableURL == nil || !store.isRelayConfigurationValid)
                .keyboardShortcut(.defaultAction)

                if setupBlockingMessage != nil {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Open settings", systemImage: "gearshape")
                    }
                    .buttonStyle(CrocButtonStyle(kind: .secondary))
                }
            }

            if let setupBlockingMessage {
                Label(setupBlockingMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(CrocPalette.danger)
            }
        }
        .surfaceCard()
    }

    private var handoffCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Label("Code phrase", systemImage: "key.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CrocPalette.olive)
                Spacer()
                Text(store.statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(store.codePhrase)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(CrocPalette.ink)
                .textSelection(.enabled)
                .minimumScaleFactor(0.64)
                .lineLimit(1)
                .help(store.codePhrase)

            HStack(spacing: 12) {
                CopyFeedbackButton("Copy code phrase", kind: .primary, action: store.copyCode)

                if let notice = store.clipboardNotice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(CrocPalette.forestBright)
                        .accessibilityLabel(notice)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }

            Text("Send the phrase to the receiver, or copy one of the commands below if they use croc in a terminal.")
                .font(.callout)
                .foregroundStyle(CrocPalette.olive)

            cliInstructions
        }
        .surfaceCard()
    }

    private var cliInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("COMMAND LINE RECEIVER")
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(CrocPalette.olive)
                Spacer()
                CopyFeedbackButton("Copy all", kind: .secondary, action: store.copyReceiveInstructions)
            }

            if let command = store.windowsReceiveCommand {
                commandRow(platform: "Windows", command: command, copy: store.copyWindowsCommand)
            }
            if let command = store.unixReceiveCommand {
                commandRow(platform: "Linux / macOS", command: command, copy: store.copyUnixCommand)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.52))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func commandRow(platform: String, command: String, copy: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(platform)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(command)
            }
            Spacer(minLength: 12)
            CopyFeedbackButton("Copy", kind: .secondary, action: copy)
        }
        .padding(12)
        .background(Color.white.opacity(0.68))
        .clipShape(.rect(cornerRadius: 9))
    }

    private func receiveBody(expandedHeight: CGFloat) -> some View {
        Group {
            if store.phase.isTerminal {
                terminalOutcomeCard
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Receive securely", systemImage: "tray.and.arrow.down.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CrocPalette.olive)

                    Text("Enter the sender's code phrase")
                        .font(.title.weight(.bold))
                        .foregroundStyle(CrocPalette.ink)

                    Text("The sender keeps the content until this Mac connects with the correct phrase.")
                        .font(.body)
                        .foregroundStyle(CrocPalette.olive)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Code phrase")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CrocPalette.olive)
                        TextField("8527-credit-tuna-radio", text: $store.receiveCode)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3.monospaced())
                            .accessibilityLabel("Receive code phrase")
                            .onSubmit {
                                if canBeginReceive {
                                    store.beginReceive()
                                }
                            }
                    }

                    HStack(spacing: 14) {
                        Image(systemName: "folder")
                            .foregroundStyle(CrocPalette.forestBright)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Save received files to")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(store.outputDirectory.abbreviatedDirectoryPath)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(store.outputDirectory.path)
                        }
                        Spacer()
                        Button("Change…") { chooseOutputDirectory() }
                            .buttonStyle(CrocButtonStyle(kind: .secondary))
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.52))
                    .clipShape(.rect(cornerRadius: 12))

                    HStack(spacing: 12) {
                        Button {
                            store.beginReceive()
                        } label: {
                            Label("Receive", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(CrocButtonStyle(kind: .primary))
                        .disabled(!canBeginReceive)

                        if setupBlockingMessage != nil {
                            Button {
                                showsSettings = true
                            } label: {
                                Label("Open settings", systemImage: "gearshape")
                            }
                            .buttonStyle(CrocButtonStyle(kind: .secondary))
                        }

                        Label("End-to-end encrypted", systemImage: "lock.fill")
                            .font(.callout)
                            .foregroundStyle(CrocPalette.olive)
                    }

                    if let setupBlockingMessage {
                        Label(setupBlockingMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(CrocPalette.danger)
                    }
                }
                .surfaceCard(minHeight: expandedHeight, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var terminalOutcomeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(store.statusTitle, systemImage: store.phase.menuBarSymbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(store.phase == .cancelled ? .secondary : CrocPalette.ink)

            Text(store.statusDetail)
                .font(.body)
                .foregroundStyle(CrocPalette.olive)

            if let completionLocationDetail = store.completionLocationDetail {
                Label(completionLocationDetail, systemImage: store.mode == .receive ? "folder" : "doc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    store.prepareNewTransfer()
                } label: {
                    Label("New transfer", systemImage: "plus")
                }
                .buttonStyle(CrocButtonStyle(kind: .primary))

                if case .failed = store.phase, store.failureAllowsRetry {
                    Button {
                        store.mode == .send ? store.beginSend() : store.beginReceive()
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(CrocButtonStyle(kind: .secondary))
                }

                if store.completionLocationURL != nil {
                    Button {
                        store.revealCompletionLocation()
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .buttonStyle(CrocButtonStyle(kind: .secondary))
                }

                if !store.logLines.isEmpty {
                    Button {
                        store.showDetails = true
                    } label: {
                        Label("View log", systemImage: "text.alignleft")
                    }
                    .buttonStyle(CrocButtonStyle(kind: .secondary))
                }
            }
        }
        .surfaceCard()
    }

    private var statusFooter: some View {
        VStack(spacing: 0) {
            if let progress = store.progress, store.phase.isRunning {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(store.phase == .cancelling ? Color.secondary : CrocPalette.forestBright)
                    .accessibilityLabel(store.statusTitle)
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }

            HStack(spacing: 12) {
                Image(systemName: store.phase.menuBarSymbol)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.statusTitle)
                        .font(.callout.weight(.semibold))
                    Text(store.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(store.statusTitle)
                .accessibilityValue(store.statusDetail)

                Spacer(minLength: 16)

                footerActions
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(CrocPalette.chrome)
    }

    @ViewBuilder
    private var footerActions: some View {
        if store.phase.isRunning {
            if !store.codePhrase.isEmpty {
                CopyFeedbackButton("Copy code", kind: .secondary, action: store.copyCode)
            }

            Button {
                store.showDetails = true
            } label: {
                Label("Details", systemImage: "text.alignleft")
            }
            .buttonStyle(CrocButtonStyle(kind: .secondary))

            if store.phase != .cancelling {
                Button {
                    store.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(CrocButtonStyle(kind: .destructive))
            }
        }
    }

    private var statusColor: Color {
        switch store.phase {
        case .failed: CrocPalette.danger
        case .completed: CrocPalette.forestBright
        case .cancelled: .secondary
        default: CrocPalette.forestMuted
        }
    }

    private var canBeginReceive: Bool {
        !store.receiveCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        store.executableURL != nil &&
        store.isRelayConfigurationValid
    }

    private var setupBlockingMessage: String? {
        if store.executableURL == nil {
            return "Choose a croc executable in Settings before starting."
        }
        if !store.isRelayConfigurationValid {
            return "Enter a custom relay address in Settings before starting."
        }
        return nil
    }

    private func itemMetadata(_ item: SelectedTransferItem) -> String {
        let kind = item.isDirectory ? "Folder" : (item.byteCount?.fileSizeLabel ?? "File")
        return "\(kind) · \(item.parentPath)"
    }

    private func chooseTransferFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose folder"
        if panel.runModal() == .OK, let url = panel.url {
            store.select(url)
        }
    }

    private func chooseTransferFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose file"
        if panel.runModal() == .OK, let url = panel.url {
            store.select(url)
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.outputDirectory
        panel.prompt = "Save Here"
        if panel.runModal() == .OK, let url = panel.url {
            store.setOutputDirectory(url)
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
            resetTask?.cancel()
            withAnimation(.easeOut(duration: 0.12)) {
                isCopied = true
            }
            resetTask = Task {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    isCopied = false
                }
            }
        } label: {
            Label(isCopied ? "Copied" : title, systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(CrocButtonStyle(kind: isCopied ? .success : kind))
        .accessibilityLabel(isCopied ? "Copied" : title)
        .onDisappear {
            resetTask?.cancel()
        }
    }
}

private extension View {
    func surfaceCard(minHeight: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        self
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
            .background(CrocPalette.cream)
            .clipShape(.rect(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}
