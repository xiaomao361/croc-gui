# croc for macOS 0.3.1

Settings usability fixes, build 10.

- Give the custom relay address a full-width bordered input field with a
  separate label and placeholder.
- Place relay connection options below their label and focus the address
  field when switching to a custom relay.
- Explain that both computers must use the same relay address.
- Allow original-project links to stack when there is insufficient width.
- Close Settings and Transfer Details with Escape. Return in an address
  field no longer acts as the sheet's Done shortcut.

Apple Silicon, macOS 14 or newer. The bundled upstream core remains croc
10.7.0. Release DMG and ZIP distributions use Developer ID signing and
Apple notarization.

## Validation

- All 30 Swift tests passed; production build and local packaging passed.
- The packaged Info.plist reports 0.3.1, build 10, and the bundled core reports
  croc 10.7.0. Strict, deep signature verification and ZIP integrity passed.
- Native focus, keyboard, and responsive layout acceptance remain manual
  checks for the final 0.3.1 package.
- App and DMG notarization accepted, tickets stapled and validated, and
  Gatekeeper accepted both as Notarized Developer ID. DMG integrity passed;
  ZIP executable, core, Info.plist, and license match the signed app.

Notarization receipts:
- App: `86ce1177-e92a-47c2-a4d4-565bcedd43b8`.
- DMG: `ebf64ed3-722c-4c29-a975-ef71500a4bc4`.
