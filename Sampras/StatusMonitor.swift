import SwiftUI

struct PortInfo: Identifiable {
    let id: Int           // port number
    var appName: String? = nil
    var isRunning: Bool { appName != nil }
}

@Observable
@MainActor
class StatusMonitor {
    var backendPorts:  [PortInfo] = [8000, 8001, 8002].map              { PortInfo(id: $0) }
    var frontendPorts: [PortInfo] = [5173, 5174, 5175, 5176, 5177, 5178].map { PortInfo(id: $0) }

    private var timer: Timer?

    init() { startPolling() }

    var backendRunning:  Bool { backendPorts.contains  { $0.isRunning } }
    var frontendRunning: Bool { frontendPorts.contains { $0.isRunning } }
    var activeFrontendPort: Int? { frontendPorts.first(where: { $0.isRunning })?.id }

    private func startPolling() {
        Task { await poll() }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
    }

    private func poll() async {
        for i in backendPorts.indices {
            backendPorts[i].appName = await appName(forPort: backendPorts[i].id)
        }
        for i in frontendPorts.indices {
            frontendPorts[i].appName = await appName(forPort: frontendPorts[i].id)
        }
    }

    /// Detects which project is running on a port by:
    ///   1. lsof  → PID of the listening process
    ///   2. ps    → full command string for that PID
    ///   3. parse → first path component after the home directory
    private func appName(forPort port: Int) async -> String? {
        let home = NSHomeDirectory()
        return await Task.detached {
            // Step 1: lsof to find the PID
            let lsof = Process()
            lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            lsof.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
            let lsofPipe = Pipe()
            lsof.standardOutput = lsofPipe
            lsof.standardError  = Pipe()
            guard (try? lsof.run()) != nil else { return nil }
            lsof.waitUntilExit()

            let lsofOut = String(data: lsofPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let lines = lsofOut.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count > 1 else { return nil }
            let fields = lines[1].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard fields.count >= 2, let pid = Int(fields[1]) else { return nil }

            // Step 2: ps to get the full command
            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-p", "\(pid)", "-o", "command="]
            let psPipe = Pipe()
            ps.standardOutput = psPipe
            ps.standardError  = Pipe()
            guard (try? ps.run()) != nil else { return nil }
            ps.waitUntilExit()

            let command = String(data: psPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            // Step 3: find the first home-directory path component in the command
            let prefix = home + "/"
            for token in command.components(separatedBy: .whitespaces) {
                if token.hasPrefix(prefix) {
                    let relative = String(token.dropFirst(prefix.count))
                    if let name = relative.components(separatedBy: "/").first, !name.isEmpty {
                        return name
                    }
                }
            }
            return nil
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
