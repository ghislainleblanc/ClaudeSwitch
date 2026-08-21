# Claude Switch

A macOS menu bar utility to quickly switch Claude Desktop between your **personal** and **work** accounts.

## How it works

Claude Desktop keeps the signed-in account in its Application Support directory
(`~/Library/Application Support/Claude`): the OAuth token cache in `config.json`
plus the Electron session storage (Cookies, Local Storage, IndexedDB, …).

Claude Switch keeps one snapshot of those files per profile under
`~/Library/Application Support/Claude Switch/Profiles/<profile>/`. Switching:

1. Quits Claude Desktop (gracefully, with a force-quit fallback).
2. Saves the live session into the currently active profile's snapshot.
3. Restores the target profile's snapshot — or, the first time you switch to a
   profile that has no snapshot yet, clears the live session so Claude Desktop
   asks you to sign in with that account.
4. Relaunches Claude Desktop.

On first launch the app asks which account Claude Desktop is currently signed
in to, and saves that session as the starting snapshot.

Safety measures:

- Saves build the snapshot in a staging directory and swap it in, so an
  interrupted save never leaves a half-written snapshot.
- Restores stage the incoming files first and move the live files into an undo
  directory before replacing them; on any failure they roll back, and an
  interrupted restore is healed automatically on the next launch.
- Each snapshot records the account UUID it belongs to. Before overwriting a
  snapshot, the app checks which account the live session actually belongs to —
  so signing out/in manually inside Claude Desktop can never cause the wrong
  profile to be overwritten. If the session is unrecognized, the app asks you
  to re-assign it instead.
- The app refuses to quit while a switch is mutating files.

## App

- SwiftUI, MVVM (`Models` / `Services` / `ViewModels` / `Views`)
- Menu bar only (`LSUIElement`, no Dock icon), window-style `MenuBarExtra`
- Localized in English and French (String Catalog)
- App Sandbox is disabled: the app must read and write Claude Desktop's
  Application Support directory and quit/relaunch Claude Desktop.

## Notes

- Snapshots contain your Claude session tokens. They stay on this Mac, in your
  user Library, but treat that folder as sensitive.
- Cookies and token caches are encrypted by Claude Desktop via the macOS
  Keychain ("Claude Safe Storage"); the same install decrypts both profiles, so
  swapped snapshots work without re-authentication.

## Build

Open `Claude Switch/Claude Switch.xcodeproj` in Xcode and run, or:

```bash
xcodebuild -project "Claude Switch/Claude Switch.xcodeproj" -scheme "Claude Switch" -configuration Release build
```
