import SwiftUI
import Charts
import ServiceManagement

@main
struct MacTempApp: App {
    @StateObject private var model = TempModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if let color = model.level?.nsColor {
                Image(nsImage: MenuBarLabel.image(model.menuBarText, color: color))
            } else {
                Text(model.menuBarText)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class TempModel: ObservableObject {
    @Published var celsius: Double?
    @Published var thermalState = ProcessInfo.processInfo.thermalState
    @Published var readings: [Reading] = []
    @Published var startAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("useFahrenheit") var useFahrenheit = false {
        willSet { objectWillChange.send() }
    }
    @AppStorage("didSetUpLoginItem") private var didSetUpLoginItem = false
    private let history = History()
    private var timer: Timer?

    init() {
        readings = history.readings
        // Start at login is on by default: register once on first launch.
        if !didSetUpLoginItem {
            setStartAtLogin(true)
            didSetUpLoginItem = true
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        celsius = Sensors.cpuTemperature()
        thermalState = ProcessInfo.processInfo.thermalState
        if let c = celsius, history.add(c) {
            readings = history.readings
        }
    }

    func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MacTemp: could not change login item: \(error)")
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Converts a Celsius value to whichever unit the user picked.
    func display(_ c: Double) -> Double { useFahrenheit ? c * 9 / 5 + 32 : c }
    var unit: String { useFahrenheit ? "°F" : "°C" }

    var fahrenheit: Double? { celsius.map { $0 * 9 / 5 + 32 } }

    var menuBarText: String {
        guard let c = celsius else { return "🌡 \(thermalText)" }
        return "\(Int(display(c).rounded()))\(unit)"
    }

    var level: TempLevel? { celsius.map(TempLevel.init(celsius:)) }

    var label: String {
        guard let c = celsius else { return thermalText }
        switch c {
        case ..<55: return "Cool"
        case ..<80: return "Warm"
        default: return "Hot"
        }
    }

    var thermalText: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: TempModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let c = model.celsius, let f = model.fahrenheit {
                Text(String(format: "%.1f°C / %.1f°F", c, f)).font(.title2.bold())
                    .foregroundStyle(model.level?.color ?? .primary)
                Text("Feels: \(model.label)")
            } else {
                Text("Temperature sensors not readable").font(.headline)
            }
            Text("Thermal state: \(model.thermalText)").foregroundStyle(.secondary)

            Divider()
            HistoryView(model: model)
            Divider()

            Toggle("Show °F", isOn: Binding(
                get: { model.useFahrenheit },
                set: { model.useFahrenheit = $0 }))
            Toggle("Start at login", isOn: Binding(
                get: { model.startAtLogin },
                set: { model.setStartAtLogin($0) }))
            Divider()
            Button("Quit MacTemp") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
    }
}

struct HistoryView: View {
    @ObservedObject var model: TempModel

    var body: some View {
        let values = model.readings.map(\.celsius)
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 24 hours").font(.headline)
            if values.count < 2 {
                Text("History builds up while MacTemp is running. Check back in a few minutes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let lo = model.display(values.min()!) - 2
                let hi = model.display(values.max()!) + 2
                Chart(model.readings) { r in
                    LineMark(x: .value("Time", r.date), y: .value("Temp", model.display(r.celsius)))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(lineGradient(lo: lo, hi: hi))
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 120)

                HStack {
                    stat("Highest", values.max()!)
                    Spacer()
                    stat("Lowest", values.min()!)
                    Spacer()
                    stat("Average", values.reduce(0, +) / Double(values.count))
                }
            }
        }
    }

    /// Vertical gradient with hard color changes at the blue / red thresholds.
    private func lineGradient(lo: Double, hi: Double) -> LinearGradient {
        func at(_ c: Double) -> CGFloat { CGFloat(min(max((model.display(c) - lo) / (hi - lo), 0), 1)) }
        let blueTop = at(TempLevel.lowBelow), redBottom = at(TempLevel.highFrom)
        let stops: [Gradient.Stop] = [
            .init(color: .blue, location: 0), .init(color: .blue, location: blueTop),
            .init(color: .primary, location: blueTop), .init(color: .primary, location: redBottom),
            .init(color: .red, location: redBottom), .init(color: .red, location: 1),
        ]
        return LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
    }

    private func stat(_ title: String, _ c: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(model.display(c).rounded()))\(model.unit)").font(.body.monospacedDigit().bold())
        }
    }
}
