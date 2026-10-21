import SwiftUI

@main
struct MacTempApp: App {
    @StateObject private var model = TempModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Text(model.menuBarText)
        }
    }
}

final class TempModel: ObservableObject {
    @Published var celsius: Double?
    @Published var thermalState = ProcessInfo.processInfo.thermalState
    @AppStorage("useFahrenheit") var useFahrenheit = false {
        willSet { objectWillChange.send() }
    }
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        celsius = Sensors.cpuTemperature()
        thermalState = ProcessInfo.processInfo.thermalState
    }

    var fahrenheit: Double? { celsius.map { $0 * 9 / 5 + 32 } }

    var menuBarText: String {
        guard let c = celsius else { return "🌡 \(thermalText)" }
        return useFahrenheit ? "\(Int(fahrenheit!.rounded()))°F" : "\(Int(c.rounded()))°C"
    }

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
        if let c = model.celsius, let f = model.fahrenheit {
            Text(String(format: "CPU: %.1f°C / %.1f°F", c, f))
            Text("Feels: \(model.label)")
        } else {
            Text("Temperature sensors not readable")
        }
        Text("Thermal state: \(model.thermalText)")
        Divider()
        Toggle("Show °F in menu bar", isOn: Binding(
            get: { model.useFahrenheit },
            set: { model.useFahrenheit = $0 }))
        Divider()
        Button("Quit MacTemp") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
