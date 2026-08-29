//
//  Claude_SwitchApp.swift
//  Claude Switch
//
//  Created by Ghislain Leblanc on 2026-08-21.
//

import SwiftUI

@main
struct Claude_SwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app lives in the status bar (see AppDelegate); no windows.
        Settings {
            EmptyView()
        }
    }
}

/// Owns the status item directly instead of using MenuBarExtra: left-click
/// toggles the SwiftUI panel in a popover, right-click shows a context menu
/// with the Quit command.
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let viewModel = SwitcherViewModel()

    private var statusItem: NSStatusItem?
    private var popoverLastClosed: Date = .distantPast

    private lazy var popover: NSPopover = {
        let hostingController = NSHostingController(rootView: MenuContentView(viewModel: viewModel))
        hostingController.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.delegate = self
        return popover
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()
    }

    /// Refuses to terminate while a switch is mutating Claude Desktop's
    /// files, so the quit menu item, AppleScript, or logout can't interrupt
    /// it midway.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        viewModel.isBusy ? .terminateCancel : .terminateNow
    }

    func popoverDidClose(_ notification: Notification) {
        popoverLastClosed = Date()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if isSecondaryClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else if Date().timeIntervalSince(popoverLastClosed) > 0.25 {
            // The transient popover may already have closed on this very
            // click's mouse-down; without the delay guard the mouse-up
            // action would immediately reopen it.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        popover.performClose(nil)
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let aboutItem = NSMenuItem(title: String(localized: "menu.about"),
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "menu.quit"),
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = !viewModel.isBusy
        menu.addItem(quitItem)

        // Attaching the menu makes this click open it; detach right after so
        // the next left-click goes back to the popover action.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Shows the standard About panel (app icon, version, and build number).
    /// The app must be activated first or the panel stays behind other apps.
    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Keeps the status bar icon in sync with the active profile, re-arming
    /// observation after every change.
    private func updateIcon() {
        withObservationTracking {
            // Build the image before the optional-chain assignment: a failed
            // chain would skip the tracked property read and end the loop.
            let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            let image = NSImage(systemSymbolName: viewModel.menuSymbolName,
                                accessibilityDescription: String(localized: "app.name"))?
                .withSymbolConfiguration(configuration)
            statusItem?.button?.image = image
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.updateIcon()
            }
        }
    }
}
