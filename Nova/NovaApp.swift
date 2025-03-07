//
//  NovaApp.swift
//  Nova
//
//  Created by Luca Vaio on 07/03/2025.
//

import SwiftUI
import AppKit

@main
struct FloatingBrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {} // Required to avoid a blank app window
    }
}
