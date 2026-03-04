import SwiftUI

@main
struct SamprasApp: App {
    @State private var monitor = StatusMonitor()
    @State private var manager = ProcessManager()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor, manager: manager)
        } label: {
            Image(systemName: statusIcon)
                .symbolRenderingMode(.monochrome)
        }
        .menuBarExtraStyle(.menu)
    }

    // Distinct icons per state so changes are visible even without color
    private var statusIcon: String {
        switch (monitor.backendRunning, monitor.frontendRunning) {
        case (true, true):   return "circle.fill"          // both up
        case (false, false): return "circle"               // both down
        default:             return "circle.lefthalf.filled" // one up
        }
    }
}
