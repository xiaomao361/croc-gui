# croc for macOS 0.3.0

A compact native transfer workspace puts the current task first, with direct
access to the terminal commands used to receive files.

## Highlights

- Center the handoff code and transfer progress in a compact window; unify
  file selection, receiving, waiting, progress, and results.
- Show macOS/Linux and Windows PowerShell commands with one-click copy while
  waiting. Include the current transfer's custom relay and quote shell values.
- Keep one Details entry and provide focused recovery actions for relay,
  executable, and destination errors without discarding the user's input.
- Ignore duplicate start actions and lock file, mode, and destination during
  transfers. Completion uses the actual attempt's destination and metadata.
- Reject multiple dropped items explicitly instead of silently selecting one.
  Put multiple files in a folder to send them together.
- Preserve cancellation and declined-overwrite outcomes even if croc exits
  successfully. Wait for successful process exit before reporting completion,
  including when progress already displays 100%.

## Compatibility

- Apple Silicon, macOS 14 or newer.
- Bundled upstream croc remains v10.7.0; the transfer protocol is unchanged.
- DMG and ZIP distributions use Developer ID signing and Apple notarization.

## Validation

- 30 Swift tests covering parser, runner, lifecycle, recovery, command quoting,
  destination snapshots, progress semantics, and multi-item drops.
- Real croc v10.7.0 transfer using two TransferStores and a local custom relay:
  both completed and the 2,000,000-byte received file matched the source.
- Offscreen SwiftUI content layout checks; production build and packaging.
- App and DMG Developer ID signatures, Apple notarization and stapling,
  Gatekeeper acceptance, DMG integrity, ZIP contents, and SHA-256 checksums.

Native window, keyboard, clipboard, and drag interaction acceptance, plus
multi-gigabyte transfers on representative networks, remain manual checks.
The runtime test above does not establish those results.
