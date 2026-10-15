import AppKit

/// Keep NSSlider's layout, tracking and accessibility pipeline intact. Replacing
/// draw(_:) bypasses cell geometry preparation and can break direct-touch input.
@MainActor final class RoundedTouchBarSlider: NSSlider {
    private(set) var thumbPressed = false
    private var glassThumb: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = RoundedTouchBarSliderCell()
        prepareGlassThumb()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        cell = RoundedTouchBarSliderCell()
        prepareGlassThumb()
    }

    private func prepareGlassThumb() {
        if #available(macOS 26.0, *) {
            let glass = TouchBarGlassThumb(frame: .zero)
            glass.style = .clear
            glass.cornerRadius = 9
            glass.isHidden = true
            addSubview(glass)
            glassThumb = glass
        }
    }

    // NSSliderCell owns touch tracking. The effect is only a visual overlay;
    // it never takes touches or sends extra fan-speed actions.
    func setThumbPressed(_ pressed: Bool) {
        let next = pressed && isEnabled
        guard thumbPressed != next else { return }
        thumbPressed = next
        glassThumb?.isHidden = !next
        needsDisplay = true
    }

    override var isEnabled: Bool {
        didSet { if !isEnabled { setThumbPressed(false) } }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setThumbPressed(false) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if thumbPressed, let cell = cell as? NSSliderCell, let glassThumb {
            let frame = cell.knobRect(flipped: isFlipped).insetBy(dx: 1, dy: 1)
            if glassThumb.frame != frame { glassThumb.frame = frame }
        }
    }

    var displaysGlassThumb: Bool { thumbPressed && glassThumb != nil }
}

@available(macOS 26.0, *)
@MainActor private final class TouchBarGlassThumb: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor private final class RoundedTouchBarSliderCell: NSSliderCell {
    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        let tracking = super.startTracking(at: startPoint, in: controlView)
        (controlView as? RoundedTouchBarSlider)?.setThumbPressed(tracking)
        return tracking
    }

    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint,
                               in controlView: NSView, mouseIsUp flag: Bool) {
        defer { (controlView as? RoundedTouchBarSlider)?.setThumbPressed(false) }
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
    }

    override func trackMouse(with event: NSEvent, in cellFrame: NSRect,
                             of controlView: NSView, untilMouseUp flag: Bool) -> Bool {
        defer { (controlView as? RoundedTouchBarSlider)?.setThumbPressed(false) }
        return super.trackMouse(with: event, in: cellFrame, of: controlView, untilMouseUp: flag)
    }

    override var knobThickness: CGFloat { 28 }

    override func knobRect(flipped: Bool) -> NSRect {
        let native = super.knobRect(flipped: flipped)
        let bounds = controlView?.bounds ?? .zero
        let center = bounds.width >= 28
            ? min(bounds.maxX - 14, max(bounds.minX + 14, native.midX)) : native.midX
        // AppKit invalidates the old/new knob rectangles during tracking. The
        // returned rect must enclose our entire capsule, including antialiasing.
        return NSRect(x: center - 14, y: native.midY - 10, width: 28, height: 20)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        // The stock cell clears around its knob as part of drawing the bar. Our
        // custom bar must also erase that area, not just paint the thin track.
        NSColor(white: 0.25, alpha: 1).setFill()
        (controlView?.bounds ?? rect).fill()
        let track = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
        NSColor.white.withAlphaComponent(isEnabled ? 0.22 : 0.12).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        let filledWidth = min(track.width, max(0, knobRect(flipped: flipped).midX - track.minX))
        let fill = NSRect(x: track.minX, y: track.minY, width: filledWidth, height: 6)
        NSColor.white.withAlphaComponent(isEnabled ? 0.85 : 0.28).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        if (controlView as? RoundedTouchBarSlider)?.displaysGlassThumb == true { return }
        let thumb = knobRect.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: thumb, xRadius: 9, yRadius: 9)
        NSColor(white: isEnabled ? 0.94 : 0.58, alpha: 1).setFill()
        path.fill()
    }
}
