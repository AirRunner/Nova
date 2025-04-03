//
//  PreferencesManager.swift
//  Nova
//
//  Created by Luca Vaio on 03/04/2025.
//


import Foundation
import AppKit // For NSSize, NSPoint, CGFloat
import os.log

@MainActor // Ensure access to preferences happens on the main thread if needed by UI
class PreferencesManager {

    // Define the Preferences structure within the manager
    struct Preferences: Codable {
        var windowSize: NSSize
        var windowOrigin: NSPoint // Stored as offset from bottom-right of *visible* screen area
        var webViewURL: String
        var cornerRadius: CGFloat

        static let defaults = Preferences(
            windowSize: NSSize(width: 440, height: 540),
            windowOrigin: NSPoint(x: 30, y: 30), // Offset from screen bottom-right corner
            webViewURL: "http://localhost:8080/",
            cornerRadius: 30
        )

        // Helper to encode/decode NSSize and NSPoint which aren't directly Codable
        private enum CodingKeys: String, CodingKey {
            case windowWidth, windowHeight, windowOriginX, windowOriginY, webViewURL, cornerRadius
        }

        init(windowSize: NSSize, windowOrigin: NSPoint, webViewURL: String, cornerRadius: CGFloat) {
            self.windowSize = windowSize
            self.windowOrigin = windowOrigin
            self.webViewURL = webViewURL
            self.cornerRadius = cornerRadius
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let width = try container.decode(CGFloat.self, forKey: .windowWidth)
            let height = try container.decode(CGFloat.self, forKey: .windowHeight)
            let x = try container.decode(CGFloat.self, forKey: .windowOriginX)
            let y = try container.decode(CGFloat.self, forKey: .windowOriginY)
            self.windowSize = NSSize(width: width, height: height)
            self.windowOrigin = NSPoint(x: x, y: y)
            self.webViewURL = try container.decode(String.self, forKey: .webViewURL)
            self.cornerRadius = try container.decode(CGFloat.self, forKey: .cornerRadius)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(windowSize.width, forKey: .windowWidth)
            try container.encode(windowSize.height, forKey: .windowHeight)
            try container.encode(windowOrigin.x, forKey: .windowOriginX)
            try container.encode(windowOrigin.y, forKey: .windowOriginY)
            try container.encode(webViewURL, forKey: .webViewURL)
            try container.encode(cornerRadius, forKey: .cornerRadius)
        }
    }

    // --- Properties ---
    private(set) var currentPreferences: Preferences
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lucavaio.Nova", category: "PreferencesManager")
    private let preferencesFileURL: URL

    // --- Initialization ---
    init() {
        self.preferencesFileURL = Self.defaultPreferencesFilePath()
        self.currentPreferences = Preferences.defaults // Start with defaults

        // Load existing preferences, potentially overwriting defaults
        self.currentPreferences = loadPreferencesFromFile()
    }

    // --- Public Methods ---
    func savePreferences(_ newPreferences: Preferences) {
        // Update in-memory preferences
        self.currentPreferences = newPreferences

        // Save to disk
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml // Or .binary
            let data = try encoder.encode(newPreferences)
            try data.write(to: preferencesFileURL, options: .atomic)
            logger.info("Saved preferences to \(self.preferencesFileURL.path)")
        } catch {
            logger.error("Failed to save preferences: \(error.localizedDescription)")
        }
    }

    // --- Private Helpers ---
    private func loadPreferencesFromFile() -> Preferences {
        guard FileManager.default.fileExists(atPath: preferencesFileURL.path(percentEncoded: false)) else {
             logger.info("No preferences file found at \(self.preferencesFileURL.path). Using and saving defaults.")
             // Save defaults if file doesn't exist
             savePreferences(Preferences.defaults)
             return Preferences.defaults
         }

        do {
            let data = try Data(contentsOf: preferencesFileURL)
            let decoder = PropertyListDecoder()
            let loadedPreferences = try decoder.decode(Preferences.self, from: data)
            logger.info("Loaded preferences from \(self.preferencesFileURL.path)")
            return loadedPreferences
        } catch {
            logger.error("Failed to decode preferences: \(error.localizedDescription). Using defaults.")
            // Consider backing up the corrupted file here before overwriting with defaults
            savePreferences(Preferences.defaults) // Overwrite potentially corrupted file with defaults
            return Preferences.defaults
        }
    }

    private static func defaultPreferencesFilePath() -> URL {
        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Cannot access Application Support directory.")
        }
        let novaDir = appSupportDir.appendingPathComponent("Nova", isDirectory: true)

        // Ensure the Nova directory exists
        if !fileManager.fileExists(atPath: novaDir.path(percentEncoded: false)) {
            do {
                try fileManager.createDirectory(at: novaDir, withIntermediateDirectories: true, attributes: nil)
                // Log creation, maybe handle error slightly differently
            } catch {
                // Log error, fatalError might be too harsh if defaults can still work in memory
                print("Failed to create preferences directory: \(error.localizedDescription)")
            }
        }
        return novaDir.appendingPathComponent("Preferences.plist")
    }
}
