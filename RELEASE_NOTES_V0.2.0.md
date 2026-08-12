# croc for macOS 0.2.0

This release improves observability and reliability for long-running file
transfers.

## Highlights

- Read terminal progress updates separated by carriage returns without
  buffering an entire long transfer.
- Show percentage, transferred bytes, speed, ETA, and prolonged inactivity
  while keeping process-running and failure states distinct.
- Keep only the latest live progress row in the transfer log.
- Automatically accept croc's partial-file resume prompt; a conflicting full
  destination file is left unchanged and reported as a failure.
- Prevent idle system sleep during an active transfer and block accidental
  window closing or app termination until the transfer is finished or cancelled.
- Treat cancellation as an in-progress operation until the core exits, with a
  forced-stop fallback if it becomes unresponsive.
- Keep the interactive control pipe out of croc's send-file detection, avoiding
  spurious `croc-stdin-*` files and read-only working-directory failures.
- Use a native AppKit dragging destination and pasteboard file-URL reader for
  reliable drops from Finder and DockShelf / 搁这儿.
- Show completion time, duration, destination, and a Finder shortcut, with
  clearer retry behavior and accessible progress/status descriptions.
- Explain blocked start actions, hide irrelevant file controls during active
  transfers, and turn common secure-channel, relay, and file-system failures
  into recovery guidance while preserving the full log.
- Display the actual selected croc core version and whether it is bundled,
  custom, environment-provided, or system-installed.
- Pin the bundled core to official croc v10.7.0 for macOS ARM64, retaining v10
  receiver compatibility while including its later security and reliability
  fixes, and verify both the archive and executable before packaging.

## Bundled core provenance

- Project: https://github.com/schollz/croc
- Release: https://github.com/schollz/croc/releases/tag/v10.7.0
- Asset: `croc_v10.7.0_macOS-ARM64.tar.gz`
- Archive SHA-256: `be7a6716068277002d2fc30a5c37c8786641b40226b412ace20b44aebacd594c`
- Extracted executable SHA-256: `5063bc6f029cb38936067e69d0851606c98705441aed6b2eb3406a337ea280eb`

## Validation completed

- 18 Swift tests, including native pasteboard file drops, CR/LF framing,
  progress metadata, version parsing,
  failure guidance, and interactive resume prompt handling
- Production Swift build
- Official croc v10.7.0 archive checksum, extracted executable checksum,
  version, and ARM64 architecture
- Real 4 MB random-file transfers from bundled v10.7.0 to v10.5.0 and the
  previous bundled v10.3.1 through a relay, both with matching SHA-256
- Interrupted 16 MB receive restarted at 25.2% through a temporary self-hosted
  relay, completed with matching SHA-256
- Local ad-hoc app packaging, deep code-signature verification, and ZIP
  integrity check
- Developer ID signing, Apple notarization and stapling for both the app and
  DMG, Gatekeeper acceptance, DMG verification, and release checksums

## Remaining runtime validation

- A complete multi-gigabyte transfer should still be observed on representative
  networks; signing and notarization do not replace this runtime acceptance test.
