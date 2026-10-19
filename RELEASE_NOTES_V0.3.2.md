# croc for macOS 0.3.2

Transfer reliability and interaction fixes, build 11.

## Changes

- Require a successful croc version check before sending or receiving. An invalid custom executable no longer silently falls back to another core.
- Read core output in order through end of file before reporting completion or selecting a recovery action.
- Bound core version checks with a timeout, drain output while the process runs, and terminate cancelled checks.
- Send malformed-code failures back to code editing while retaining the entered code.
- Give cancellation its own stopping display, without stale transfer speed or ETA.
- Parse known output events without using words inside filenames to determine the transfer phase.
- Show the core's received-item summary and identify progress, bytes and ETA as belonging to the current file. A file reaching 100% does not complete the transfer.
- Add a default keyboard action on result pages and follow new log output only while the reader is at the bottom.

Apple Silicon, macOS 14 or newer. The bundled upstream core remains croc 10.7.0; the protocol and upstream executable are unchanged. The App and DMG use Developer ID signing and Apple notarization.

## Validation

- `swift test`: all 48 tests passed, including real-time prompt handling, ordered final output, invalid-core gating, timeout/cancellation process cleanup, retained receive input and per-file progress restarting within a batch. The final build emitted no compiler warnings.
- Release build and formal packaging passed. The App reports 0.3.2 (11), both executables are arm64, and the bundled core reports croc 10.7.0.
- App and DMG notarization accepted, tickets stapled and validated, and Gatekeeper accepted both as `Notarized Developer ID`. Strict, deep App signature verification passed.
- ZIP integrity and DMG integrity passed; all nine files inside the ZIP match the signed, stapled App. SHA-256 checksums are included with the release assets.
- Formal artifacts: `.build/releases/0.3.2/croc.app`, `croc-0.3.2-arm64.zip`, `croc-0.3.2-arm64.dmg` and `SHA256SUMS.txt`.
- No new real network transfer was run. Progress semantics were checked against pinned upstream source and isolated process fixtures; native interaction acceptance remains pending.

Native window layout, keyboard focus, drag and drop, clipboard use and log scrolling require manual acceptance. No App, window or browser interaction is performed by this change.

Notarization receipts:

- App: `ddf11a6b-be30-4805-a428-ce35c548001e` — Accepted.
- DMG: `1798bf4a-289d-4cc7-b286-e988a79bc48f` — Accepted.

## Progress semantics

The pinned upstream core builds each file's progress bar using that file's size and name. The percentage, byte counts and ETA describe that file. The GUI does not infer aggregate progress or treat the core's trailing content counter as a file count, since that counter may also include empty folders.

- [Pinned file progress implementation](https://github.com/schollz/croc/blob/v10.7.0/src/croc/croc.go#L2762-L2784)
- [Pinned receive summary implementation](https://github.com/schollz/croc/blob/v10.7.0/src/croc/croc.go#L1986-L2042)
