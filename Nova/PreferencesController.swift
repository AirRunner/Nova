//
//  PreferencesController.swift
//  Nova
//
//  Created by Luca Vaio on 02/04/2025.
//


import Cocoa
import WebKit

class PreferencesController: NSWindowController {
    // MARK: - Outlets
    private var widthField: NSTextField!
    private var heightField: NSTextField!
    private var xPositionField: NSTextField!
    private var yPositionField: NSTextField!
    private var urlField: NSTextField!
    private var cornerRadiusSlider: NSSlider!
    private var cornerRadiusLabel: NSTextField!
    private var previewView: NSView!
    
    // MARK: - Properties
    private var preferences: AppDelegate.Preferences
    private var onSave: ((AppDelegate.Preferences) -> Void)?
    
    // MARK: - Initialization
    
    init(preferences: AppDelegate.Preferences, onSave: @escaping (AppDelegate.Preferences) -> Void) {
        self.preferences = preferences
        self.onSave = onSave
        
        // Create the window programmatically
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nova Preferences"
        window.center()
        
        super.init(window: window)
        
        // Set up the UI
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        guard let window = self.window else { return }
        
        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = contentView
        
        // Create UI elements
        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        contentView.addSubview(stackView)
        
        // Window Size Section
        let sizeLabel = NSTextField(labelWithString: "Window Size")
        sizeLabel.font = NSFont.boldSystemFont(ofSize: 14)
        
        let sizeStackView = NSStackView()
        sizeStackView.orientation = .horizontal
        sizeStackView.spacing = 8
        
        widthField = createTextField(value: Int(preferences.windowSize.width), width: 60)
        heightField = createTextField(value: Int(preferences.windowSize.height), width: 60)
        
        sizeStackView.addArrangedSubview(NSTextField(labelWithString: "Width :"))
        sizeStackView.addArrangedSubview(widthField)
        sizeStackView.addArrangedSubview(NSTextField(labelWithString: "Height :"))
        sizeStackView.addArrangedSubview(heightField)
        
        // Window Position Section
        let positionLabel = NSTextField(labelWithString: "Window Position")
        positionLabel.font = NSFont.boldSystemFont(ofSize: 14)
        
        let positionStackView = NSStackView()
        positionStackView.orientation = .horizontal
        positionStackView.spacing = 8
        
        xPositionField = createTextField(value: Int(preferences.windowOrigin.x), width: 60)
        yPositionField = createTextField(value: Int(preferences.windowOrigin.y), width: 60)
        
        positionStackView.addArrangedSubview(NSTextField(labelWithString: "X :"))
        positionStackView.addArrangedSubview(xPositionField)
        positionStackView.addArrangedSubview(NSTextField(labelWithString: "Y :"))
        positionStackView.addArrangedSubview(yPositionField)
        
        // WebView URL Section
        let urlLabel = NSTextField(labelWithString: "WebView URL")
        urlLabel.font = NSFont.boldSystemFont(ofSize: 14)
        
        urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        urlField.stringValue = preferences.webViewURL
        urlField.placeholderString = "http://localhost:8080"
        urlField.target = self
        urlField.action = #selector(updatePreview)
        
        // Corner Radius Section
        let cornerRadiusLabel = NSTextField(labelWithString: "Corner Radius:")
        cornerRadiusLabel.font = NSFont.boldSystemFont(ofSize: 14)
        
        let cornerRadiusStackView = NSStackView()
        cornerRadiusStackView.orientation = .vertical
        cornerRadiusStackView.spacing = 8
        cornerRadiusStackView.alignment = .leading
        
        cornerRadiusSlider = NSSlider(value: Double(preferences.cornerRadius), 
                                     minValue: 0, 
                                     maxValue: 50, 
                                     target: self, 
                                     action: #selector(cornerRadiusChanged(_:)))
        cornerRadiusSlider.frame = NSRect(x: 0, y: 0, width: 400, height: 24)
        
        self.cornerRadiusLabel = NSTextField(labelWithString: "\(Int(preferences.cornerRadius)) px")
        
        let sliderStackView = NSStackView()
        sliderStackView.orientation = .horizontal
        sliderStackView.spacing = 16
        sliderStackView.addArrangedSubview(cornerRadiusSlider)
        sliderStackView.addArrangedSubview(self.cornerRadiusLabel)
        
        cornerRadiusStackView.addArrangedSubview(sliderStackView)
        
        // Preview Section
        previewView = NSView(frame: NSRect(x: 100, y: 0, width: 200, height: 100))
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        previewView.layer?.cornerRadius = preferences.cornerRadius
        
        // Buttons
        let buttonStackView = NSStackView()
        buttonStackView.orientation = .horizontal
        buttonStackView.spacing = 8
        
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelButton.bezelStyle = .rounded
        
        let saveButton = NSButton(title: "Apply", target: self, action: #selector(saveAction))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Return key
        
        buttonStackView.addArrangedSubview(NSView())
        buttonStackView.addView(cancelButton, in: .trailing)
        buttonStackView.addView(saveButton, in: .trailing)
        
        // Add all sections to the main stack view
        stackView.addArrangedSubview(sizeLabel)
        stackView.addArrangedSubview(sizeStackView)
        stackView.addArrangedSubview(positionLabel)
        stackView.addArrangedSubview(positionStackView)
        stackView.addArrangedSubview(urlLabel)
        stackView.addArrangedSubview(urlField)
        stackView.addArrangedSubview(cornerRadiusLabel)
        stackView.addArrangedSubview(cornerRadiusStackView)
        stackView.addArrangedSubview(previewView)
        
        // Use hugging/compression resistance or constraints for flexible spacing
        let spacer = NSView()
        stackView.addArrangedSubview(spacer)
        // Make the spacer flexible vertically
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        stackView.addArrangedSubview(buttonStackView)
        
        // Auto Layout Constraints
        stackView.translatesAutoresizingMaskIntoConstraints = false
        urlField.translatesAutoresizingMaskIntoConstraints = false
        cornerRadiusSlider.translatesAutoresizingMaskIntoConstraints = false
        previewView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Main Stack View constraints
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            // Specific Widths/Heights
            urlField.widthAnchor.constraint(equalTo: stackView.widthAnchor), // Make URL field fill width
            cornerRadiusSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 250), // Min width for slider
            previewView.heightAnchor.constraint(equalToConstant: 100),
            previewView.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            previewView.centerXAnchor.constraint(equalTo: stackView.centerXAnchor),
            
            // Ensure button stack view spans the width
            buttonStackView.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }
    
    private func createTextField(value: Int, width: CGFloat) -> NSTextField {
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        textField.stringValue = "\(value)"
        textField.formatter = NumberFormatter()
        textField.target = self
        textField.action = #selector(updatePreview)
        
        // Set width constraint for the text field itself
        textField.widthAnchor.constraint(equalToConstant: width).isActive = true
        
        return textField
    }
    
    // MARK: - Actions
    
    @objc private func cornerRadiusChanged(_ sender: NSSlider) {
        let radius = CGFloat(sender.doubleValue)
        cornerRadiusLabel.stringValue = "\(Int(radius)) px"
        previewView.layer?.cornerRadius = radius
    }
    
    @objc private func updatePreview() {
        // Update preview based on current settings
        previewView.layer?.cornerRadius = CGFloat(cornerRadiusSlider.doubleValue)
        previewView.needsDisplay = true
    }
    
    @objc private func cancelAction() {
        window?.close()
    }
    
    @objc private func saveAction() {
        // Validate input
        guard let widthValue = Int(widthField.stringValue),
              let heightValue = Int(heightField.stringValue),
              let xValue = Int(xPositionField.stringValue),
              let yValue = Int(yPositionField.stringValue),
              !urlField.stringValue.isEmpty else {
            
            // Show error alert for invalid input
            let alert = NSAlert()
            alert.messageText = "Invalid Input"
            alert.informativeText = "Please check your values and try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window!) { _ in }
            return
        }
        
        // Update preferences
        let updatedPreferences = AppDelegate.Preferences(
            windowSize: NSSize(width: widthValue, height: heightValue),
            windowOrigin: NSPoint(x: xValue, y: yValue),
            webViewURL: urlField.stringValue,
            cornerRadius: CGFloat(cornerRadiusSlider.doubleValue)
        )
        
        // Call the save handler
        onSave?(updatedPreferences)
    }
}
