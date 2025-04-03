//
//  AppDelegate.swift
//  Nova
//
//  Created by Luca Vaio on 07/03/2025.
//


import Cocoa
@preconcurrency import WebKit
import os.log

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private weak var webView: WKWebView?
    private var reloadButton: NSButton?
    // Keep track of drag areas to resize them
    private weak var topDragArea: NSView?
    private weak var bottomDragArea: NSView?

    // Use a constant for reused values
    private let buttonSize: CGFloat = 30
    private let padding: CGFloat = 10
    private let borderThickness: CGFloat = 15

    // Preferences window
    private var preferencesWindowController: PreferencesController?

    // Logger
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lucavaio.Nova", category: "AppDelegate")

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Remove Dock icon

        setupMainMenuAction()
        setupMenuBar()
        setupWindow()

        window?.makeKeyAndOrderFront(nil) // Show the window immediately
    }

    // MARK: - Menu Bar Setup

    private func setupMainMenuAction() {
        // Find the default Preferences item in the main menu
        guard let mainMenu = NSApplication.shared.mainMenu,
              let appMenuItem = mainMenu.items.first, // Usually the Application menu
              let appMenu = appMenuItem.submenu else {
            logger.warning("Could not find the main menu or application menu.")
            return
        }

        if let prefsMenuItem = appMenu.items.first(where: { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }) {
            prefsMenuItem.target = self
            prefsMenuItem.action = #selector(showPreferencesWindow)
            logger.info("Successfully bound Preferences menu item.")
        } else {
            // Fallback if standard item not found (less likely but safer)
            logger.warning("Could not find default Preferences menu item (Cmd+,). Adding a new one.")
            let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferencesWindow), keyEquivalent: ",")
            prefsItem.target = self
            // Try adding to the app menu, finding a suitable spot
            if let separatorIndex = appMenu.items.firstIndex(where: { $0.isSeparatorItem }) {
                appMenu.insertItem(prefsItem, at: separatorIndex)
            } else {
                appMenu.addItem(prefsItem) // Add at the end if no separator
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else {
            logger.critical("Failed to create status bar button.")
            return
        }

        button.image = NSImage(
            systemSymbolName: "message.badge.waveform",
            accessibilityDescription: "Nova"
        )
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp]) // Detect both left and right clicks
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showMenu(sender) // Handle right-click
        } else {
            toggleWindow() // Handle left-click & potentially AppleScript click
        }
    }

    private func showMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()

        // Add menu items
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferencesWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Nova", action: #selector(quitApp), keyEquivalent: "q"))

        // Use temporary menu assignment to show menu relative to the status item
        statusItem.menu = menu
        statusItem.button?.performClick(nil) // Programmatically click to show the menu
        statusItem.menu = nil // Clear menu after display so it doesn't interfere with left clicks
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Preferences Management

    struct Preferences: Codable {
        var windowSize: NSSize
        var windowOrigin: NSPoint // Stored as offset from bottom-left of screen, but positioned from top-right
        var webViewURL: String
        var cornerRadius: CGFloat

        static let defaults = Preferences(
            windowSize: NSSize(width: 440, height: 540),
            windowOrigin: NSPoint(x: 30, y: 120), // Offset from screen bottom-right corner
            webViewURL: "http://localhost:8080/",
            cornerRadius: 30
        )
    }

    private func preferencesFilePath() -> URL {
        let fileManager = FileManager.default
        // Use Application Support directory
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Fallback or fatal error if App Support is not accessible
            fatalError("Cannot access Application Support directory.")
        }

        let novaDir = appSupportDir.appendingPathComponent("Nova", isDirectory: true)

        // Ensure the Nova directory exists
        if !fileManager.fileExists(atPath: novaDir.path(percentEncoded: false)) { // Use percentEncoded: false for fileExists
            do {
                try fileManager.createDirectory(at: novaDir, withIntermediateDirectories: true, attributes: nil)
                logger.info("Created preferences directory at \(novaDir.path)")
            } catch {
                // Log the error if directory creation fails
                logger.error("Failed to create preferences directory: \(error.localizedDescription)")
            }
        }

        return novaDir.appendingPathComponent("Preferences.plist")
    }


    private func loadPreferences() -> Preferences {
        let configFile = preferencesFilePath()

        // Try to load existing preferences
        if let data = try? Data(contentsOf: configFile) {
            do {
                let preferences = try PropertyListDecoder().decode(Preferences.self, from: data)
                logger.info("Loaded preferences from \(configFile.path)")
                return preferences
            } catch {
                logger.error("Failed to decode preferences: \(error.localizedDescription). Using defaults.")
            }
        } else {
            logger.info("No preferences file found at \(configFile.path). Using defaults.")
        }

        // Save and return defaults if no valid preferences exist or loading failed
        let defaults = Preferences.defaults
        savePreferences(defaults) // Save defaults on first launch/load failure
        return defaults
    }

    private func savePreferences(_ preferences: Preferences) {
        let configFile = preferencesFilePath()
        do {
            let data = try PropertyListEncoder().encode(preferences)
            try data.write(to: configFile, options: .atomic) // Use atomic write for safety
            logger.info("Saved preferences to \(configFile.path)")
        } catch {
            logger.error("Failed to save preferences: \(error.localizedDescription)")
        }
    }

    // MARK: - Window Setup

    private func setupWindow() {
        // Load preferences
        let preferences = loadPreferences()

        // Create window with correct positioning
        let window = createFloatingWindow(with: preferences)

        // Create HoverView
        let hoverView = HoverView(frame: NSRect(origin: .zero, size: preferences.windowSize)) // Use .zero origin for content view
        hoverView.autoresizingMask = [.width, .height] // Allow hover view to resize with window
        window.contentView = hoverView

        // Setup web view
        let webView = setupWebView(in: hoverView, with: preferences)

        // Add control elements
        setupControlButtons(in: hoverView, size: preferences.windowSize)
        setupDragAreas(in: hoverView, size: preferences.windowSize)

        // Configure hover behavior
        configureHoverBehavior(for: hoverView)

        self.window = window
        self.webView = webView
    }

     private func createFloatingWindow(with preferences: Preferences) -> NSWindow {
        let windowSize = preferences.windowSize
        let windowOriginOffset = preferences.windowOrigin // Offset from bottom-right

        // Calculate position from top-right edge of the main screen
        guard let mainScreen = NSScreen.main else {
            logger.error("Could not get main screen information.")
            // Fallback to a default position if screen info is unavailable
            return FloatingWindow(contentRect: NSRect(origin: .zero, size: windowSize), styleMask: [.borderless], backing: .buffered, defer: false)
        }
        let screenFrame = mainScreen.visibleFrame // Use visibleFrame to account for Dock/Menu bar
        let windowX = screenFrame.maxX - windowSize.width - windowOriginOffset.x
        let windowY = screenFrame.minY + windowOriginOffset.y // Y is from bottom

        let rect = NSRect(
            x: windowX,
            y: windowY,
            width: windowSize.width,
            height: windowSize.height
        )

        // Create window
        let window = FloatingWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating // Keep window above others
        // Allows window to be visible on all spaces and work with fullscreen apps
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hasShadow = true // System handles shadow for borderless windows

        return window
     }


    private func setupWebView(in hoverView: NSView, with preferences: Preferences) -> WKWebView {
        let webView = WKWebView(frame: hoverView.bounds)
        webView.autoresizingMask = [.width, .height] // Ensure webview resizes with hoverView
        webView.underPageBackgroundColor = .clear

        // Make WKWebView rounded
        webView.wantsLayer = true // Essential for cornerRadius and other layer effects
        webView.layer?.cornerRadius = preferences.cornerRadius
        webView.layer?.masksToBounds = true // Clip content to rounded corners

        webView.navigationDelegate = self
        hoverView.addSubview(webView) // Add webView to the hoverView

        // Load web content
        if let url = URL(string: preferences.webViewURL) {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData) // Consider cache policy
            webView.load(request)
            logger.info("Loading URL: \(url.absoluteString)")
        } else {
            logger.error("Invalid URL string in preferences: \(preferences.webViewURL)")
            // Show an error page
            webView.loadHTMLString(createHTML(message: "Invalid URL"), baseURL: nil)
        }

        return webView
    }

    private func setupControlButtons(in hoverView: NSView, size windowSize: NSSize) {
        // Create reload button with system icon
        if let reloadImage = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "Reload"
        ) {
            let button = HoverButton(image: reloadImage, target: self, action: #selector(reloadWebView))
            // Position button near top-center
            button.frame = NSRect(
                x: (windowSize.width - buttonSize) / 2, // Centered horizontally
                y: windowSize.height - buttonSize - padding, // Near the top
                width: buttonSize,
                height: buttonSize
            )
            button.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin] // Keep centered and distance from top

            button.isBordered = false
            button.wantsLayer = true
            button.alphaValue = 0 // Hidden by default
            button.contentTintColor = NSColor.secondaryLabelColor // Use a subtle color

            hoverView.addSubview(button)
            self.reloadButton = button
        } else {
            logger.warning("Could not load system symbol 'arrow.clockwise'.")
        }
    }

    private func setupDragAreas(in hoverView: NSView, size windowSize: NSSize) {
        // Top draggable area
        let topDragRect = NSRect(
            x: 0,
            y: windowSize.height - borderThickness,
            width: windowSize.width,
            height: borderThickness
        )
        let topArea = NSView(frame: topDragRect)
        topArea.wantsLayer = true
        topArea.autoresizingMask = [.width, .minYMargin] // Stick to top, resize width
        hoverView.addSubview(topArea)
        self.topDragArea = topArea // Keep reference

        // Bottom draggable area
        let bottomDragRect = NSRect(
            x: 0,
            y: 0,
            width: windowSize.width,
            height: borderThickness
        )
        let bottomArea = NSView(frame: bottomDragRect)
        bottomArea.wantsLayer = true
        bottomArea.autoresizingMask = [.width, .maxYMargin] // Stick to bottom, resize width
        hoverView.addSubview(bottomArea)
        self.bottomDragArea = bottomArea // Keep reference

        // Add drag gesture recognizers
        let dragRecognizerTop = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        topArea.addGestureRecognizer(dragRecognizerTop)

        let dragRecognizerBottom = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        bottomArea.addGestureRecognizer(dragRecognizerBottom)
    }

    private func configureHoverBehavior(for hoverView: HoverView) {
        // Use weak self to prevent retain cycles in the closure
        hoverView.onHover = { [weak self] isHovering in
            // Ensure self and the button still exist
            guard let self = self, let reloadButton = self.reloadButton else { return }

            // Get the layer for animation (safer access)
            guard let buttonLayer = reloadButton.layer else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) // Smoother timing
                context.allowsImplicitAnimation = true // Allows animating alphaValue directly

                let targetAlpha: CGFloat = isHovering ? 1.0 : 0.0
                let targetScale: CGFloat = isHovering ? 1.2 : 1.0

                // Animate alpha change using animator proxy
                reloadButton.animator().alphaValue = targetAlpha

                // Animate scale using CABasicAnimation for better control
                let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
                scaleAnimation.toValue = targetScale
                scaleAnimation.duration = context.duration // Match context duration
                scaleAnimation.timingFunction = context.timingFunction // Match context timing

                // Apply animation and set final value
                buttonLayer.add(scaleAnimation, forKey: "transform.scale")
                // Set the final transform state directly so it persists after animation
                buttonLayer.setAffineTransform(CGAffineTransform(scaleX: targetScale, y: targetScale))

            }
        }
    }

    // MARK: - Window Actions

    @objc func toggleWindow() {
        guard let window = window else { return }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            // Repositioning if only screen changed
            let currentPrefs = loadPreferences()
            repositionWindow(window, preferences: currentPrefs)

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true) // Bring the app (and its window) to the front
        }
    }

    // Helper to reposition window based on preferences and current screen
    private func repositionWindow(_ window: NSWindow, preferences: Preferences) {
        guard let mainScreen = NSScreen.main else { return }
        let screenFrame = mainScreen.visibleFrame
        let windowSize = preferences.windowSize
        let windowOriginOffset = preferences.windowOrigin

        let windowX = screenFrame.maxX - windowSize.width - windowOriginOffset.x
        let windowY = screenFrame.minY + windowOriginOffset.y

        let newFrame = NSRect(x: windowX, y: windowY, width: windowSize.width, height: windowSize.height)
        window.setFrame(newFrame, display: false) // display: false as it's about to be shown
    }

    @objc func reloadWebView() {
        logger.debug("Reloading WebView content.")
        // Reload and bypass cache
        webView?.reloadFromOrigin()
    }

    @objc func closeWindow() {
        // Clean up delegate to avoid potential issues if webview is somehow reused
        webView?.navigationDelegate = nil
        window?.orderOut(nil)
    }

    @objc func handleDrag(_ sender: NSPanGestureRecognizer) {
        guard let window = window else { return }

        // Simulate a mouse down event
        if sender.state == .began {
            // Location in the window's base coordinate system
            let locationInWindow = sender.location(in: nil)

            // Create a synthetic mouse down event at the drag start location
            let fakeMouseDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: locationInWindow,
                modifierFlags: [], // Use current event's flags if needed: sender.modifierFlags
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1.0 // Standard pressure for mouse down
            )

            if let event = fakeMouseDown {
                // Tell the window to initiate a drag operation using this synthetic event
                window.performDrag(with: event)
            } else {
                logger.error("Could not create synthetic mouse event for dragging.")
            }
        }
        // No action needed for .changed or .ended state, as performDrag handles the loop
    }

    @objc private func showPreferencesWindow() {
        // Create preferences window controller lazily if it doesn't exist
        if preferencesWindowController == nil {
            let currentPreferences = loadPreferences()
            preferencesWindowController = PreferencesController(
                preferences: currentPreferences
            ) { [weak self] updatedPreferences in
                // When user clicks "Apply" in Preferences
                guard let self = self else { return }

                // Save updated preferences
                self.savePreferences(updatedPreferences)

                // Apply changes to main window
                self.applyPreferencesChanges(updatedPreferences)
            }
            // Keep the preferences window in memory when closed
            preferencesWindowController?.window?.isReleasedWhenClosed = false
        }

        // Show the preferences window
        preferencesWindowController?.showWindow(self)
        // Bring the preferences window to the front
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true) // Ensure the app is active
    }
    
    // Standard SwiftUI Preferences, in case it is being called
    @objc func showPreferences(_ sender: Any?) {
         logger.debug("showPreferences(_:) called, routing to showPreferencesWindow")
         self.showPreferencesWindow()
    }


    // Apply preferences changes to the live window and webview
    private func applyPreferencesChanges(_ preferences: Preferences) {
        logger.info("Applying preference changes...")
        // Update window size and position
        if let window = window {
            // Get screen size to calculate position from top-right
            guard let mainScreen = NSScreen.main else {
                logger.error("Cannot get main screen to apply preferences.")
                return
            }
            let screenFrame = mainScreen.visibleFrame
            let newFrame = NSRect(
                x: screenFrame.maxX - preferences.windowSize.width - preferences.windowOrigin.x,
                y: screenFrame.minY + preferences.windowOrigin.y, // Y is from bottom
                width: preferences.windowSize.width,
                height: preferences.windowSize.height
            )

            // Animate window frame change
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().setFrame(newFrame, display: true)
            }

            // Update corner radius with animation
            if let webViewLayer = self.webView?.layer {
                 NSAnimationContext.runAnimationGroup { context in
                     context.duration = 0.2
                     context.allowsImplicitAnimation = true // Allow layer properties to animate
                     webViewLayer.cornerRadius = preferences.cornerRadius
                 } completionHandler: {
                     // After animation, invalidate shadow to match new shape
                     window.invalidateShadow()
                 }
            } else {
                 logger.warning("Could not access webView layer to update corner radius.")
            }

            // Update frames of draggable areas
            self.topDragArea?.frame = NSRect(
                x: 0, y: preferences.windowSize.height - borderThickness,
                width: preferences.windowSize.width, height: borderThickness
            )
            self.bottomDragArea?.frame = NSRect(
                x: 0, y: 0,
                width: preferences.windowSize.width, height: borderThickness
            )

            // Update reload button position
            // Autoresizing mask on HoverView might handle this
            self.reloadButton?.frame = NSRect(
                x: (preferences.windowSize.width - buttonSize) / 2,
                y: preferences.windowSize.height - buttonSize - padding,
                width: buttonSize,
                height: buttonSize
            )


            // Autoresizing mask on HoverView might handle this
            if let hoverView = window.contentView as? HoverView {
                 hoverView.updateTrackingAreas()
            }
        }

        // Update WebView URL if it has changed
        if let webView = webView,
           let currentURLString = webView.url?.absoluteString,
           currentURLString != preferences.webViewURL {
            logger.info("WebView URL changed. Loading new URL: \(preferences.webViewURL)")
            if let newURL = URL(string: preferences.webViewURL) {
                let request = URLRequest(url: newURL, cachePolicy: .reloadIgnoringLocalCacheData)
                webView.load(request)
            } else {
                logger.error("Invalid new URL string: \(preferences.webViewURL)")
                webView.loadHTMLString(createHTML(message: "Invalid URL"), baseURL: nil)
            }
        } else if webView?.url == nil && !preferences.webViewURL.isEmpty {
            // Handle case where webview might not have loaded anything yet
            logger.info("WebView has no URL. Loading initial URL: \(preferences.webViewURL)")
            if let newURL = URL(string: preferences.webViewURL) {
                let request = URLRequest(url: newURL, cachePolicy: .reloadIgnoringLocalCacheData)
                webView?.load(request)
            } else {
                logger.error("Invalid initial URL string: \(preferences.webViewURL)")
            }
        }
    }

}

// MARK: - WebView Navigation Delegate

extension AppDelegate: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow) // Allow if no URL
            return
        }

        switch navigationAction.navigationType {
        case .linkActivated:
            // Open links in default browser
            logger.info("Opening external link in browser: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel) // Cancel loading in WKWebView

        case .other, .formSubmitted, .backForward, .reload, .formResubmitted:
            // Allow other navigation types within the webview, unless it's a data URL
            if url.scheme == "data" {
                logger.info("Detected data URL navigation.")
                handleDataURLDownload(url)
                decisionHandler(.cancel) // Cancel loading the data URL itself
            } else {
                decisionHandler(.allow) // Allow standard navigation
            }

        @unknown default:
            // Handle potential future navigation types
            decisionHandler(.allow)
        }
    }

    // Handle data URLs file downloads
    private func handleDataURLDownload(_ url: URL) {
        let urlString = url.absoluteString

        // Basic parsing - might need improvement for complex data URLs
        guard urlString.starts(with: "data:"),
              let rangeOfBase64 = urlString.range(of: ";base64,") else {
            logger.error("Could not parse data URL for download: \(urlString)")
            return
        }

        let base64String = String(urlString[rangeOfBase64.upperBound...])

        guard let data = Data(base64Encoded: base64String) else {
            logger.error("Failed to decode Base64 data from URL.")
            return
        }

        // Generate a filename based on date (could use UUID)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "file_\(timestamp).csv" // Assume CSV

        // Get Downloads directory URL
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            logger.error("Could not access Downloads directory.")
            return
        }

        let fileURL = downloadsURL.appendingPathComponent(fileName)

        // Save the data to the file
        do {
            try data.write(to: fileURL, options: .atomic)
            logger.info("File saved successfully to: \(fileURL.path)")
            // Reveal in Finder
            // NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } catch {
            logger.error("Failed to save downloaded file: \(error.localizedDescription)")
        }
    }
    
    // Helper to generate HTML error message
    private func createHTML(message: String) -> String {
        return "<html><body style='text-align: center;'>\(message)</body></html>"
    }

    // Handle web content process termination
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.warning("WebView process terminated. Reloading might be necessary.")
        // Attempt to reload the page
        reloadWebView()
    }

    // Handle navigation errors
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("WebView failed provisional navigation: \(error.localizedDescription)")
        // Display an error message in the WebView
        webView.loadHTMLString(createHTML(message: "Error loading page: \(error.localizedDescription)"), baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("WebView failed navigation: \(error.localizedDescription)")
    }
}
