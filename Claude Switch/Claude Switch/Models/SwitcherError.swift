//
//  SwitcherError.swift
//  Claude Switch
//

import Foundation

nonisolated enum SwitcherError: LocalizedError, Sendable {
    case claudeNotInstalled
    case quitTimedOut
    case noSnapshot(Profile)
    case recoveryFailed

    var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            String(localized: "error.claudeNotInstalled")
        case .quitTimedOut:
            String(localized: "error.quitTimedOut")
        case .noSnapshot(let profile):
            String(format: String(localized: "error.noSnapshotFormat"), profile.localizedName)
        case .recoveryFailed:
            String(localized: "error.recoveryFailed")
        }
    }
}
