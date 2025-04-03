//
//  MenuBarManager.swift
//  Nova
//
//  Created by Luca Vaio on 03/04/2025.
//


import AppKit
import os.log

// Protocol to communicate actions back to the AppDelegate (or coordinator)
@MainActor
protocol MenuBarManagerDelegate: AnyObject {
    func menuBarManagerDidRequestToggleWindow()
    func menuBarManagerDidRequestShowPreferences()
    func menuBarManagerDidRequestQuit()
}

@MainActor // Interacts with NSStatusItem
class MenuBarManager {

    // --- Delegate ---
    weak var delegate: MenuBarManagerDelegate?

    // --- UI Elements ---
    private var statusItem: NSStatusItem?

    // --- Logger ---
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lucavaio.Nova", category: "MenuBarManager")

    // --- Initialization ---
    init() {
        setupMenuBar()
    }

    // --- Setup ---
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else {
            logger.critical("Failed to create status bar button.")
            // Consider how to handle this fatal error - maybe alert the user?
            return
        }

        button.image = NSImage(systemSymbolName: "message.badge.waveform", accessibilityDescription: "Nova")
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        logger.info("Menu bar item created.")
    }

    // --- Actions ---

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            // Left-click or programmatic click
            delegate?.menuBarManagerDidRequestToggleWindow()
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(preferencesAction), keyEquivalent: ",")
        prefsItem.target = self // Action is handled within this class
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Nova", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Display the menu
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil) // Programmatically click to show
        statusItem?.menu = nil // Important: Reset menu so left-click works again
    }

    @objc private func preferencesAction() {
        delegate?.menuBarManagerDidRequestShowPreferences()
    }

    @objc private func quitAction() {
        delegate?.menuBarManagerDidRequestQuit()
    }
}
