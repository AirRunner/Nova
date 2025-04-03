//
//  NovaApp.swift
//  Nova
//
//  Created by Luca Vaio on 07/03/2025.
//


import SwiftUI

@main
struct NovaApp: App {
    // Use the AppDelegate for lifecycle and core functionality management
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Prevent SwiftUI from creating a default settings window content
        Settings {
            EmptyView()
                .frame(width: 0, height: 0) // Ensure it takes no space if shown
        }
    }
}
