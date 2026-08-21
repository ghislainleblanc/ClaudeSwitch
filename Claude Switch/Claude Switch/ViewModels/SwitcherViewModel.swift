//
//  SwitcherViewModel.swift
//  Claude Switch
//

import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class SwitcherViewModel {
    enum Status: Equatable {
        case saving(Profile)
        case switching(Profile)
        case switched(Profile)
        case signInRequired(Profile)
        case sessionMismatch
        case loginItemNeedsApproval
        case failure(String)
    }

    private(set) var activeProfile: Profile?
    private(set) var isBusy = false
    private(set) var status: Status?
    private(set) var snapshotDates: [Profile: Date] = [:]
    private(set) var launchAtLogin = false

    var needsInitialSetup: Bool { activeProfile == nil }

    var menuSymbolName: String {
        guard let activeProfile else { return "person.crop.circle.badge.questionmark" }
        return activeProfile.symbolName
    }

    private let store = ProfileStore()
    private let claude = ClaudeDesktopController()
    private static let activeProfileKey = "activeProfile"

    @ObservationIgnored private var statusDismissalTask: Task<Void, Never>?

    init() {
        if let rawValue = UserDefaults.standard.string(forKey: Self.activeProfileKey) {
            activeProfile = Profile(rawValue: rawValue)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Task {
            _ = await store.recoverInterruptedRestore()
            await refreshSnapshotDates()
        }
    }

    /// Refreshes state that can change behind the app's back (login item
    /// status, snapshots on disk). Called each time the menu opens.
    func refresh() async {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if status == .loginItemNeedsApproval && launchAtLogin {
            status = nil
        }
        await refreshSnapshotDates()
    }

    /// Records which account the live Claude Desktop session belongs to, and
    /// saves that session as the profile's snapshot. Used on first run and to
    /// re-assign after a session mismatch.
    func assignCurrentSession(to profile: Profile) async {
        guard !isBusy else { return }
        isBusy = true
        cancelStatusDismissal()
        status = .saving(profile)

        do {
            guard await store.recoverInterruptedRestore() else {
                throw SwitcherError.recoveryFailed
            }
            let wasRunning = claude.isRunning
            try await claude.quit()
            try await store.saveSnapshot(for: profile)
            setActiveProfile(profile)
            if wasRunning {
                try await claude.launch()
            }
            status = .switched(profile)
            scheduleStatusDismissal(after: .seconds(4))
        } catch {
            status = .failure(error.localizedDescription)
        }
        await refreshSnapshotDates()
        isBusy = false
    }

    /// Switches Claude Desktop to the given profile: quits Claude, saves the
    /// live session into the profile it belongs to, restores the target
    /// profile's snapshot (or clears the session so the user can sign in the
    /// first time), and relaunches Claude.
    func switchTo(_ profile: Profile) async {
        guard !isBusy, let currentProfile = activeProfile, profile != currentProfile else { return }
        isBusy = true
        cancelStatusDismissal()
        status = .switching(profile)

        do {
            try await performSwitch(from: currentProfile, to: profile)
        } catch {
            status = .failure(error.localizedDescription)
        }
        await refreshSnapshotDates()
        isBusy = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        cancelStatusDismissal()
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    status = .loginItemNeedsApproval
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            status = .failure(error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func performSwitch(from currentProfile: Profile, to profile: Profile) async throws {
        guard await store.recoverInterruptedRestore() else {
            throw SwitcherError.recoveryFailed
        }
        try await claude.quit()

        // Save the live session into the profile it actually belongs to, so a
        // manual sign-out/in inside Claude Desktop can't overwrite the wrong
        // profile's snapshot.
        switch await liveSessionOwner(assuming: currentProfile) {
        case .signedOut:
            break
        case .unknown:
            status = .sessionMismatch
            try await claude.launch()
            return
        case .profile(let owner):
            try await store.saveSnapshot(for: owner)
            if owner == profile {
                setActiveProfile(profile)
                try await claude.launch()
                status = .switched(profile)
                scheduleStatusDismissal(after: .seconds(4))
                return
            }
        }

        if await store.hasSnapshot(for: profile) {
            try await store.restoreSnapshot(for: profile)
            setActiveProfile(profile)
            try await claude.launch()
            status = .switched(profile)
            scheduleStatusDismissal(after: .seconds(4))
        } else {
            try await store.clearLiveIdentity()
            setActiveProfile(profile)
            try await claude.launch()
            status = .signInRequired(profile)
        }
    }

    private enum LiveSessionOwner {
        case profile(Profile)
        case signedOut
        case unknown
    }

    /// Determines which profile the live Claude Desktop session belongs to by
    /// comparing account UUIDs. Falls back to the recorded active profile only
    /// when there is no recorded UUID to contradict it.
    private func liveSessionOwner(assuming currentProfile: Profile) async -> LiveSessionOwner {
        guard await store.liveConfigurationExists() else { return .signedOut }

        if let liveUuid = await store.liveAccountUuid() {
            if await store.snapshotAccountUuid(for: currentProfile) == liveUuid {
                return .profile(currentProfile)
            }
            for candidate in Profile.allCases where candidate != currentProfile {
                if await store.snapshotAccountUuid(for: candidate) == liveUuid {
                    return .profile(candidate)
                }
            }
        }
        if await store.snapshotAccountUuid(for: currentProfile) == nil {
            return .profile(currentProfile)
        }
        return .unknown
    }

    private func setActiveProfile(_ profile: Profile) {
        activeProfile = profile
        UserDefaults.standard.set(profile.rawValue, forKey: Self.activeProfileKey)
    }

    private func refreshSnapshotDates() async {
        var dates: [Profile: Date] = [:]
        for profile in Profile.allCases {
            dates[profile] = await store.snapshotDate(for: profile)
        }
        snapshotDates = dates
    }

    private func scheduleStatusDismissal(after delay: Duration) {
        statusDismissalTask?.cancel()
        statusDismissalTask = Task {
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            status = nil
        }
    }

    private func cancelStatusDismissal() {
        statusDismissalTask?.cancel()
        statusDismissalTask = nil
    }
}
