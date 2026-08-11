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
- Show transfer output and progress, and cancel a running process

The Swift app is a process wrapper; it does not reimplement or fork the croc protocol. Receive secrets are passed with `CROC_SECRET` and are deliberately omitted from the visible command log. The GUI owns the explicit copy action, so the wrapped sender disables croc's automatic clipboard write.

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

The local packaging script builds an arm64 app, embeds a croc CLI, generates the Code Gate icon, and applies an ad-hoc signature:

```sh
./scripts/package-app.sh
open .build/package/croc.app
```

Override the bundled CLI when needed:

```sh
CROC_CORE=/absolute/path/to/croc ./scripts/package-app.sh
```

## Download and install

Download the latest signed and notarized build from [GitHub Releases](https://github.com/xiaomao361/croc-gui/releases/latest). The current release supports Apple Silicon Macs running macOS 14 or newer.

Open the DMG and drag `croc.app` to Applications. The ZIP contains the same notarized application for users who prefer a direct archive.

Release `v0.1.6` is signed with Developer ID team `A5L4GGX82X`, accepted by Apple's notarization service, and validated by Gatekeeper as `Notarized Developer ID`. Published SHA-256 hashes are included with the Release assets.

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

The current public package is Apple Silicon only. A universal build remains future work because both the Swift executable and bundled croc core must include Intel slices.
