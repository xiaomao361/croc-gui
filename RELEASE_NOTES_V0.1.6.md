# croc for macOS 0.1.6

The first public macOS release of this independent native SwiftUI GUI for
[croc](https://github.com/schollz/croc).

## Highlights

- Send a file or folder by choosing it or dragging it into the app.
- Receive into a chosen directory with a croc code phrase.
- Show Windows and Linux/macOS command-line receive instructions.
- Configure the default or a custom croc relay.
- View transfer progress and logs, copy codes, and cancel transfers.
- Use a focused single-window macOS interface with no account or cloud storage.

## Original croc project

The transfer core, protocol implementation, encryption behavior, relay
compatibility, and bundled command-line program are from the original
[schollz/croc](https://github.com/schollz/croc) project created by Zack
(`schollz`). Visit the official project website at [getcroc.com](https://getcroc.com/).
This GUI is independent and is not the official croc app.

The bundled croc v10.3.1 binary is distributed under its MIT License. The
copyright notice and complete license are included in the application bundle.

## Package

- macOS 14 or newer
- Apple Silicon (`arm64`)
- Developer ID signed and Apple notarized
- ZIP and drag-to-Applications DMG downloads

## Release validation

- App ZIP notarization: Accepted (`35ff3a4d-3b98-4620-a8a4-61166c04a60b`)
- DMG notarization: Accepted (`a2be7639-d2cb-4ecf-859e-b0319ff35f66`)
- App and DMG Gatekeeper assessment: `Notarized Developer ID`
- App and bundled croc CLI: Hardened Runtime and secure timestamp enabled
- Mounted DMG contents: version 0.1.6, arm64 GUI and croc v10.3.1, license and notice present

```text
73632637c15a00ae8c7c2b2cd36c3e9a09bed3cc738d1f1233ebdcc737a7cb12  croc-0.1.6-arm64.zip
9f63a525dbb14c4c8e8df884fd141e980b94c38ca8489cd4cb60c80df098e818  croc-0.1.6-arm64.dmg
```
