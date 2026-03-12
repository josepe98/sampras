import SwiftUI

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct PortInfo: Identifiable {
    let id: Int           // port number
    var appName: String? = nil
    var isDemoMode: Bool = false
    var isRunning: Bool { appName != nil }
}

@Observable
@MainActor
class StatusMonitor {
    var backendPorts:  [PortInfo] = [8000, 8001, 8002, 8003, 8004, 8005].map { PortInfo(id: $0) }
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
            let result = await portDetails(forPort: backendPorts[i].id)
            backendPorts[i].appName = result.appName
            backendPorts[i].isDemoMode = result.isDemoMode
        }
        for i in frontendPorts.indices {
            let result = await portDetails(forPort: frontendPorts[i].id)
            frontendPorts[i].appName = result.appName
            frontendPorts[i].isDemoMode = result.isDemoMode
        }
    }

    /// Detects which project is running on a port and whether it has demo.db open.
    private func portDetails(forPort port: Int) async -> (appName: String?, isDemoMode: Bool) {
        let home = NSHomeDirectory()
        return await Task.detached {
            // Step 1: lsof to find the PID
            let lsof = Process()
            lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            lsof.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
            let lsofPipe = Pipe()
            lsof.standardOutput = lsofPipe
            lsof.standardError  = Pipe()
            guard (try? lsof.run()) != nil else { return (nil, false) }
            lsof.waitUntilExit()

            let lsofOut = String(data: lsofPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let dataLines = lsofOut.components(separatedBy: "\n").dropFirst().filter { !$0.isEmpty }
            guard !dataLines.isEmpty else { return (nil, false) }

            let pids = dataLines.compactMap { line -> Int? in
                let fields = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                return fields.count >= 2 ? Int(fields[1]) : nil
            }.uniqued()

            let prefix = home + "/"

            // Helper: extract project name from an absolute path under ~/
            func projectName(from path: String) -> String? {
                guard path.hasPrefix(prefix) else { return nil }
                let relative = String(path.dropFirst(prefix.count))
                if let name = relative.components(separatedBy: "/").first, !name.isEmpty {
                    return name
                }
                return nil
            }

            // Step 2: try to parse the app name from command-line tokens.
            var appName: String? = nil
            for pid in pids {
                let ps = Process()
                ps.executableURL = URL(fileURLWithPath: "/bin/ps")
                ps.arguments = ["-p", "\(pid)", "-o", "command="]
                let psPipe = Pipe()
                ps.standardOutput = psPipe
                ps.standardError  = Pipe()
                guard (try? ps.run()) != nil else { continue }
                ps.waitUntilExit()

                let command = String(data: psPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                for token in command.components(separatedBy: .whitespaces) {
                    if let name = projectName(from: token) { appName = name; break }
                }
                if appName != nil { break }
            }

            // Fallback: check the process's working directory.
            if appName == nil {
                for pid in pids {
                    let cwd = Process()
                    cwd.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                    cwd.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
                    let cwdPipe = Pipe()
                    cwd.standardOutput = cwdPipe
                    cwd.standardError  = Pipe()
                    guard (try? cwd.run()) != nil else { continue }
                    cwd.waitUntilExit()

                    let cwdOut = String(data: cwdPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    for line in cwdOut.components(separatedBy: "\n") where line.hasPrefix("n") {
                        if let name = projectName(from: String(line.dropFirst())) {
                            appName = name; break
                        }
                    }
                    if appName != nil { break }
                }
            }

            guard appName != nil else { return (nil, false) }

            // Step 3: check if any PID has demo.db open.
            var isDemoMode = false
            for pid in pids {
                let files = Process()
                files.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                files.arguments = ["-a", "-p", "\(pid)", "-Fn"]
                let filesPipe = Pipe()
                files.standardOutput = filesPipe
                files.standardError  = Pipe()
                guard (try? files.run()) != nil else { continue }
                files.waitUntilExit()

                let filesOut = String(data: filesPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if filesOut.contains("/demo.db") {
                    isDemoMode = true
                    break
                }
            }

            return (appName, isDemoMode)
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
