//
//  NapCatInstallerApp.swift
//  NapCatInstaller
//
//  Created by hguandl on 2024/10/1.
//

import SwiftUI

@main
struct NapCatInstallerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
