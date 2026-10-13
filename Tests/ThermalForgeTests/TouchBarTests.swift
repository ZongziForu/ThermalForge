import AppKit
import Testing
@testable import ThermalForgeTouchBar

@MainActor private final class FakeTouchBarBackend: TouchBarBackend {
    var available = true
    var additions = 0
    var removals = 0
    var presentations = 0
    var dismissals = 0
    var item: NSTouchBarItem?
    func add(_ item: NSTouchBarItem) -> Bool {
        additions += 1
        self.item = item
        return true
    }
    func remove(_ item: NSTouchBarItem) { removals += 1 }
    func present(_ bar: NSTouchBar, entry: NSTouchBarItem.Identifier) -> Bool {
        presentations += 1
        return true
    }
    func dismiss(_ bar: NSTouchBar) { dismissals += 1 }
}

@Suite("Touch Bar without system registration")
struct TouchBarTests {
    @Test("Unavailable private APIs leave the rest of the app usable") @MainActor
    func unavailable() {
        let backend = FakeTouchBarBackend()
        backend.available = false
        let controller = TouchBarController(backend: backend) { _ in Issue.record("Unexpected fan action") }
        #expect(!controller.setEnabled(true))
        controller.openPanel()
        #expect(backend.additions == 0)
        #expect(backend.presentations == 0)
    }

    @Test("Repeated readings never re-register the global item; disable closes and removes it") @MainActor
    func lifecycle() {
        let backend = FakeTouchBarBackend()
        let controller = TouchBarController(backend: backend) { _ in Issue.record("Unexpected fan action") }
        #expect(controller.setEnabled(true))
        for value in 50...70 { controller.update(TouchBarReading(cpuTemperature: Float(value))) }
        let button = (backend.item as? NSCustomTouchBarItem)?.view as? NSButton
        #expect(button?.title == "70°")
        #expect((button?.frame.width ?? 0) > 0)
        #expect(button?.target === controller)
        #expect(controller.setEnabled(true))
        #expect(backend.additions == 1)
        controller.openPanel()
        #expect(backend.presentations == 1)
        controller.setEnabled(false)
        #expect(backend.removals == 1)
        #expect(backend.dismissals == 1)
        controller.setEnabled(false)
        #expect(backend.removals == 1)
    }

    @Test("Missing readings, Fahrenheit and net battery power remain explicit")
    func display() {
        let reading = TouchBarReading(cpuTemperature: 50, batteryWatts: -12.4, fahrenheit: true)
        #expect(reading.temperatureText(reading.cpuTemperature) == "122°")
        #expect(reading.temperatureText(nil) == "—")
        #expect(reading.temperatureText(.nan) == "—")
        #expect(reading.powerText == "Battery 12 W")
    }

    @Test("Native Touch Bar slider sender dispatches a bounded RPM only in manual mode") @MainActor
    func sliderAction() {
        let backend = FakeTouchBarBackend()
        var actions: [TouchBarAction] = []
        let controller = TouchBarController(backend: backend) { actions.append($0) }
        controller.setEnabled(true)
        controller.update(TouchBarReading(manual: true, minRPM: 1200, maxRPM: 7200, controlAvailable: true))
        let item = NSSliderTouchBarItem(identifier: .init("test.slider"))
        item.slider.minValue = 0
        item.slider.maxValue = 10000
        item.doubleValue = 8000
        controller.setSpeed(item)
        #expect(actions == [.speed(7200)])
        controller.update(TouchBarReading(manual: true, safetyOverride: true, controlAvailable: true))
        controller.setSpeed(item)
        #expect(actions.count == 1)
        controller.update(TouchBarReading(manual: false, controlAvailable: true))
        controller.setSpeed(item)
        #expect(actions.count == 1)
    }

    @Test("Closing the panel keeps its entry registered and permits reopening") @MainActor
    func closeAndReopen() {
        let backend = FakeTouchBarBackend()
        let controller = TouchBarController(backend: backend) { _ in }
        controller.setEnabled(true)
        controller.openPanel()
        controller.closePanel()
        #expect(controller.enabled)
        #expect(backend.removals == 0)
        controller.openPanel()
        #expect(backend.presentations == 2)
        controller.setEnabled(false)
        #expect(backend.removals == 1)
    }

    @Test("Preview and installed app do not compete for the same global identifier") @MainActor
    func namespaces() {
        let productionBackend = FakeTouchBarBackend()
        let previewBackend = FakeTouchBarBackend()
        let production = TouchBarController(namespace: "com.thermalforge.app", backend: productionBackend) { _ in }
        let preview = TouchBarController(namespace: "com.thermalforge.preview", backend: previewBackend) { _ in }
        production.setEnabled(true)
        preview.setEnabled(true)
        #expect(productionBackend.item?.identifier != previewBackend.item?.identifier)
        preview.setEnabled(false)
        #expect(production.enabled)
    }
}
