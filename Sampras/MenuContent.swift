import SwiftUI
import AppKit

struct MenuContent: View {
    var monitor: StatusMonitor
    var manager: ProcessManager
    var onAbout: () -> Void

    var body: some View {
        // ── Backend ports ─────────────────────────────────────────────────
        ForEach(monitor.backendPorts) { port in
            Label {
                Text(portLabel(port))
            } icon: {
                Image(nsImage: dotImage(port.isRunning ? .systemGreen : .systemRed))
            }
        }

        Button("Start Backend")    { manager.startBackend() }  .disabled(monitor.backendRunning)
        Button("Stop Backend")     { manager.stopBackend() }   .disabled(!monitor.backendRunning)
        Button("Open Backend Log") { NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/backend.log")) }

        Divider()

        // ── Frontend ports ────────────────────────────────────────────────
        ForEach(monitor.frontendPorts) { port in
            Label {
                Text(portLabel(port))
            } icon: {
                Image(nsImage: dotImage(port.isRunning ? .systemGreen : .systemRed))
            }
        }

        Button("Start Frontend")    { manager.startFrontend() }  .disabled(monitor.frontendRunning)
        Button("Stop Frontend")     { manager.stopFrontend() }   .disabled(!monitor.frontendRunning)
        Button("Open Frontend Log") { NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/frontend.log")) }

        Divider()

        Button("Open in Browser") {
            let port = monitor.activeFrontendPort ?? 5173
            if let url = URL(string: "http://localhost:\(port)") {
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Button("About Sampras") { onAbout() }

        Divider()

        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private func portLabel(_ port: PortInfo) -> String {
        var label = ":\(port.id)"
        if let name = port.processName { label += "  \(name)" }
        return label
    }

    private func dotImage(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
