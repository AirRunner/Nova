//
//  AppDelegate.swift
//  Nova
//
//  Created by Luca Vaio on 07/03/2025.
//

import Cocoa
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, MenuBarManagerDelegate { // Conform to delegate

    // --- Managers ---
    private var preferencesManager: PreferencesManager!
    private var windowManager: WindowManager!
    private var menuBarManager: MenuBarManager!

    // --- Preferences Window ---
    private var preferencesWindowController: PreferencesController?

    // --- Logger ---
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lucavaio.Nova", category: "AppDelegate")

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Remove Dock icon

        // Initialize managers (order might matter if they depend on each other)
        preferencesManager = PreferencesManager()
        windowManager = WindowManager(preferencesManager: preferencesManager)
        menuBarManager = MenuBarManager()
        menuBarManager.delegate = self // Set AppDelegate as the delegate

        setupMainMenuPreferencesAction() // Keep main menu hook here
        windowManager.performInitialLoad() // Load the WebView

        logger.info("Nova application finished launching with managers.")
    }

    // Keep main menu hook separate from status bar menu
    private func setupMainMenuPreferencesAction() {
        guard let mainMenu = NSApplication.shared.mainMenu,
              let appMenuItem = mainMenu.items.first,
              let appMenu = appMenuItem.submenu else {
            logger.warning("Could not find the main menu or application menu.")
            return
        }

        if let prefsMenuItem = appMenu.items.first(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }) {
            prefsMenuItem.target = self
            prefsMenuItem.action = #selector(showPreferencesWindow) // Keep direct action here
        } else {
            logger.warning("Could not find default Preferences menu item (Cmd+,). Adding a new one.")
            let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferencesWindow), keyEquivalent: ",")
            prefsItem.target = self
            if let separatorIndex = appMenu.items.firstIndex(where: { $0.isSeparatorItem }) {
                appMenu.insertItem(prefsItem, at: separatorIndex)
            } else {
                appMenu.addItem(prefsItem)
            }
        }
    }


    // MARK: - MenuBarManagerDelegate Methods

    func menuBarManagerDidRequestToggleWindow() {
        logger.debug("Delegate: Toggle window requested.")
        windowManager.toggleWindow()
    }

    func menuBarManagerDidRequestShowPreferences() {
        logger.debug("Delegate: Show preferences requested.")
        showPreferencesWindow()
    }

    func menuBarManagerDidRequestQuit() {
        logger.debug("Delegate: Quit requested.")
        NSApp.terminate(nil)
    }

    // MARK: - Preferences Window Handling

    // Triggered by Cmd+, or menu bar item click via delegate
    @objc private func showPreferencesWindow() {
        // Create preferences window controller lazily if it doesn't exist or was closed
        if preferencesWindowController == nil {
            let currentPreferences = preferencesManager.currentPreferences // Get from manager
            preferencesWindowController = PreferencesController(
                preferences: currentPreferences
            ) { [weak self] updatedPreferences in
                // This closure is called when user clicks "Apply" in PreferencesController
                guard let self = self else { return }

                // 1. Tell PreferencesManager to save
                self.preferencesManager.savePreferences(updatedPreferences)

                // 2. Tell WindowManager to apply the changes
                self.windowManager.applyPreferencesChanges(updatedPreferences)

                // Optionally close the preferences window after applying
                // self.preferencesWindowController?.close()
            }
            preferencesWindowController?.window?.isReleasedWhenClosed = false
        }

        preferencesWindowController?.showWindow(self)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Handle standard Preferences menu item if it exists and wasn't overridden
    @objc func showPreferences(_ sender: Any?) {
         logger.debug("Standard showPreferences(_:) called, routing to showPreferencesWindow")
         self.showPreferencesWindow()
    }

    // MARK: - App Termination (Optional)
    // func applicationWillTerminate(_ notification: Notification) {
    //     // Perform any cleanup if necessary
    //     logger.info("Nova application will terminate.")
    // }
}
