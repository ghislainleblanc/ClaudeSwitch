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
        MenuBarExtra {
            MenuContentView(viewModel: appDelegate.viewModel)
        } label: {
            Image(systemName: appDelegate.viewModel.menuSymbolName)
                .accessibilityLabel(Text("app.name"))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = SwitcherViewModel()

    /// Refuses to terminate while a switch is mutating Claude Desktop's
    /// files, so Cmd-Q, AppleScript, or logout can't interrupt it midway.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        viewModel.isBusy ? .terminateCancel : .terminateNow
    }
}
