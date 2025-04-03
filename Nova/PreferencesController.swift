//
//  PreferencesController.swift
//  Nova
//
//  Created by Luca Vaio on 02/04/2025.
//


import Cocoa
import os.log

class PreferencesController: NSWindowController, NSWindowDelegate {
    // MARK: - Outlets
    private var widthField: NSTextField!
    private var heightField: NSTextField!
    private var xPositionField: NSTextField!
    private var yPositionField: NSTextField!
    private var urlField: NSTextField!
    private var cornerRadiusSlider: NSSlider!
    private var cornerRadiusValueLabel: NSTextField!
    private var previewView: NSView!
    private var saveButton: NSButton!
    private var cancelButton: NSButton!

    
    // MARK: - Properties
    private var currentPreferences: PreferencesManager.Preferences // Store the initial/current state
    private var onSave: ((PreferencesManager.Preferences) -> Void)? // Closure to call on save
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lucavaio.Nova", category: "PreferencesController")

    // Number Formatter for numeric fields
    private lazy var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none // Allow only integers
        formatter.allowsFloats = false
        formatter.minimum = 0
        return formatter
    }()


    // MARK: - Initialization

    init(preferences: PreferencesManager.Preferences, onSave: @escaping (PreferencesManager.Preferences) -> Void) {
        self.currentPreferences = preferences
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nova Preferences"
        window.center()
        // Prevent resizing
        window.styleMask.remove(.resizable)

        super.init(window: window)

        // Set the window delegate to self to handle closure
        window.delegate = self
        setupUI()
        loadInitialValues()
        updatePreview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    // MARK: - UI Setup

    private func setupUI() {
        guard let window = self.window, let contentView = window.contentView else {
            logger.error("Window or ContentView not available for UI Setup.")
            return
        }

        let mainStackView = NSStackView()
        mainStackView.orientation = .vertical
        mainStackView.alignment = .leading // Align content to the leading edge
        mainStackView.spacing = 18 // Consistent spacing between sections
        mainStackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStackView)

        // --- Window Size Section ---
        let sizeSectionLabel = NSTextField(labelWithString: "Window Size")
        sizeSectionLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

        let sizeStackView = NSStackView()
        sizeStackView.orientation = .horizontal
        sizeStackView.spacing = 8
        widthField = createTextField(width: 60)
        heightField = createTextField(width: 60)
        sizeStackView.addArrangedSubview(NSTextField(labelWithString: "Width:"))
        sizeStackView.addArrangedSubview(widthField)
        sizeStackView.addArrangedSubview(NSTextField(labelWithString: "Height:"))
        sizeStackView.addArrangedSubview(heightField)
        sizeStackView.addArrangedSubview(NSView()) // Spacer to push left

        // --- Window Position Section (Offset from Bottom-Right) ---
        let positionSectionLabel = NSTextField(labelWithString: "Window Position")
        positionSectionLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

        let positionStackView = NSStackView()
        positionStackView.orientation = .horizontal
        positionStackView.spacing = 8
        xPositionField = createTextField(width: 60)
        yPositionField = createTextField(width: 60)
        positionStackView.addArrangedSubview(NSTextField(labelWithString: "X Offset:"))
        positionStackView.addArrangedSubview(xPositionField)
        positionStackView.addArrangedSubview(NSTextField(labelWithString: "Y Offset:"))
        positionStackView.addArrangedSubview(yPositionField)
        positionStackView.addArrangedSubview(NSView()) // Spacer

        // --- WebView URL Section ---
        let urlSectionLabel = NSTextField(labelWithString: "WebView URL")
        urlSectionLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

        urlField = NSTextField()
        urlField.placeholderString = "e.g., http://localhost:8080"
        urlField.lineBreakMode = .byTruncatingTail
        urlField.translatesAutoresizingMaskIntoConstraints = false // Needed for width constraint

        // --- Corner Radius Section ---
        let cornerRadiusSectionLabel = NSTextField(labelWithString: "Window Corner Radius")
        cornerRadiusSectionLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

        let radiusStackView = NSStackView()
        radiusStackView.orientation = .horizontal
        radiusStackView.spacing = 8
        radiusStackView.alignment = .centerY // Align slider and label vertically

        cornerRadiusSlider = NSSlider(value: 0, minValue: 0, maxValue: 50, target: self, action: #selector(cornerRadiusChanged(_:)))
        cornerRadiusSlider.translatesAutoresizingMaskIntoConstraints = false // For width constraint

        cornerRadiusValueLabel = NSTextField(labelWithString: "0 px")
        cornerRadiusValueLabel.alignment = .right
        cornerRadiusValueLabel.translatesAutoresizingMaskIntoConstraints = false // For width constraint

        radiusStackView.addArrangedSubview(cornerRadiusSlider)
        radiusStackView.addArrangedSubview(cornerRadiusValueLabel)

        // --- Preview Section ---
        previewView = NSView()
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.controlColor.blended(withFraction: 0.5, of: .black)?.cgColor
        previewView.layer?.borderColor = NSColor.secondaryLabelColor.cgColor
        previewView.layer?.borderWidth = 1.0
        previewView.translatesAutoresizingMaskIntoConstraints = false // Essential for constraints

        // --- Buttons Section ---
        let buttonStackView = NSStackView()
        buttonStackView.orientation = .horizontal
        buttonStackView.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal) // Flexible space to push buttons right

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelButton.bezelStyle = .rounded

        saveButton = NSButton(title: "Apply", target: self, action: #selector(saveAction))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Enter/Return key triggers Apply

        buttonStackView.addArrangedSubview(spacer)
        buttonStackView.addArrangedSubview(cancelButton)
        buttonStackView.addArrangedSubview(saveButton)
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false // For width constraint

        // --- Add sections to main stack ---
        mainStackView.addArrangedSubview(sizeSectionLabel)
        mainStackView.addArrangedSubview(sizeStackView)
        mainStackView.setCustomSpacing(10, after: sizeStackView)

        mainStackView.addArrangedSubview(positionSectionLabel)
        mainStackView.addArrangedSubview(positionStackView)
        mainStackView.setCustomSpacing(10, after: positionStackView)

        mainStackView.addArrangedSubview(urlSectionLabel)
        mainStackView.addArrangedSubview(urlField)
        mainStackView.setCustomSpacing(10, after: urlField)

        mainStackView.addArrangedSubview(cornerRadiusSectionLabel)
        mainStackView.addArrangedSubview(radiusStackView)
        mainStackView.setCustomSpacing(15, after: radiusStackView)

        mainStackView.addArrangedSubview(previewView)

        let verticalSpacer = NSView()
        verticalSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        mainStackView.addArrangedSubview(verticalSpacer)

        mainStackView.addArrangedSubview(buttonStackView)

        // --- Auto Layout Constraints ---
        NSLayoutConstraint.activate([
            // Main Stack View constraints
            mainStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Width constraints
            urlField.widthAnchor.constraint(equalTo: mainStackView.widthAnchor, constant: -mainStackView.edgeInsets.left - mainStackView.edgeInsets.right), // Fill width minus padding
            cornerRadiusSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            cornerRadiusValueLabel.widthAnchor.constraint(equalToConstant: 50), // Fixed width for label consistency
            buttonStackView.widthAnchor.constraint(equalTo: mainStackView.widthAnchor, constant: -mainStackView.edgeInsets.left - mainStackView.edgeInsets.right),

            // Preview View constraints
            previewView.heightAnchor.constraint(equalToConstant: 100),
            previewView.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            previewView.centerXAnchor.constraint(equalTo: mainStackView.centerXAnchor), // Center preview horizontally
            previewView.leadingAnchor.constraint(greaterThanOrEqualTo: mainStackView.leadingAnchor, constant: mainStackView.edgeInsets.left),
            previewView.trailingAnchor.constraint(lessThanOrEqualTo: mainStackView.trailingAnchor, constant: -mainStackView.edgeInsets.right)
        ])
    }

    // Helper to create consistently styled text fields
    private func createTextField(width: CGFloat) -> NSTextField {
        let textField = NSTextField()
        textField.formatter = numberFormatter
        textField.target = self // Trigger updatePreview on change
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.widthAnchor.constraint(equalToConstant: width).isActive = true
        return textField
    }

    private func loadInitialValues() {
        widthField.stringValue = "\(Int(currentPreferences.windowSize.width))"
        heightField.stringValue = "\(Int(currentPreferences.windowSize.height))"
        xPositionField.stringValue = "\(Int(currentPreferences.windowOrigin.x))"
        yPositionField.stringValue = "\(Int(currentPreferences.windowOrigin.y))"
        urlField.stringValue = currentPreferences.webViewURL
        cornerRadiusSlider.doubleValue = Double(currentPreferences.cornerRadius)
        cornerRadiusValueLabel.stringValue = "\(Int(currentPreferences.cornerRadius)) px"
    }


    // MARK: - Actions

    @objc private func cornerRadiusChanged(_ sender: NSSlider) {
        let radius = CGFloat(sender.doubleValue)
        cornerRadiusValueLabel.stringValue = "\(Int(radius)) px"
        updatePreview()
    }

    @objc private func updatePreview() {
        let radius = CGFloat(cornerRadiusSlider.doubleValue)
        previewView.layer?.cornerRadius = radius
        previewView.needsDisplay = true // Ensure layer changes are rendered
    }

    @objc private func cancelAction() {
        logger.debug("Cancel button clicked.")
        window?.close() // Close the window without saving
    }

    @objc private func saveAction() {
        logger.debug("Apply button clicked.")
        // Validate input before saving
        guard let widthValue = Int(widthField.stringValue), widthValue > 0,
              let heightValue = Int(heightField.stringValue), heightValue > 0,
              let xValue = Int(xPositionField.stringValue), // Allow zero and negative offsets
              let yValue = Int(yPositionField.stringValue),
              let url = URL(string: urlField.stringValue), url.host != nil || url.scheme == "file" // Basic URL validation
        else {
            logger.warning("Invalid input detected during save attempt.")
            showValidationError()
            return
        }

        let updatedPreferences = PreferencesManager.Preferences(
            windowSize: NSSize(width: widthValue, height: heightValue),
            windowOrigin: NSPoint(x: xValue, y: yValue),
            webViewURL: urlField.stringValue,
            cornerRadius: CGFloat(cornerRadiusSlider.doubleValue)
        )

        // Call the save handler provided by AppDelegate
        logger.info("Saving updated preferences.")
        onSave?(updatedPreferences)
    }

    // Show a simple validation error alert
    private func showValidationError() {
        let alert = NSAlert()
        alert.messageText = "Invalid Preferences"
        alert.informativeText = "Please check the values provided."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        guard let window = self.window else {
            logger.error("Cannot show validation alert: Window not found.")
            return
        }
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}
