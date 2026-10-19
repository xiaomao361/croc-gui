# Compact transfer UI — 2026-09-14

## Approved direction

Implement Figma study B's centered handoff and progress with study A's compactness. Reference file `iVCqXqYwcmOCMzN5FdEx8D`, waiting frame `10:70`, transfer frame `10:90`. Native system typography and window controls replace the presentation proxies.

The default content size is 520 × 440, minimum 520 × 400. One workspace follows the task from selection through waiting, transfer, and outcome. A restrained green accent identifies the primary action; macOS/Linux and Windows PowerShell commands have directly visible copy buttons while waiting, following the user's frequent terminal workflow. Long commands truncate visually with the full value available on hover and copied without truncation. The footer contains security context, one Details entry, and cancellation during a live task. Settings and logs use compact native sheets.

## Behavior changes

- Reject repeated start actions before mutating state. Keep the mode, file, and destination stable while running.
- Snapshot the attempt's item, receive directory, and relay; completion and copied commands use that snapshot, including after future preferences change.
- Include custom relay arguments in shell-safe macOS/Linux and PowerShell instructions.
- Reject multiple dropped items with an explicit message and preserve the previous selection.
- Preserve input when returning from failure to edit. Offer folder selection for destination errors, Settings for relay/core errors, or retry where appropriate.
- Keep cancellation distinct from success even when the core exits zero. Declined overwrite remains a failure and preserves the existing file.
- Unknown progress stays indeterminate; 100% is not completion until the process succeeds. Inactivity describes absence of core output, not a proven network stall.

## Validation

- `swift test`: 30 tests covering parser/runner behavior plus the lifecycle, recovery, command quoting, and drop regressions.
- Release build and local trial packaging passed. `codesign --verify --deep --strict` passed; the ZIP's app executable, core, Info.plist, and license match the packaged app. The bundled core reports 10.7.0. Output: `.build/package-compact-20260914/`.
- Real croc 10.7.0 integration: two TransferStores, a loopback custom relay, and a 2,000,000-byte fixture. Both processes completed, received bytes matched, and the destination snapshot was correct.
- Offscreen SwiftUI rendering checks the content layout only. It does not establish native window, drag-and-drop, keyboard, sheet, or clipboard interaction acceptance.
- Trial mapping: **HCT-2026-09-08-01** checks failure/cancellation/overwrite outcomes remain distinguishable; **HCT-2026-09-08-02** checks attempt snapshots and progress preserve their meaning. These are scoped checks, not evidence that the broader provisional trials are validated.

## User verification remaining

1. At the default window size, try send and receive; check readability, spacing, and keyboard focus.
2. Drop one item and then multiple items; confirm the rejection message and prior selection. During a transfer, try repeated activation and cancellation.
3. Copy a code and each platform command directly from the waiting page; check long custom relay commands copy in full. Open/close Settings and Details. Check that the task remains easy to follow.
4. Receive into a test folder, check the resulting Finder location, and try an existing-file conflict without overwriting it.

## Release 0.3.0

Version 0.3.0 (build 9) packages the final direct-command layout. The App and
DMG are signed with Developer ID team `A5L4GGX82X`, notarized, stapled, and
accepted by Gatekeeper as `Notarized Developer ID`. ZIP contents match the
signed app and the DMG integrity check passed. Release artifacts and checksums
are in `.build/releases/0.3.0/`; the earlier ad-hoc trial packages remain separate.

- App notarization: `ae6b00ad-504f-47a7-b3b7-b138a92da0a2` — Accepted.
- DMG notarization: `09e7226d-9d0d-41dd-ba83-30d500744ddc` — Accepted.

No installation or user-window interaction was performed during validation.

## Reliability iteration — 0.3.2 (build 11), 2026-10-19

The compact layout and light appearance remain the design baseline. This iteration
fixes transfer-state reliability and adds small recovery and reading improvements:

- A transfer requires a successful version check of the currently selected core.
  Invalid explicit paths stay invalid instead of silently selecting another core.
  Version checks have a three-second timeout, drain output while running, and stop
  their process on cancellation. Settings retains a manual recheck action.
- One ordered event stream delivers live output and interactive prompts before the
  final result. The result waits for both output EOF and process exit. Cancellation,
  refused overwrite and failures remain distinct from successful completion.
- Cancellation immediately clears old metrics and shows an indeterminate stopping
  state. A malformed receive code keeps the input and offers code editing.
- Received-item summaries come from recognized upstream summary lines. The current
  file name may be truncated by croc and is displayed as a label, not treated as a
  filesystem path. Unknown metadata stays unavailable.
- The pinned core's percentage, bytes and ETA describe the current file. A file can
  reach 100% before the next file starts; the GUI does not invent a batch percentage.
  Preparation bars and filename text are distinguished using the known output
  format, including whether count/total metrics are present.
- Result pages have one default keyboard action. Details follows growing logs only
  while the reader stays at the bottom, so reading older output does not force a jump.

The regression tests cover the affected failure paths, final errors without a
newline, live prompts, large output, timeout/process cleanup, file progress restarting
within a batch, and a selected core disappearing during inspection. These checks
protect failure-state fidelity and the meaning of per-file progress; they do not
establish native interaction acceptance or a new real end-to-end transfer.

Manual acceptance for 0.3.2:

1. Check send and receive at the default and minimum window sizes, including a long
   filename, receive summary and custom relay.
2. Cancel a transfer after progress appears; confirm old speed/ETA disappear and the
   app reaches cancelled only after croc stops.
3. Enter a malformed code, then use Edit code and verify the input is retained. In
   Settings, choose an invalid core and recover using the automatic core or recheck.
4. Check the result page's Enter action and the receive field's focus after editing.
5. Open Details during a long transfer, scroll up, then return to the bottom; check
   that following resumes only at the bottom.

No application/window operation or installation was performed during validation.
The 0.3.2 App and DMG are Developer ID signed, notarized, stapled and accepted by
Gatekeeper. See [0.3.2 release notes](../RELEASE_NOTES_V0.3.2.md) for the automated
test, formal package and notarization evidence. Publication does not establish the
manual interaction acceptance listed above.
