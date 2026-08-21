//
//  ClaudeDesktopController.swift
//  Claude Switch
//

import AppKit

/// Controls the Claude Desktop application lifecycle: detecting whether it is
/// running, quitting it gracefully (with a force-terminate fallback), and
/// relaunching it.
@MainActor
final class ClaudeDesktopController {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    private var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)
    }

    var isRunning: Bool {
        !runningApplications.isEmpty
    }

    func quit() async throws {
        guard isRunning else { return }

        runningApplications.forEach { $0.terminate() }
        if try await waitForTermination(within: .seconds(8)) { return }

        runningApplications.forEach { $0.forceTerminate() }
        if try await waitForTermination(within: .seconds(4)) { return }

        throw SwitcherError.quitTimedOut
    }

    func launch() async throws {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            throw SwitcherError.claudeNotInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }

    private func waitForTermination(within timeout: Duration) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !isRunning { return true }
            try await Task.sleep(for: .milliseconds(200))
        }
        return !isRunning
    }
}
