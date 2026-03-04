import SwiftUI

struct PortInfo: Identifiable {
    let id: Int          // port number is the unique identifier
    var processName: String? = nil
    var isRunning: Bool { processName != nil }
}

@Observable
@MainActor
class StatusMonitor {
    var backendPorts:  [PortInfo] = [8000, 8001, 8002].map         { PortInfo(id: $0) }
    var frontendPorts: [PortInfo] = [5173, 5174, 5175, 5176, 5177, 5178].map { PortInfo(id: $0) }

    private var timer: Timer?

    init() { startPolling() }

    var backendRunning:  Bool { backendPorts.contains  { $0.isRunning } }
    var frontendRunning: Bool { frontendPorts.contains { $0.isRunning } }

    /// First running frontend port, used by "Open in Browser".
    var activeFrontendPort: Int? { frontendPorts.first(where: { $0.isRunning })?.id }

    private func startPolling() {
        Task { await poll() }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
    }

    private func poll() async {
        for i in backendPorts.indices {
            backendPorts[i].processName = await processName(forPort: backendPorts[i].id)
        }
        for i in frontendPorts.indices {
            frontendPorts[i].processName = await processName(forPort: frontendPorts[i].id)
        }
    }

    /// Runs lsof on a background thread and returns the process name listening on
    /// the given port, or nil if nothing is listening.
    private func processName(forPort port: Int) async -> String? {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            p.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError  = Pipe()
            guard (try? p.run()) != nil else { return nil }
            p.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // lsof columns: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count > 1 else { return nil }
            return lines[1].components(separatedBy: .whitespaces).filter { !$0.isEmpty }.first
        }.value
    }

    var overallColor: Color {
        switch (backendRunning, frontendRunning) {
        case (true, true):   return .green
        case (false, false): return .red
        default:             return .orange
        }
    }
}
