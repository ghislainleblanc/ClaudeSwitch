//
//  ProfileStore.swift
//  Claude Switch
//

import Foundation

/// Persists per-profile snapshots of the files in Claude Desktop's
/// Application Support directory that carry the signed-in account:
/// the OAuth token cache (`config.json`) and the Electron storage
/// (cookies, local storage, IndexedDB, …).
///
/// Snapshots live under `~/Library/Application Support/Claude Switch/Profiles/<profile>/`.
/// Saving builds the snapshot in a staging directory and swaps it in, and
/// restoring moves the live files into an undo directory before replacing
/// them, so neither an error nor a kill mid-operation can leave a mixed
/// two-account state behind: `recoverInterruptedRestore()` puts the live
/// directory back the way it was.
actor ProfileStore {
    /// Items inside Claude Desktop's Application Support directory that
    /// identify the signed-in account. Missing items are skipped; SQLite
    /// side files (journal/wal/shm) are listed defensively.
    static let identityItems = [
        "config.json",
        "claude_desktop_config.json",
        "Local State",
        "Cookies",
        "Cookies-journal",
        "Cookies-wal",
        "Cookies-shm",
        "Local Storage",
        "Session Storage",
        "WebStorage",
        "IndexedDB",
        "Partitions",
        "SharedStorage",
        "SharedStorage-wal",
    ]

    private static let infoFileName = "snapshot-info.json"
    private static let manifestFileName = "undo-manifest.json"

    private struct SnapshotInfo: Codable {
        var savedAt: Date
        var accountUuid: String?
    }

    private let claudeDirectory: URL
    private let profilesDirectory: URL
    private let stagingDirectory: URL
    private let undoDirectory: URL

    init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let supportDirectory = applicationSupport.appending(path: "Claude Switch", directoryHint: .isDirectory)
        claudeDirectory = applicationSupport.appending(path: "Claude", directoryHint: .isDirectory)
        profilesDirectory = supportDirectory.appending(path: "Profiles", directoryHint: .isDirectory)
        stagingDirectory = supportDirectory.appending(path: ".restore-staging", directoryHint: .isDirectory)
        undoDirectory = supportDirectory.appending(path: ".restore-undo", directoryHint: .isDirectory)
    }

    func hasSnapshot(for profile: Profile) -> Bool {
        itemExists(at: snapshotDirectory(for: profile))
    }

    func snapshotDate(for profile: Profile) -> Date? {
        snapshotInfo(for: profile)?.savedAt
    }

    /// The account UUID a profile's snapshot belongs to. Prefers the value
    /// recorded at save time; falls back to reading the snapshot's own
    /// config.json for snapshots saved before the UUID was recorded.
    func snapshotAccountUuid(for profile: Profile) -> String? {
        if let uuid = snapshotInfo(for: profile)?.accountUuid {
            return uuid
        }
        return accountUuid(inConfigurationAt: snapshotDirectory(for: profile).appending(path: "config.json"))
    }

    func liveConfigurationExists() -> Bool {
        itemExists(at: claudeDirectory.appending(path: "config.json"))
    }

    func liveAccountUuid() -> String? {
        accountUuid(inConfigurationAt: claudeDirectory.appending(path: "config.json"))
    }

    /// Puts the live directory back the way it was if a previous restore was
    /// interrupted (error, kill, power loss). Idempotent and cheap when there
    /// is nothing to recover. Returns false only when leftover undo items
    /// could not be moved back — no snapshot may be saved or restored until
    /// a later call succeeds.
    func recoverInterruptedRestore() -> Bool {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: stagingDirectory)
        removeStaleSaveStaging()
        guard itemExists(at: undoDirectory) else { return true }

        // The manifest lists which items existed in the live directory before
        // the interrupted swap. Items not in it can only be staged arrivals
        // from the target snapshot, so they must be removed.
        let manifestURL = undoDirectory.appending(path: Self.manifestFileName)
        let manifest = (try? Data(contentsOf: manifestURL))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) }
            .map(Set.init)

        for item in Self.identityItems {
            let live = claudeDirectory.appending(path: item)
            let saved = undoDirectory.appending(path: item)
            if itemExists(at: saved) {
                try? fileManager.removeItem(at: live)
                try? fileManager.moveItem(at: saved, to: live)
            } else if let manifest, !manifest.contains(item) {
                try? fileManager.removeItem(at: live)
            }
            // No undo copy but listed in the manifest: the item was never
            // moved out of the live directory — leave it alone.
        }

        guard undoLeftovers().isEmpty else { return false }
        try? fileManager.removeItem(at: undoDirectory)
        return true
    }

    /// Copies the live identity files into the profile's snapshot,
    /// replacing any previous snapshot for that profile.
    func saveSnapshot(for profile: Profile) throws {
        let fileManager = FileManager.default
        let destination = snapshotDirectory(for: profile)
        let staging = profilesDirectory.appending(path: profile.rawValue + ".staging", directoryHint: .isDirectory)

        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        for item in Self.identityItems {
            let source = claudeDirectory.appending(path: item)
            guard itemExists(at: source) else { continue }
            try fileManager.copyItem(at: source, to: staging.appending(path: item))
        }

        let info = SnapshotInfo(savedAt: Date(), accountUuid: liveAccountUuid())
        try JSONEncoder().encode(info).write(to: staging.appending(path: Self.infoFileName))

        if itemExists(at: destination) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
    }

    /// Replaces the live identity files with the profile's snapshot.
    /// Claude Desktop must not be running.
    func restoreSnapshot(for profile: Profile) throws {
        let snapshot = snapshotDirectory(for: profile)
        guard itemExists(at: snapshot) else {
            throw SwitcherError.noSnapshot(profile)
        }
        try replaceLiveIdentity(withContentsOf: snapshot)
    }

    /// Removes the live identity files so Claude Desktop starts signed out.
    /// Only call after the current session has been saved to a snapshot.
    func clearLiveIdentity() throws {
        try replaceLiveIdentity(withContentsOf: nil)
    }

    /// Transactionally swaps the live identity items for the contents of
    /// `source` (or removes them when `source` is nil). Incoming files are
    /// fully staged first, so a read error or full disk aborts before the
    /// live directory is touched; live items are moved into the undo
    /// directory, so any later failure rolls back to the original state.
    private func replaceLiveIdentity(withContentsOf source: URL?) throws {
        let fileManager = FileManager.default
        guard recoverInterruptedRestore() else {
            throw SwitcherError.recoveryFailed
        }

        if let source {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            for item in Self.identityItems {
                let saved = source.appending(path: item)
                guard itemExists(at: saved) else { continue }
                try fileManager.copyItem(at: saved, to: stagingDirectory.appending(path: item))
            }
        }

        try fileManager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: undoDirectory, withIntermediateDirectories: true)

        // Record what the live directory holds before the swap, so crash
        // recovery can tell moved-aside originals from staged arrivals.
        let liveItems = Self.identityItems.filter { itemExists(at: claudeDirectory.appending(path: $0)) }
        try JSONEncoder().encode(liveItems).write(to: undoDirectory.appending(path: Self.manifestFileName), options: .atomic)

        var touched: [String] = []
        var failedItem: String?
        do {
            for item in Self.identityItems {
                touched.append(item)
                failedItem = item
                let live = claudeDirectory.appending(path: item)
                if itemExists(at: live) {
                    try fileManager.moveItem(at: live, to: undoDirectory.appending(path: item))
                }
                let staged = stagingDirectory.appending(path: item)
                if source != nil, itemExists(at: staged) {
                    try fileManager.moveItem(at: staged, to: live)
                }
                failedItem = nil
            }
        } catch {
            rollBack(touched: touched, failedItem: failedItem)
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }

        try? fileManager.removeItem(at: undoDirectory)
        try? fileManager.removeItem(at: stagingDirectory)
    }

    /// Moves the undo copies back over whatever the interrupted swap left in
    /// the live directory. For the item that failed mid-move, the original may
    /// still be in place, so it is only replaced when an undo copy exists.
    /// Anything that cannot be moved back stays in the undo directory for
    /// `recoverInterruptedRestore()` to retry.
    private func rollBack(touched: [String], failedItem: String?) {
        let fileManager = FileManager.default
        for item in touched {
            let live = claudeDirectory.appending(path: item)
            let saved = undoDirectory.appending(path: item)
            if item == failedItem {
                if itemExists(at: saved) {
                    try? fileManager.removeItem(at: live)
                    try? fileManager.moveItem(at: saved, to: live)
                }
            } else {
                try? fileManager.removeItem(at: live)
                if itemExists(at: saved) {
                    try? fileManager.moveItem(at: saved, to: live)
                }
            }
        }
        if undoLeftovers().isEmpty {
            try? fileManager.removeItem(at: undoDirectory)
        }
    }

    /// Undo entries that still need to be moved back (excluding bookkeeping files).
    private func undoLeftovers() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: undoDirectory.path(percentEncoded: false))) ?? []
        return entries.filter { $0 != ".DS_Store" && $0 != Self.manifestFileName }
    }

    /// Removes staging directories left behind by a save interrupted mid-copy.
    /// They contain identity-file copies and would otherwise linger forever.
    private func removeStaleSaveStaging() {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(atPath: profilesDirectory.path(percentEncoded: false))) ?? []
        for entry in entries where entry.hasSuffix(".staging") {
            try? fileManager.removeItem(at: profilesDirectory.appending(path: entry))
        }
    }

    private func snapshotDirectory(for profile: Profile) -> URL {
        profilesDirectory.appending(path: profile.rawValue, directoryHint: .isDirectory)
    }

    private func snapshotInfo(for profile: Profile) -> SnapshotInfo? {
        let infoURL = snapshotDirectory(for: profile).appending(path: Self.infoFileName)
        guard let data = try? Data(contentsOf: infoURL) else { return nil }
        return try? JSONDecoder().decode(SnapshotInfo.self, from: data)
    }

    private func accountUuid(inConfigurationAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["lastKnownAccountUuid"] as? String
    }

    private func itemExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
