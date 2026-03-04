import SwiftUI

@main
struct SamprasApp: App {
    @State private var monitor = StatusMonitor()
    @State private var manager = ProcessManager()

    @State private var aboutWindow: NSWindow?

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor, manager: manager, onAbout: showAbout)
        } label: {
            Image(systemName: statusIcon)
                .symbolRenderingMode(.monochrome)
        }
        .menuBarExtraStyle(.menu)
    }

    // Distinct icons per state so changes are visible even without color
    private var statusIcon: String {
        switch (monitor.backendRunning, monitor.frontendRunning) {
        case (true, true):   return "circle.fill"
        case (false, false): return "circle"
        default:             return "circle.lefthalf.filled"
        }
    }

    private func showAbout() {
        if let existing = aboutWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Sampras"
        window.contentView = NSHostingView(rootView: AboutView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        aboutWindow = window
    }
}
