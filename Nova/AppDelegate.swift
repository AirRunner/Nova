//
//  AppDelegate.swift
//  Nova
//
//  Created by Luca Vaio on 07/03/2025.
//


import Cocoa
@preconcurrency import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow?
    weak var webView: WKWebView?
    var reloadButton: NSButton?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Remove Dock icon
        
        setupMenuBar()
        setupWindow()
        
        window?.makeKeyAndOrderFront(nil) // Show the window immediately
    }

    // Create Menu Bar Icon
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "message.badge.waveform", accessibilityDescription: "Nova")
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp]) // Detect both left and right clicks
        }
    }
    
    @objc func handleClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showMenu(sender) // Handle right-click
        } else {
            toggleWindow() // Handle left-click & AppleScript click
        }
    }
    
    // Show the menu when right-clicking
    func showMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil) // Display the menu
        statusItem.menu = nil // Prevent the menu from showing on left click
    }
    
    // Quit app
    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // Setup Floating Window
    func setupWindow() {
        let screenSize = NSScreen.main?.frame ?? .zero
        let windowSize = NSSize(width: 440, height: 540) // Default size

        let window = FloatingWindow(
            contentRect: NSRect(x: screenSize.width - windowSize.width - 30, y: 120, width: windowSize.width, height: windowSize.height),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        
        // Use HoverView to detect mouse events
        let hoverView = HoverView(frame: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height))
        window.contentView = hoverView

        // Rounded Corners
        hoverView.wantsLayer = true
        hoverView.layer?.cornerRadius = 30
        hoverView.layer?.masksToBounds = true
        
        // Blur Effect
        let blurEffect = NSVisualEffectView(frame: hoverView.bounds)
        blurEffect.material = .hudWindow
        blurEffect.blendingMode = .behindWindow
        blurEffect.state = .active
        blurEffect.autoresizingMask = [.width, .height]
        hoverView.addSubview(blurEffect)

        // Add WebView
        let webView = WKWebView(frame: hoverView.bounds)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(NSColor.clear, forKey: "underPageBackgroundColor")
        webView.navigationDelegate = self
        hoverView.addSubview(webView)
        
        // Load Web Page
        if let url = URL(string: "http://localhost:8080/") {
            webView.load(URLRequest(url: url))
        }
        
        // Create control buttons
        let buttonSize: CGFloat = 30
        let padding: CGFloat = 10

        // Reload button
        // Declare reloadButton before the if let block
        let reloadButton: HoverButton?
        
        if let reloadImage = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
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
            button.alphaValue = 0
            hoverView.addSubview(button)
            reloadButton = button
        } else {
            reloadButton = nil
        }

        // Make buttons appear/disappear on hover
        hoverView.onHover = { isHovering in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                let scale: CGFloat = isHovering ? 1.2 : 1.0
                let alpha: CGFloat = isHovering ? 1 : 0

                // Use `animator()` to animate alpha change
                self.reloadButton?.animator().alphaValue = alpha

                // Use explicit CABasicAnimation for the scale effect
                let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
                scaleAnimation.toValue = scale
                scaleAnimation.duration = 0.2
                scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

                self.reloadButton?.layer?.add(scaleAnimation, forKey: "scale")
                self.reloadButton?.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        self.window = window
        self.webView = webView
        self.reloadButton = reloadButton
    }

    // Toggle Window Visibility
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
}

class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}

class HoverView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true) // Show buttons
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false) // Hide buttons
    }
}

class HoverButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url) // Open in Safari
            decisionHandler(.cancel) // Prevent loading in WebView
        } else {
            decisionHandler(.allow) // Allow normal navigation
        }
    }
}
