//
//  WindowManager.swift
//  Nova
//
//  Created by Luca Vaio on 03/04/2025.
//


import Cocoa
import WebKit
import os.log

@MainActor // This class manipulates UI elements
class WindowManager: NSObject, WKNavigationDelegate {

    // --- Dependencies ---
    private let preferencesManager: PreferencesManager

    // --- UI Elements ---
    private var window: FloatingWindow? // Use the custom subclass
    private weak var webView: WKWebView?
    private var reloadButton: NSButton?
    private weak var topDragArea: NSView?
    private weak var bottomDragArea: NSView?
    private weak var hoverView: HoverView?

    // --- State ---
    private var isWindowVisible: Bool { window?.isVisible ?? false }

    // --- Constants ---
    private let buttonSize: CGFloat = 30
    private let padding: CGFloat = 10
    private let borderThickness: CGFloat = 15

    // --- Logger ---
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lucavaio.Nova", category: "WindowManager")

    // --- Initialization ---
    init(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
        super.init()
        setupWindow()
    }

    // --- Public Methods ---

    func performInitialLoad() {
        logger.info("Performing initial load...")
        guard webView != nil else {
            logger.error("Cannot perform initial load: WebView is nil.")
            return
        }
        let initialURL = preferencesManager.currentPreferences.webViewURL
        loadURLInWebView(initialURL)
    }
    
    func showWindow() {
         guard let window = window else { return }
         guard !isWindowVisible else { return } // Don't do anything if already visible

         // Reposition before showing, in case screen setup changed
         repositionWindow(window, preferences: preferencesManager.currentPreferences)

         window.makeKeyAndOrderFront(nil)
         NSApp.activate(ignoringOtherApps: true) // Bring the app (and its window) to the front
         logger.debug("Window shown.")
    }

    func hideWindow() {
        guard let window = window else { return }
        guard isWindowVisible else { return } // Don't do anything if already hidden

        window.orderOut(nil)
        logger.debug("Window hidden.")
    }

    func toggleWindow() {
        if isWindowVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    func reloadWebView() {
        logger.debug("Reloading WebView content from origin.")
        webView?.reloadFromOrigin() // Reload bypassing cache
    }

    // Apply preferences changes to the live window and webview
    func applyPreferencesChanges(_ preferences: PreferencesManager.Preferences) {
        logger.info("Applying preference changes to window...")
        guard let window = window else {
            logger.warning("Window not available to apply preference changes.")
            return
        }

        // Update window size and position with animation
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().setFrame(newFrame, display: true)
        }

        // Update corner radius with animation
        if let webViewLayer = self.webView?.layer {
             NSAnimationContext.runAnimationGroup { context in
                 context.duration = 0.2
                 context.allowsImplicitAnimation = true // Allow layer properties like cornerRadius to animate
                 webViewLayer.cornerRadius = preferences.cornerRadius
             } completionHandler: {
                 window.invalidateShadow() // Update shadow after animation
             }
        } else {
             logger.warning("Could not access webView layer to update corner radius.")
        }

        // Update frames of draggable areas to match new window size
        self.topDragArea?.frame = NSRect(x: 0, y: preferences.windowSize.height - borderThickness, width: preferences.windowSize.width, height: borderThickness)
        self.bottomDragArea?.frame = NSRect(x: 0, y: 0, width: preferences.windowSize.width, height: borderThickness)

        // Reposition reload button
        self.reloadButton?.frame = NSRect(
            x: (preferences.windowSize.width - buttonSize) / 2,
            y: preferences.windowSize.height - buttonSize - padding,
            width: buttonSize, height: buttonSize
        )

        // Ensure HoverView tracking area is updated
        self.hoverView?.updateTrackingAreas()

        // Update WebView URL if it has changed
        let currentURLString = webView?.url?.absoluteString ?? ""
        if currentURLString != preferences.webViewURL {
            logger.info("WebView URL changed. Loading new URL: \(preferences.webViewURL)")
            loadURLInWebView(preferences.webViewURL)
        } else if webView?.url == nil && !preferences.webViewURL.isEmpty {
            logger.info("WebView has no URL. Loading initial/updated URL: \(preferences.webViewURL)")
            loadURLInWebView(preferences.webViewURL)
        }
    }

    // --- Window Setup (Private) ---

    private func setupWindow() {
        let preferences = preferencesManager.currentPreferences
        let window = createFloatingWindow(with: preferences)

        let hoverView = HoverView(frame: NSRect(origin: .zero, size: preferences.windowSize))
        hoverView.autoresizingMask = [.width, .height]
        window.contentView = hoverView
        self.hoverView = hoverView // Keep reference

        let webView = setupWebView(in: hoverView, with: preferences)
        setupControlButtons(in: hoverView, size: preferences.windowSize)
        setupDragAreas(in: hoverView, size: preferences.windowSize)
        configureHoverBehavior(for: hoverView)

        self.window = window
        self.webView = webView

        // Optionally show immediately, or let AppDelegate decide when
         self.showWindow() // Show window after setup
    }

     private func createFloatingWindow(with preferences: PreferencesManager.Preferences) -> FloatingWindow {
        let windowSize = preferences.windowSize
        let windowOriginOffset = preferences.windowOrigin

        guard let mainScreen = NSScreen.main else {
            logger.error("Could not get main screen information. Using zero origin.")
            // Return a default positioned window? Or handle more gracefully.
            return FloatingWindow(contentRect: NSRect(origin: .zero, size: windowSize), styleMask: [.borderless], backing: .buffered, defer: false)
        }
        let screenFrame = mainScreen.visibleFrame
        let windowX = screenFrame.maxX - windowSize.width - windowOriginOffset.x
        let windowY = screenFrame.minY + windowOriginOffset.y

        let rect = NSRect(x: windowX, y: windowY, width: windowSize.width, height: windowSize.height)

        let window = FloatingWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hasShadow = true
        // window.delegate = self // If window delegate methods are needed (e.g., windowWillClose)

        return window
     }

    private func setupWebView(in hoverView: HoverView, with preferences: PreferencesManager.Preferences) -> WKWebView {
        let webView = WKWebView(frame: hoverView.bounds)
        webView.autoresizingMask = [.width, .height]
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.cornerRadius = preferences.cornerRadius
        webView.layer?.masksToBounds = true
        webView.navigationDelegate = self // Manager handles delegate calls
        hoverView.addSubview(webView) // Add behind controls

        return webView
    }

    private func loadURLInWebView(_ urlString: String) {
        guard let webView = webView else { return }
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            webView.load(request)
            logger.info("Loading URL: \(url.absoluteString)")
        } else {
            logger.error("Invalid URL string: \(urlString)")
            webView.loadHTMLString(createHTML(message: "Invalid URL"), baseURL: nil)
        }
    }

    private func setupControlButtons(in hoverView: HoverView, size windowSize: NSSize) {
        if let reloadImage = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") {
            let button = HoverButton(image: reloadImage, target: self, action: #selector(reloadWebViewAction))
            button.frame = NSRect(
                x: (windowSize.width - buttonSize) / 2,
                y: windowSize.height - buttonSize - padding,
                width: buttonSize, height: buttonSize
            )
            button.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
            button.isBordered = false
            button.wantsLayer = true
            button.alphaValue = 0
            button.contentTintColor = NSColor.secondaryLabelColor

            hoverView.addSubview(button, positioned: .above, relativeTo: webView)
            self.reloadButton = button
        } else {
            logger.warning("Could not load system symbol 'arrow.clockwise'. Reload button unavailable.")
        }
    }

    private func setupDragAreas(in hoverView: HoverView, size windowSize: NSSize) {
        let topDragRect = NSRect(x: 0, y: windowSize.height - borderThickness, width: windowSize.width, height: borderThickness)
        let topArea = NSView(frame: topDragRect)
        topArea.autoresizingMask = [.width, .minYMargin]
        hoverView.addSubview(topArea, positioned: .above, relativeTo: webView)
        self.topDragArea = topArea

        let bottomDragRect = NSRect(x: 0, y: 0, width: windowSize.width, height: borderThickness)
        let bottomArea = NSView(frame: bottomDragRect)
        bottomArea.autoresizingMask = [.width, .maxYMargin]
        hoverView.addSubview(bottomArea, positioned: .above, relativeTo: webView)
        self.bottomDragArea = bottomArea

        let dragRecognizerTop = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        topArea.addGestureRecognizer(dragRecognizerTop)

        let dragRecognizerBottom = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        bottomArea.addGestureRecognizer(dragRecognizerBottom)
    }

     private func configureHoverBehavior(for hoverView: HoverView) {
         // Use weak self to prevent retain cycles in the closure
         hoverView.onHover = { [weak self] isHovering in
             guard let self = self, let reloadButton = self.reloadButton else { return }
             guard let buttonLayer = reloadButton.layer else { return }

             NSAnimationContext.runAnimationGroup { context in
                 context.duration = 0.2
                 context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                 context.allowsImplicitAnimation = true

                 let targetAlpha: CGFloat = isHovering ? 1.0 : 0.0
                 let targetScale: CGFloat = isHovering ? 1.2 : 1.0

                 reloadButton.animator().alphaValue = targetAlpha

                 let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
                 scaleAnimation.toValue = targetScale
                 scaleAnimation.duration = context.duration
                 scaleAnimation.timingFunction = context.timingFunction

                 buttonLayer.add(scaleAnimation, forKey: "transform.scale")
                 buttonLayer.setAffineTransform(CGAffineTransform(scaleX: targetScale, y: targetScale))
             }
         }
     }

    // --- Actions ---

    // Renamed action to avoid conflict with public func
    @objc private func reloadWebViewAction() {
        reloadWebView()
    }

    @objc private func handleDrag(_ sender: NSPanGestureRecognizer) {
        guard let window = window else { return }
        if sender.state == .began {
            let locationInWindow = sender.location(in: nil)
            let fakeMouseDown = NSEvent.mouseEvent(
                with: .leftMouseDown, location: locationInWindow, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0
            )
            if let event = fakeMouseDown {
                window.performDrag(with: event)
            } else {
                logger.error("Could not create synthetic mouse event for dragging.")
            }
        }
    }

    // --- Helpers ---

    private func repositionWindow(_ window: NSWindow, preferences: PreferencesManager.Preferences) {
        guard let mainScreen = NSScreen.main else {
            logger.warning("Cannot get main screen to reposition window.")
            return
        }
        let screenFrame = mainScreen.visibleFrame
        let windowSize = preferences.windowSize
        let windowOriginOffset = preferences.windowOrigin

        let windowX = screenFrame.maxX - windowSize.width - windowOriginOffset.x
        let windowY = screenFrame.minY + windowOriginOffset.y

        let newFrame = NSRect(x: windowX, y: windowY, width: windowSize.width, height: windowSize.height)
        window.setFrame(newFrame, display: false)
    }

    private func createHTML(message: String) -> String {
        // Copied from original AppDelegate
        return """
               <html><body style='font-family: -apple-system, sans-serif; color: #888; background-color: #EEE;
               display: flex; justify-content: center; align-items: center; height: 100vh; text-align: center;'>
               \(message)
               </body></html>
               """
    }


    // MARK: - WKNavigationDelegate Methods

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        switch navigationAction.navigationType {
        case .linkActivated:
            logger.info("Opening external link in browser: \(url.absoluteString)")
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        case .other, .formSubmitted, .backForward, .reload, .formResubmitted:
            if url.scheme == "data" {
                logger.info("Detected data URL navigation, attempting download.")
                handleDataURLDownload(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        @unknown default:
            decisionHandler(.allow)
        }
    }

    private func handleDataURLDownload(_ url: URL) {
        // Copied from original AppDelegate
        let urlString = url.absoluteString
        guard urlString.starts(with: "data:"), let rangeOfBase64 = urlString.range(of: ";base64,") else {
            logger.error("Could not parse data URL for download: \(urlString.prefix(100))")
            return
        }
        let base64String = String(urlString[rangeOfBase64.upperBound...])
        guard let data = Data(base64Encoded: base64String) else {
            logger.error("Failed to decode Base64 data.")
            return
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "file_\(timestamp).csv" // Assume file is a CSV table
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            logger.error("Could not access Downloads directory.")
            return
        }
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            logger.info("File saved successfully to: \(fileURL.path)")
        } catch {
            logger.error("Failed to save downloaded file: \(error.localizedDescription)")
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.warning("WebView process terminated unexpectedly. Attempting to reload.")
        reloadWebView()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("WebView failed provisional navigation: \(error.localizedDescription)")
        webView.loadHTMLString(createHTML(message: "Error loading page: \(error.localizedDescription)"), baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("WebView failed navigation after starting: \(error.localizedDescription)")
    }
}
