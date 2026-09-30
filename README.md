# croc for macOS

An independent native SwiftUI GUI for [croc](https://github.com/schollz/croc). The file-transfer core, protocol implementation, and bundled command-line program are the original `croc` project created by Zack (`schollz`). This GUI is not the official croc app.

- Original project: [github.com/schollz/croc](https://github.com/schollz/croc)
- Official website: [getcroc.com](https://getcroc.com/)
- Original license: [MIT License](https://github.com/schollz/croc/blob/main/LICENSE)

## Current scope

- Send a file or folder, including drag and drop
- Receive with a croc code phrase and choose the output folder
- Copy the generated code phrase
- Use croc's default relay or configure a custom relay
- Show live transfer progress, byte counts, speed, ETA, and inactivity status
- Automatically resume an existing partial file when croc offers a safe resume
- Prevent idle system sleep during a transfer and keep the window open until it finishes or is cancelled
- Confirm process exit before reporting cancellation, with a forced-stop fallback for an unresponsive core
- Show the active croc core version plus completion time, duration, destination, and a Finder shortcut
- Explain common secure-channel, relay, and destination failures while preserving the full core log
- Compact task workspace: select, share the code, track progress, then act on the result
- Keep the active file, destination, and relay fixed for each attempt; ignore duplicate start actions
- Include the active custom relay in copied terminal instructions (Windows PowerShell or macOS/Linux shell)
- Reject multi-item drops explicitly; place several files in a folder to send them together

The Swift app is a process wrapper; it does not reimplement or fork the croc protocol. Receive secrets are passed with `CROC_SECRET` and are deliberately omitted from the visible command log. The GUI owns the explicit copy action, so the wrapped sender disables croc's automatic clipboard write. Packaged builds pin and checksum the official croc v10.7.0 macOS ARM64 binary, retaining the v10 protocol line for compatibility with existing receivers.

## Original croc attribution

This application bundles and launches the original `croc` command-line program for all transfers. Credit for the transfer engine, protocol, encryption behavior, relay compatibility, and CLI belongs to the [schollz/croc](https://github.com/schollz/croc) project and its contributors.

The bundled `croc` program is distributed under the MIT License. Its copyright notice and full license text are preserved in [`ThirdPartyNotices/croc-LICENSE.txt`](ThirdPartyNotices/croc-LICENSE.txt). A distribution notice is preserved in [`ThirdPartyNotices/croc-NOTICE.txt`](ThirdPartyNotices/croc-NOTICE.txt).

## Run from source

Requirements: macOS 14 or newer, Xcode 16 or newer, and a `croc` executable.

```sh
brew install croc
swift run CrocGUI
```

For local development with another croc binary:

```sh
CROC_EXECUTABLE=/absolute/path/to/croc swift run CrocGUI
```

You can also choose the binary later in **croc → Settings**.

## Validate

```sh
swift test
swift build
```

## Package a local trial app

The local packaging script builds an arm64 app, downloads and verifies the pinned official croc core when needed, generates the Code Gate icon, and applies an ad-hoc signature:

```sh
./scripts/package-app.sh
open .build/package/croc.app
```

Override the bundled CLI when needed:

```sh
CROC_CORE=/absolute/path/to/croc ./scripts/package-app.sh
```

Set `CROC_PACKAGE_OUTPUT_DIR` to a separate directory to preserve an existing package while creating a trial build. Local trial packages are ad-hoc signed, not notarized releases.

The current source revision is 0.3.1 (build 10), with settings usability fixes.
See the [0.3.1 notes](RELEASE_NOTES_V0.3.1.md) for changes and validation boundaries.

## Download and install

Download the latest signed and notarized build from [GitHub Releases](https://github.com/xiaomao361/croc-gui/releases/latest). The current release supports Apple Silicon Macs running macOS 14 or newer.

Open the DMG and drag `croc.app` to Applications. The ZIP contains the same notarized application for users who prefer a direct archive.

Release `v0.3.1` is signed with Developer ID team `A5L4GGX82X`, accepted by Apple's notarization service, and validated by Gatekeeper as `Notarized Developer ID`. See the [release notes](RELEASE_NOTES_V0.3.1.md).

## Create a signed release

The release script signs the bundled croc CLI and outer application with Developer ID, enables Hardened Runtime, submits the App and DMG to Apple for notarization, staples both tickets, verifies Gatekeeper acceptance, and writes SHA-256 checksums:

```sh
./scripts/release-macos.sh
```

Defaults:

- Signing identity: `Developer ID Application: zhou wei (A5L4GGX82X)`
- notarytool keychain profile: `claracore-notary`
- Architecture: `arm64`

Override `SIGN_IDENTITY`, `NOTARY_PROFILE`, or `CROC_CORE` in the environment when needed. The script never stores Apple credentials in the repository.

## Design

The visual direction is maintained in [Figma](https://www.figma.com/design/iVCqXqYwcmOCMzN5FdEx8D). The app uses the macOS system font and native controls; Figma's Inter labels and drawn window chrome are presentation proxies only.

The compact redesign combines study B's centered code/progress with study A's density. Terminal commands and their copy buttons are directly visible while waiting, Details has one entry point, and errors retain input with a relevant recovery action. See [implementation and validation notes](docs/compact-ui.md).

The current public package is Apple Silicon only. A universal build remains future work because both the Swift executable and bundled croc core must include Intel slices.
