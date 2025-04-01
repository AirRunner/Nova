//
//  View.swift
//  Nova
//
//  Created by Luca Vaio on 02/04/2025.
//


import Cocoa

class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}

class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove existing tracking areas before adding a new one
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
        onHover?(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

class HoverButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
