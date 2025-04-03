//
//  Views.swift
//  Nova
//
//  Created by Luca Vaio on 02/04/2025.
//


import Cocoa

// Custom NSWindow subclass to allow borderless windows to become key window (receive events)
class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}

// Custom NSView subclass that detects mouse hover events
class HoverView: NSView {
    // Closure property to notify when the hover state changes
    var onHover: ((_ isHovering: Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    // Recalculate view's tracking areas when bounds change
    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = self.trackingArea {
            removeTrackingArea(existingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        self.trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

// Custom NSButton subclass that shows a pointing hand cursor on hover
class HoverButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(self.bounds, cursor: .pointingHand)
    }
}
