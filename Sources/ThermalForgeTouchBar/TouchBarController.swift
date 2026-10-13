import AppKit
import ObjectiveC
import Darwin
import os

public enum TouchBarMode: Int, Sendable { case summer = 0, manual = 1, automatic = 2 }

public struct TouchBarReading: Equatable, Sendable {
    public var cpuTemperature: Float?
    public var gpuTemperature: Float?
    public var actualRPM: Int?
    public var batteryWatts: Double?
    public var charging: Bool
    public var manual: Bool
    public var mode: TouchBarMode?
    public var targetRPM: Double
    public var minRPM: Double
    public var maxRPM: Double
    public var safetyOverride: Bool
    public var controlAvailable: Bool
    public var fahrenheit: Bool

    public init(cpuTemperature: Float? = nil, gpuTemperature: Float? = nil,
                actualRPM: Int? = nil, batteryWatts: Double? = nil,
                charging: Bool = false, manual: Bool = false,
                targetRPM: Double = 2000, minRPM: Double = 1200, maxRPM: Double = 7200,
                safetyOverride: Bool = false, controlAvailable: Bool = false,
                fahrenheit: Bool = false, mode: TouchBarMode? = nil) {
        self.cpuTemperature = cpuTemperature; self.gpuTemperature = gpuTemperature
        self.actualRPM = actualRPM; self.batteryWatts = batteryWatts
        self.charging = charging; self.manual = manual; self.targetRPM = targetRPM
        self.minRPM = minRPM; self.maxRPM = maxRPM
        self.safetyOverride = safetyOverride; self.controlAvailable = controlAvailable
        self.fahrenheit = fahrenheit; self.mode = mode
    }

    public func temperatureText(_ value: Float?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int((fahrenheit ? value * 9 / 5 + 32 : value).rounded()))°"
    }
    public var powerText: String {
        guard let batteryWatts, batteryWatts.isFinite else { return "Battery —" }
        return "\(charging ? "Charge" : "Battery") \(Int(abs(batteryWatts).rounded())) W"
    }
}

public enum TouchBarAction: Equatable { case summer, manual, automatic, speed(Double) }

/// Isolated so tests exercise lifecycle and actions without touching the system bar.
@MainActor public protocol TouchBarBackend: AnyObject {
    var available: Bool { get }
    func add(_ item: NSTouchBarItem) -> Bool
    func remove(_ item: NSTouchBarItem)
    func present(_ bar: NSTouchBar, entry: NSTouchBarItem.Identifier) -> Bool
    func dismiss(_ bar: NSTouchBar)
}

/// Runtime lookup: no private framework is linked at build time. Missing methods
/// disable only Touch Bar; fan control and the menu bar app keep working.
@MainActor public final class SystemTouchBarBackend: TouchBarBackend {
    private let library: UnsafeMutableRawPointer?
    private var lastEntry: NSTouchBarItem.Identifier?
    private typealias Presence = @convention(c) (CFString, Bool) -> Void
    private var presence: Presence? {
        guard let library, let symbol = dlsym(library, "DFRElementSetControlStripPresenceForIdentifier") else { return nil }
        return unsafeBitCast(symbol, to: Presence.self)
    }
    public init() {
        library = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)
    }
    public var available: Bool {
        presence != nil && method(NSTouchBarItem.self, "addSystemTrayItem:") != nil &&
        method(NSTouchBarItem.self, "removeSystemTrayItem:") != nil &&
        method(NSTouchBar.self, "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:") != nil &&
        method(NSTouchBar.self, "dismissSystemModalTouchBar:") != nil
    }
    private func method(_ cls: AnyClass, _ name: String) -> Method? {
        class_getClassMethod(cls, NSSelectorFromString(name))
    }
    public func add(_ item: NSTouchBarItem) -> Bool {
        guard available, let implementation = method(NSTouchBarItem.self, "addSystemTrayItem:") else { return false }
        typealias Function = @convention(c) (AnyObject, Selector, NSTouchBarItem) -> Void
        let function = unsafeBitCast(method_getImplementation(implementation), to: Function.self)
        function(NSTouchBarItem.self, NSSelectorFromString("addSystemTrayItem:"), item)
        lastEntry = item.identifier
        presence?(item.identifier.rawValue as CFString, true)
        return true
    }
    public func remove(_ item: NSTouchBarItem) {
        presence?(item.identifier.rawValue as CFString, false)
        guard let implementation = method(NSTouchBarItem.self, "removeSystemTrayItem:") else { return }
        typealias Function = @convention(c) (AnyObject, Selector, NSTouchBarItem) -> Void
        unsafeBitCast(method_getImplementation(implementation), to: Function.self)(
            NSTouchBarItem.self, NSSelectorFromString("removeSystemTrayItem:"), item)
    }
    public func present(_ bar: NSTouchBar, entry: NSTouchBarItem.Identifier) -> Bool {
        let selector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let implementation = method(NSTouchBar.self, NSStringFromSelector(selector)) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector, NSTouchBar, Int64, NSString?) -> Void
        // Explicit placement avoids the older two-argument wrapper's implicit
        // placement. Cover the strip while expanded; Close returns the native bar.
        unsafeBitCast(method_getImplementation(implementation), to: Function.self)(
            NSTouchBar.self, selector, bar, 1, entry.rawValue as NSString)
        return true
    }
    public func dismiss(_ bar: NSTouchBar) {
        // Minimizing a tray-linked bar returns to its persistent entry. A full
        // dismissal can remove the system-modal association instead.
        let name = method(NSTouchBar.self, "minimizeSystemModalTouchBar:") != nil
            ? "minimizeSystemModalTouchBar:" : "dismissSystemModalTouchBar:"
        guard let implementation = method(NSTouchBar.self, name) else { return }
        typealias Function = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
        unsafeBitCast(method_getImplementation(implementation), to: Function.self)(
            NSTouchBar.self, NSSelectorFromString(name), bar)
        if let lastEntry { presence?(lastEntry.rawValue as CFString, true) }
    }

}

@MainActor public final class TouchBarController: NSObject, NSTouchBarDelegate {
    private let backend: TouchBarBackend
    private let action: (TouchBarAction) -> Void
    private let entryID: NSTouchBarItem.Identifier
    private let metricsID: NSTouchBarItem.Identifier
    private let modesID: NSTouchBarItem.Identifier
    private let sliderID: NSTouchBarItem.Identifier
    private let closeID: NSTouchBarItem.Identifier
    private var entry: NSCustomTouchBarItem?
    private let entryButton = NSButton(title: "—", target: nil, action: nil)
    private let logger = Logger(subsystem: "com.thermalforge.touchbar", category: "lifecycle")
    private var metrics: NSTextField?
    private var modes: NSSegmentedControl?
    private var slider: NSSliderTouchBarItem?
    private var reading = TouchBarReading()
    private var lastEntryTitle = ""
    private var sliderNeedsSync = true
    private var expanded = false
    private lazy var bar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [metricsID, modesID, sliderID, closeID]
        return bar
    }()
    public var available: Bool { backend.available }
    public private(set) var enabled = false

    public init(namespace: String = Bundle.main.bundleIdentifier ?? "com.thermalforge",
                backend: TouchBarBackend? = nil, action: @escaping (TouchBarAction) -> Void) {
        self.backend = backend ?? SystemTouchBarBackend()
        self.action = action
        entryID = .init(namespace + ".touchbar.entry")
        metricsID = .init(namespace + ".touchbar.metrics")
        modesID = .init(namespace + ".touchbar.modes")
        sliderID = .init(namespace + ".touchbar.slider")
        closeID = .init(namespace + ".touchbar.close")
        super.init()
        entryButton.cell = CompactTouchBarEntryCell(textCell: "—")
        entryButton.target = self
        entryButton.action = #selector(openPanel)
        entryButton.bezelStyle = .rounded
        entryButton.isBordered = true
        entryButton.setButtonType(.momentaryPushIn)
        entryButton.frame = NSRect(x: 0, y: 0, width: 55, height: 30)
        entryButton.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        entryButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            entryButton.widthAnchor.constraint(equalToConstant: 55),
            entryButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        entryButton.imagePosition = .imageLeft
        entryButton.setAccessibilityLabel("ThermalForge: open temperature and fan controls")
    }

    @discardableResult public func setEnabled(_ value: Bool) -> Bool {
        if value == enabled { return enabled }
        if !value {
            if expanded { backend.dismiss(bar) }
            if let entry { backend.remove(entry) }
            entry = nil; enabled = false; expanded = false
            return false
        }
        guard backend.available else { return false }
        let item = NSCustomTouchBarItem(identifier: entryID)
        item.view = entryButton
        guard backend.add(item) else { return false }
        entry = item; enabled = true
        logger.notice("Touch Bar entry registered: \(self.entryID.rawValue, privacy: .public)")
        update(reading)
        return true
    }

    public func update(_ value: TouchBarReading) {
        let styleChanged = reading.manual != value.manual || reading.safetyOverride != value.safetyOverride || entryButton.image == nil
        if reading.manual != value.manual { sliderNeedsSync = true }
        reading = value
        guard enabled else { return }
        let title = value.temperatureText(value.cpuTemperature)
        if title != lastEntryTitle { entryButton.title = title; lastEntryTitle = title }
        let tint: NSColor = value.safetyOverride ? .systemRed : value.manual ? .systemOrange : .white
        if styleChanged {
        entryButton.image = NSImage(systemSymbolName: value.safetyOverride ? "exclamationmark.triangle.fill" : "fan.fill",
                                    accessibilityDescription: "ThermalForge")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                .applying(.init(paletteColors: [tint])))
        entryButton.image?.isTemplate = false
        entryButton.contentTintColor = tint
        }
        guard expanded else { return }
        updatePanel()
    }

    private func updatePanel() {
        let text = "CPU \(reading.temperatureText(reading.cpuTemperature))  GPU \(reading.temperatureText(reading.gpuTemperature))  |  \(reading.actualRPM.map { "\($0) RPM" } ?? "RPM —")  |  \(reading.powerText)"
        if metrics?.stringValue != text { metrics?.stringValue = text }
        if modes?.isEnabled != reading.controlAvailable { modes?.isEnabled = reading.controlAvailable }
        let segment = reading.manual ? TouchBarMode.manual.rawValue : reading.mode?.rawValue ?? -1
        if modes?.selectedSegment != segment { modes?.selectedSegment = segment }
        if sliderNeedsSync {
            slider?.slider.minValue = reading.minRPM
            slider?.slider.maxValue = max(reading.maxRPM, reading.minRPM + 1)
            slider?.slider.doubleValue = min(max(reading.targetRPM, reading.minRPM), reading.maxRPM)
            if slider != nil { sliderNeedsSync = false }
        }
        slider?.slider.isEnabled = reading.controlAvailable && reading.manual && !reading.safetyOverride
        slider?.label = reading.safetyOverride ? "Overheat protection" : "\(Int(reading.targetRPM)) RPM"
    }

    @objc public func openPanel() {
        logger.notice("Touch Bar open action received; enabled=\(self.enabled)")
        guard enabled else { return }
        sliderNeedsSync = true
        expanded = backend.present(bar, entry: entryID)
        logger.notice("Touch Bar presentation sent: \(self.expanded)")
        updatePanel()
    }
    @objc public func closePanel() {
        backend.dismiss(bar); expanded = false
    }
    @objc private func selectMode(_ sender: NSSegmentedControl) {
        guard reading.controlAvailable else { return }
        switch sender.selectedSegment {
        case 0: action(.summer)
        case 1: action(.manual)
        case 2: action(.automatic)
        default: break
        }
        // Reflect the last confirmed reading until the application sends the
        // resulting mode; a failed Default command must not look successful.
        updatePanel()
    }
    @objc public func setSpeed(_ sender: AnyObject) {
        guard reading.controlAvailable, reading.manual, !reading.safetyOverride else { return }
        let value: Double
        if let item = sender as? NSSliderTouchBarItem { value = item.doubleValue }
        else if let slider = sender as? NSSlider { value = slider.doubleValue }
        else { return }
        guard value.isFinite else { return }
        action(.speed(min(max(value, reading.minRPM), reading.maxRPM)))
    }

    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        logger.notice("Touch Bar requested item: \(identifier.rawValue, privacy: .public)")
        if identifier == metricsID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = NSTextField(labelWithString: "Reading sensors…")
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            label.textColor = .white
            metrics = label; item.view = label; updatePanel(); return item
        }
        if identifier == modesID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let buttons = NSSegmentedControl(labels: ["Summer", "Manual", "Default"], trackingMode: .selectOne,
                                             target: self, action: #selector(selectMode(_:)))
            modes = buttons; item.view = buttons; updatePanel(); return item
        }
        if identifier == sliderID {
            let item = NSSliderTouchBarItem(identifier: identifier)
            item.slider.isContinuous = false
            item.target = self; item.action = #selector(setSpeed(_:))
            slider = item; updatePanel(); return item
        }
        if identifier == closeID {
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "Close", target: self, action: #selector(closePanel))
            return item
        }
        return nil
    }
}

/// Keep AppKit's native bezel and button behavior, but fit the icon and reading
/// together within the Control Strip's fixed slot instead of truncating the title.
@MainActor private final class CompactTouchBarEntryCell: NSButtonCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let color = (controlView as? NSButton)?.contentTintColor ?? .white
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        let iconWidth: CGFloat = 14
        let gap: CGFloat = 3
        let start = cellFrame.midX - (iconWidth + gap + size.width) / 2
        image?.draw(in: NSRect(x: start, y: cellFrame.midY - 7, width: 14, height: 14),
                    from: .zero, operation: .sourceOver, fraction: isHighlighted ? 0.75 : 1,
                    respectFlipped: true, hints: nil)
        text.draw(at: NSPoint(x: start + iconWidth + gap,
                             y: cellFrame.midY - size.height / 2), withAttributes: attributes)
    }
}
