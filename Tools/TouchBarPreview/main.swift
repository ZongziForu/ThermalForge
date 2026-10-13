import AppKit
import ThermalForgeTouchBar

/// Isolated visual preview. No ThermalMonitor, daemon client, or SMC writes.
@MainActor final class PreviewDelegate: NSObject, NSApplicationDelegate {
    var controller: TouchBarController?
    var timer: Timer?
    var tick = 0
    var manual = false
    var targetRPM = 2000.0
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = TouchBarController { [weak self] action in
            guard let self else { return }
            switch action {
            case .manual: self.manual = true
            case .summer, .automatic: self.manual = false
            case .speed(let rpm): self.targetRPM = rpm
            }
            self.update()
        }
        print("Touch Bar API available: \(controller?.available == true)")
        print("Entry registered: \(controller?.setEnabled(true) == true)")
        update()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 190),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ThermalForge Touch Bar Preview — no fan writes"
        let label = NSTextField(labelWithString: "The Touch Bar entry should read 55–59°.\nClick it, or press the button below, to open the panel.\nThis preview uses simulated readings and never controls fans.")
        label.frame = NSRect(x: 20, y: 85, width: 480, height: 80)
        let button = NSButton(title: "Open Touch Bar preview", target: self, action: #selector(openPreview))
        button.frame = NSRect(x: 20, y: 30, width: 230, height: 36)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(button)
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 900) { NSApp.terminate(nil) }
    }
    @objc func openPreview() { controller?.openPanel() }
    func update() {
        tick += 1
        controller?.update(TouchBarReading(cpuTemperature: Float(55 + tick % 5), gpuTemperature: 49,
                                          actualRPM: 2000 + tick % 5 * 50, batteryWatts: 25,
                                          charging: true, manual: manual, targetRPM: targetRPM, controlAvailable: true))
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        controller?.setEnabled(false)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = PreviewDelegate()
    app.delegate = delegate
    app.run()
}
