# Personal comfort controls

This fork adds a fixed `Summer Smooth` preset, a manual fan-speed slider, custom
profile selection/restore, and native battery-power readings. Smart calibration
is unchanged and is not required for any of these features. No stress test runs
automatically.

## Summer Smooth

This is a comfort preset, not an Apple-published fan curve or a measured optimum.
The old custom Summer preset covered only 55–65°C. The new preset covers 55–75°C:

| Setting | Value |
|---|---|
| Return to Apple automatic control | ≤50°C for 20 consecutive seconds |
| Start | ≥55°C for 4 seconds |
| Curve | S-curve, 17% floor → 85% maximum at 75°C |
| Increase limit | 4% of maximum RPM per second |
| Decrease limit | 1.5% of maximum RPM per second |
| Ordinary control temperature | Exponential smoothing, 3-second time constant |
| Safety | Raw CPU/GPU peak, 95°C override, held until below 90°C |

The floor removes the long flat region produced by clamping a zero-based curve
to the fan's hardware minimum. The hardware minimum still applies independently.
On a fan with a 7199 RPM maximum, steady-state targets before ramp limits are
approximately 1224 RPM at 55°C, 1989 at 60°C, 3671 at 65°C, 5354 at 70°C, and
6119 at 75°C. These are requested speeds, not guaranteed chip temperatures.

Existing custom profile files are preserved. `minRPMPercent` is optional in JSON,
so old profiles keep their old curve calculation. `silent`, `smart`, and `manual`
are reserved IDs. The new curve is selected explicitly; launch does not silently
replace a user's existing choice. No repeated calibration is needed.

Public references inform the design, but do not supply a validated M1 curve:

- [Apple's temperature guidance](https://support.apple.com/en-au/102336) concerns
  operating environment and ventilation, not a CPU-temperature/RPM table.
- [Macs Fan Control's sensor notes](https://crystalidea.com/macs-fan-control/temperature-sensors)
  warn that momentary core-temperature fluctuations can be unsuitable for direct
  fan control. This fork smooths ordinary control while leaving safety unsmoothed.
- [Upstream's profiles](https://github.com/ProducerGuy/ThermalForge/blob/42bb5345bc0a8d41a9c47719c3ceb0fbc7249687/Sources/ThermalForgeCore/Profile.swift)
  provide curve shapes, ramp limiting, and hysteresis. This preset uses those
  mechanisms with a wider comfort-oriented band.

## Manual speed

The slider displays RPM or percentage of hardware maximum and sends its selection
on release. The monitor keeps refreshing temperature/RPM. Manual is a runtime-only
profile, so it does not become the saved launch profile; switching back restores
the previous curve. The raw-temperature override, daemon floor, heartbeat and
app/CLI arbitration remain in place. Quitting releases an app-owned hold as before.

## Battery power

Read `AppleSmartBattery` through IOKit every five seconds on a background queue.
There are no `pmset` subprocesses or paid-service dependencies. Voltage × current
is **net battery power**, not charger input power: it excludes the computer's own
consumption and conversion losses. The adapter's reported watt rating is displayed
separately and must not be mistaken for its current output. Integers are shown in
the menu; charging, plugged-in, full and battery states remain distinct.

## Development and install

The local project lives in `/Users/yqc/Projects/ThermalForge`. `origin` is the
personal fork and `upstream` is the original repository. Keep source and Git
history; `.build` can be regenerated. Work on feature branches and push to origin.

Use `swift test`, then `swift build -c release`. A staged, ad-hoc-signed app can be
assembled without replacing the installed copy. Installing the app and privileged
daemon together requires the local administrator password via `./setup.sh`.
Do not launch the new app against an old daemon: the wire protocol has changed.
An upstream Homebrew upgrade can replace this fork's features; build from the fork
when updating this customized installation.
