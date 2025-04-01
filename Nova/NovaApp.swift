//
//  NovaApp.swift
//  Nova
//
//  Created by Luca Vaio on 07/03/2025.
//


import SwiftUI
import AppKit

@main
struct NovaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            // Empty settings scene to avoid blank window
            EmptyView()
        }
    }
}
