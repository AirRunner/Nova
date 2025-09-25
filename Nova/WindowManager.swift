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
        guard !isWindowVisible else { return }

        // Reposition before showing, in case screen setup changed
        repositionWindow(window, preferences: preferencesManager.currentPreferences)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true) // Bring the app to the front
        logger.debug("Window shown.")
    }

    func hideWindow() {
        guard let window = window else { return }
        guard isWindowVisible else { return }

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
            y: screenFrame.minY + preferences.windowOrigin.y,
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

        self.showWindow() // Show window after setup
    }

     private func createFloatingWindow(with preferences: PreferencesManager.Preferences) -> FloatingWindow {
        let windowSize = preferences.windowSize
        let windowOriginOffset = preferences.windowOrigin

        guard let mainScreen = NSScreen.main else {
            logger.error("Could not get main screen information. Using zero origin.")
            // Return a default positioned window
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
            button.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
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
        topArea.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        hoverView.addSubview(topArea, positioned: .above, relativeTo: webView)
        self.topDragArea = topArea

        let bottomDragRect = NSRect(x: 0, y: 0, width: windowSize.width, height: borderThickness)
        let bottomArea = NSView(frame: bottomDragRect)
        bottomArea.autoresizingMask = [.width]
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
        return """
               <html><body style='font-family: -apple-system, sans-serif; color: #888; background-color: #EEE;
               display: flex; justify-content: center; align-items: center; margin: 0; height: 100vh; text-align: center;'>
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
        let urlString = url.absoluteString
        guard urlString.starts(with: "data:"), let rangeOfBase64 = urlString.range(of: ";base64,") else {
            logger.error("Could not parse data URL for download: \(urlString.prefix(100))")
            return
        }
        
        // Extract MIME type from data URL
        let mimeTypeSection = String(urlString[urlString.index(urlString.startIndex, offsetBy: 5)..<rangeOfBase64.lowerBound])
        let mimeType = mimeTypeSection.isEmpty ? "text/plain" : mimeTypeSection
        
        let base64String = String(urlString[rangeOfBase64.upperBound...])
        guard let data = Data(base64Encoded: base64String) else {
            logger.error("Failed to decode Base64 data.")
            return
        }
        
        // Detect file type and extension
        let fileExtension = detectFileType(from: mimeType, data: data)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "file_\(timestamp).\(fileExtension)"
        
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            logger.error("Could not access Downloads directory.")
            return
        }
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            logger.info("File saved successfully to: \(fileURL.path) with detected type: \(fileExtension)")
        } catch {
            logger.error("Failed to save downloaded file: \(error.localizedDescription)")
        }
    }
    
    private func detectFileType(from mimeType: String, data: Data) -> String {
        // First, try to determine type from MIME type
        let normalizedMimeType = mimeType.lowercased()
        
        switch normalizedMimeType {
        case let mime where mime.contains("pdf"):
            return "pdf"
        case let mime where mime.contains("xml"):
            return "xml"
        case let mime where mime.contains("html"):
            return "html"
        case let mime where mime.contains("json"):
            return "json"
        case let mime where mime.contains("csv"):
            return "csv"
        case "application/pdf":
            return "pdf"
        case "text/xml", "application/xml":
            return "xml"
        case "text/html", "application/xhtml+xml":
            return "html"
        case "application/json", "text/json":
            return "json"
        case "text/csv", "application/csv":
            return "csv"
        default:
            break
        }
        
        // Check for PDF first (binary format)
        if data.count >= 4 {
            let pdfHeader = data.prefix(4)
            if let headerString = String(data: pdfHeader, encoding: .ascii), headerString == "%PDF" {
                return "pdf"
            }
        }
        
        // If MIME type doesn't give us a clear answer, analyze the content
        guard let content = String(data: data, encoding: .utf8) else {
            // If we can't decode as UTF-8, check if it might be a binary PDF
            if data.count >= 8 {
                let headerBytes = data.prefix(8)
                if headerBytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { // %PDF in bytes
                    return "pdf"
                }
            }
            logger.warning("Could not decode data as UTF-8 text. Defaulting to txt.")
            return "txt"
        }
        
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for XML (including HTML as a subset)
        if trimmedContent.hasPrefix("<?xml") || 
           trimmedContent.contains("<?xml") ||
           (trimmedContent.hasPrefix("<") && trimmedContent.hasSuffix(">") && trimmedContent.contains("</")) {
            
            // Distinguish between HTML and XML
            let lowercaseContent = trimmedContent.lowercased()
            if lowercaseContent.contains("<!doctype html") ||
               lowercaseContent.contains("<html") ||
               lowercaseContent.contains("<head>") ||
               lowercaseContent.contains("<body>") {
                return "html"
            } else {
                return "xml"
            }
        }
        
        // Check for JSON
        if (trimmedContent.hasPrefix("{") && trimmedContent.hasSuffix("}")) ||
           (trimmedContent.hasPrefix("[") && trimmedContent.hasSuffix("]")) {
            // Try to validate it's actually JSON by attempting to parse
            do {
                _ = try JSONSerialization.jsonObject(with: data, options: [])
                return "json"
            } catch {
                // Not valid JSON, continue checking
            }
        }
        
        // Improved CSV detection
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        if !lines.isEmpty {
            let firstLine = lines[0]
            
            // Check for quoted CSV fields (more flexible pattern that handles HTML entities and mixed content)
            let quotedFieldPattern = #"\"[^\"]*\""#
            let quotedFieldRegex = try? NSRegularExpression(pattern: quotedFieldPattern)
            let quotedMatches = quotedFieldRegex?.numberOfMatches(in: firstLine, range: NSRange(firstLine.startIndex..., in: firstLine)) ?? 0
            
            // Count separators
            let commaCount = firstLine.components(separatedBy: ",").count - 1
            let semicolonCount = firstLine.components(separatedBy: ";").count - 1
            let tabCount = firstLine.components(separatedBy: "\t").count - 1
            
            // Enhanced CSV detection logic
            let hasMultipleColumns = commaCount > 0 || semicolonCount > 0 || tabCount > 0
            let hasQuotedFields = quotedMatches > 0
            
            // Additional CSV indicators
            let startsWithQuote = firstLine.hasPrefix("\"")
            let containsCommaAfterQuote = firstLine.contains("\",")
            let containsHTMLEntities = firstLine.contains("&quot;") || firstLine.contains("&amp;") || firstLine.contains("&lt;") || firstLine.contains("&gt;")
            
            // Strong CSV indicators
            let isLikelyCSV = hasQuotedFields || 
                             (startsWithQuote && containsCommaAfterQuote) ||
                             (hasMultipleColumns && (quotedMatches > 0 || containsHTMLEntities))
            
            if isLikelyCSV {
                // Determine the most likely separator
                let separator = commaCount >= semicolonCount && commaCount >= tabCount ? "," :
                               semicolonCount >= tabCount ? ";" : "\t"
                let separatorCount = separator == "," ? commaCount : 
                                   separator == ";" ? semicolonCount : tabCount
                
                // For single line with strong CSV indicators
                if lines.count == 1 && (hasQuotedFields || separatorCount >= 1) {
                    return "csv"
                }
                
                // For multiple lines, use more lenient consistency checking
                if lines.count > 1 {
                    var consistentLineCount = 0
                    
                    // Check first few lines for CSV patterns
                    for line in lines.prefix(5) {
                        let lineCommaCount = line.components(separatedBy: separator).count - 1
                        let lineQuotedMatches = quotedFieldRegex?.numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
                        
                        // A line is consistent if it has similar separator count OR has quoted fields
                        if abs(lineCommaCount - separatorCount) <= 2 || lineQuotedMatches > 0 || line.contains("&quot;") {
                            consistentLineCount += 1
                        }
                    }
                    
                    // If most lines look CSV-like, classify as CSV
                    let totalLinesToCheck = min(5, lines.count)
                    if consistentLineCount >= max(1, totalLinesToCheck / 2) {
                        return "csv"
                    }
                }
            }
        }
        
        // Default to txt if no specific type detected
        logger.info("Could not detect specific file type from MIME type '\(mimeType)' or content analysis. Using txt.")
        return "txt"
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
