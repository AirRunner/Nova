//
//  AppDelegate.swift
//  Nova
//
//  Created by Luca Vaio on 07/03/2025.
//


import Cocoa
@preconcurrency import WebKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Use private properties where appropriate
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private weak var webView: WKWebView?
    private var reloadButton: NSButton?
    
    // Use a constant for reused values
    private let buttonSize: CGFloat = 30
    private let padding: CGFloat = 10
    private let borderThickness: CGFloat = 15
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Remove Dock icon
        
        setupMenuBar()
        setupWindow()
        
        window?.makeKeyAndOrderFront(nil) // Show the window immediately
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        
        button.image = NSImage(systemSymbolName: "message.badge.waveform",
                              accessibilityDescription: "Nova")
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp]) // Detect both left and right clicks
    }
    
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showMenu(sender) // Handle right-click
        } else {
            toggleWindow() // Handle left-click & AppleScript click
        }
    }
    
    private func showMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        // Use temporary menu assignment to show menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // Clear menu after display
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Preferences Management
    
    struct Preferences: Codable {
        var windowSize: NSSize
        var windowOrigin: NSPoint
        var webViewURL: String
        var cornerRadius: CGFloat
        
        static let defaults = Preferences(
            windowSize: NSSize(width: 440, height: 540),
            windowOrigin: NSPoint(x: 30, y: 120),
            webViewURL: "http://localhost:3000/?temporary-chat=true",
            cornerRadius: 30
        )
    }
    
    private func preferencesFilePath() -> URL {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
        let novaDir = appSupportDir.appendingPathComponent("Nova", isDirectory: true)
        
        // Ensure the Nova directory exists
        if !fileManager.fileExists(atPath: novaDir.path) {
            try? fileManager.createDirectory(at: novaDir,
                                          withIntermediateDirectories: true,
                                          attributes: nil)
        }
        
        return novaDir.appendingPathComponent("Preferences.plist")
    }
    
    private func loadPreferences() -> Preferences {
        let configFile = preferencesFilePath()
        
        // Try to load existing preferences
        if let data = try? Data(contentsOf: configFile),
           let preferences = try? PropertyListDecoder().decode(Preferences.self, from: data) {
            return preferences
        }
        
        // Save and return defaults if no valid preferences exist
        let defaults = Preferences.defaults
        savePreferences(defaults)
        return defaults
    }
    
    private func savePreferences(_ preferences: Preferences) {
        if let data = try? PropertyListEncoder().encode(preferences) {
            try? data.write(to: preferencesFilePath())
        }
    }
    
    // MARK: - Window Setup
    
    private func setupWindow() {
        // Load preferences
        let preferences = loadPreferences()
        
        // Create window with correct positioning
        let window = createFloatingWindow(with: preferences)
        let hoverView = createHoverView(in: window, with: preferences)
        
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
        let windowOrigin = preferences.windowOrigin
        
        // Calculate position from right side of screen
        let screenSize = NSScreen.main?.frame ?? .zero
        let rect = NSRect(
            x: screenSize.width - windowSize.width - windowOrigin.x,
            y: windowOrigin.y,
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
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        
        return window
    }
    
    private func createHoverView(in window: NSWindow, with preferences: Preferences) -> HoverView {
        let hoverView = HoverView(frame: NSRect(
            x: 0, y: 0,
            width: preferences.windowSize.width,
            height: preferences.windowSize.height
        ))
        
        window.contentView = hoverView
        
        // Apply rounded corners
        hoverView.wantsLayer = true
        hoverView.layer?.cornerRadius = preferences.cornerRadius
        hoverView.layer?.masksToBounds = true
        
        // Add blur effect
        let blurEffect = NSVisualEffectView(frame: hoverView.bounds)
        blurEffect.material = .hudWindow
        blurEffect.blendingMode = .behindWindow
        blurEffect.state = .active
        blurEffect.autoresizingMask = [.width, .height]
        hoverView.addSubview(blurEffect)
        
        return hoverView
    }
    
    private func setupWebView(in hoverView: NSView, with preferences: Preferences) -> WKWebView {
        let webView = WKWebView(frame: hoverView.bounds)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(NSColor.clear, forKey: "underPageBackgroundColor")
        webView.navigationDelegate = self
        hoverView.addSubview(webView)
        
        // Load web content
        if let url = URL(string: preferences.webViewURL) {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    private func setupControlButtons(in hoverView: NSView, size windowSize: NSSize) {
        // Create reload button with system icon
        if let reloadImage = NSImage(systemSymbolName: "arrow.clockwise",
                                    accessibilityDescription: "Reload") {
            let button = HoverButton(image: reloadImage, target: self, action: #selector(reloadWebView))
            button.frame = NSRect(
                x: windowSize.width / 2 - buttonSize / 2,
                y: windowSize.height - buttonSize - padding,
                width: buttonSize,
                height: buttonSize
            )
            
            button.isBordered = false
            button.wantsLayer = true
            button.layer = CALayer()
            button.alphaValue = 0 // Hidden by default
            
            hoverView.addSubview(button)
            self.reloadButton = button
        }
    }
    
    private func setupDragAreas(in hoverView: NSView, size windowSize: NSSize) {
        // Top draggable area
        let topDragArea = NSView(frame: NSRect(
            x: 0,
            y: windowSize.height - borderThickness,
            width: windowSize.width,
            height: borderThickness
        ))
        topDragArea.wantsLayer = true
        topDragArea.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Bottom draggable area
        let bottomDragArea = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: windowSize.width,
            height: borderThickness
        ))
        bottomDragArea.wantsLayer = true
        bottomDragArea.layer?.backgroundColor = NSColor.clear.cgColor
        
        hoverView.addSubview(topDragArea)
        hoverView.addSubview(bottomDragArea)
        
        // Add drag gesture recognizers
        topDragArea.addGestureRecognizer(
            NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        )
        bottomDragArea.addGestureRecognizer(
            NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        )
    }
    
    private func configureHoverBehavior(for hoverView: HoverView) {
        // Use weak self to prevent memory leaks
        hoverView.onHover = { [weak self] isHovering in
            guard let self = self else { return }
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                let scale: CGFloat = isHovering ? 1.2 : 1.0
                let alpha: CGFloat = isHovering ? 1 : 0
                
                // Animate alpha change
                self.reloadButton?.animator().alphaValue = alpha
                
                // Add scale animation
                let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
                scaleAnimation.toValue = scale
                scaleAnimation.duration = 0.2
                scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                // Apply animations
                self.reloadButton?.layer?.add(scaleAnimation, forKey: "scale")
                self.reloadButton?.layer?.setAffineTransform(
                    CGAffineTransform(scaleX: scale, y: scale)
                )
            }
        }
    }
    
    // MARK: - Window Actions
    
    @objc func toggleWindow() {
        guard let window = window else { return }
        
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true) // Bring to front
        }
    }
    
    @objc func reloadWebView() {
        webView?.reload()
    }
    
    @objc func closeWindow() {
        webView?.navigationDelegate = nil
        window?.orderOut(nil)
    }
    
    @objc func handleDrag(_ sender: NSPanGestureRecognizer) {
        guard let window = window else { return }
        
        if sender.state == .began {
            // Create a mouse event to initiate the drag
            let location = sender.location(in: window.contentView)
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1.0
            )
            
            if let event = event {
                window.performDrag(with: event)
            }
        }
    }
}

// MARK: - WebView Navigation Delegate

extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        if let url = navigationAction.request.url {
            if navigationAction.navigationType == .linkActivated {
                // Open links in default browser
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else if url.absoluteString.starts(with: "data:attachment") {
                // Handle data URLs
                handleDataURL(url)
                decisionHandler(.cancel)
            } else {
                // Allow normal navigation
                decisionHandler(.allow)
            }
        } else {
            decisionHandler(.allow)
        }
    }
    
    private func handleDataURL(_ url: URL) {
        guard let base64String = url.absoluteString.components(separatedBy: "base64,").last,
              let data = Data(base64Encoded: base64String) else {
            print("Error: Can't decode data.")
            return
        }
        
        // Generate unique filename
        let uniqueID = UUID().uuidString
        let fileName = "file_\(uniqueID).csv"
        
        // Save to Downloads directory
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            print("File saved at: \(fileURL)")
        } catch {
            print("Failed to save the file: \(error)")
        }
    }
}
