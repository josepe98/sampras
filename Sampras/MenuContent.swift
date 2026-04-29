import SwiftUI
import AppKit

enum PortType { case backend, frontend }

struct MenuContent: View {
    var monitor: StatusMonitor
    var manager: ProcessManager
    var onAbout: () -> Void

    var body: some View {
        // ── Backend ports ──────────────────────────────────────────────────
        ForEach(monitor.backendPorts) { port in
            portMenu(port, type: .backend)
        }

        Divider()

        // ── Frontend ports ─────────────────────────────────────────────────
        ForEach(monitor.frontendPorts) { port in
            portMenu(port, type: .frontend)
        }

        Divider()

        Menu("Open in Browser") {
            // Prefer frontend port when an app has both; deduplicate by name
            let allActive = (monitor.frontendPorts + monitor.backendPorts).filter(\.isRunning)
            var seen = Set<String>()
            let activeFrontends = allActive.filter { port in
                let key = port.appName ?? ":\(port.id)"
                return seen.insert(key).inserted
            }
            if activeFrontends.isEmpty {
                Text("No active apps")
            } else {
                ForEach(activeFrontends) { port in
                    Button(port.appName ?? "localhost:\(port.id)") {
                        if let url = URL(string: "http://localhost:\(port.id)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }

        Divider()

        Button("About Sampras") { onAbout() }

        Divider()

        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    // MARK: - Per-port submenu

    @ViewBuilder
    private func portMenu(_ port: PortInfo, type: PortType) -> some View {
        let failure = manager.failures[port.id]
        Menu {
            if port.isRunning {
                Button("Stop") {
                    manager.stop(port: port.id)
                }
                Button("Open Log") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/sampras-\(port.id).log"))
                }
            } else if failure != nil {
                Button("Open Log") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/sampras-\(port.id).log"))
                }
                Button("Retry…") {
                    let capturedPort = port.id
                    let capturedManager = manager
                    DispatchQueue.main.async {
                        MenuContent.showStartPanel(port: capturedPort, type: type, manager: capturedManager)
                    }
                }
                Button("Dismiss") {
                    manager.clearFailure(port: port.id)
                }
            } else {
                Button("Start…") {
                    let capturedPort = port.id
                    let capturedManager = manager
                    DispatchQueue.main.async {
                        MenuContent.showStartPanel(port: capturedPort, type: type, manager: capturedManager)
                    }
                }
            }
        } label: {
            Label {
                Text(portLabel(port, failure: failure))
            } icon: {
                Image(nsImage: dotImage(dotColor(running: port.isRunning, failed: failure != nil)))
            }
        }
    }

    private func dotColor(running: Bool, failed: Bool) -> NSColor {
        if running { return .systemGreen }
        if failed  { return .systemYellow }
        return .systemRed
    }

    // MARK: - Start panel

    static func showStartPanel(port: Int, type: PortType, manager: ProcessManager) {
        let apps = discoverApps().filter { type == .backend ? $0.hasBackend : $0.hasFrontend }

        NSApplication.shared.activate(ignoringOtherApps: true)

        guard !apps.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No apps found"
            alert.informativeText = "No compatible apps were discovered in your home folder."
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Start on :\(port)"
        alert.informativeText = "Choose which app to run on this port:"
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        for app in apps { popup.addItem(withTitle: app.name) }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let selected = apps[popup.indexOfSelectedItem]

        if type == .backend {
            manager.startBackend(port: port, app: selected)
        } else {
            manager.startFrontend(port: port, app: selected)
        }
    }

    // MARK: - Helpers

    private func portLabel(_ port: PortInfo, failure: PortFailure? = nil) -> String {
        var label = ":\(port.id)"
        if let name = port.appName {
            label += "  \(name)"
            if port.isDemoMode { label += " (demo)" }
        } else if let failure {
            switch failure.reason {
            case .uncaughtSignal: label += "  failed (signal \(failure.exitCode))"
            case .exited:         label += "  failed (exit \(failure.exitCode))"
            case .launchThrew:    label += "  failed to launch"
            }
        }
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
