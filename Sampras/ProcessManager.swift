import Foundation
import AppKit

struct PortFailure {
    enum Reason { case exited, uncaughtSignal, launchThrew }
    let timestamp: Date
    let reason: Reason
    let exitCode: Int32
    let logTail: String
}

@Observable
@MainActor
class ProcessManager {
    /// Processes Sampras has started, keyed by port number.
    private var processes: [Int: Process] = [:]

    /// Per-port record of the most recent unexpected termination. Cleared on
    /// stop/restart and on user dismissal.
    var failures: [Int: PortFailure] = [:]

    // MARK: - Stop

    func stop(port: Int) {
        // Remove from the map BEFORE terminating so the termination handler
        // sees `processes[port] !== proc` and treats this as a user-initiated
        // stop (silent — no failure recorded).
        let proc = processes.removeValue(forKey: port)
        proc?.terminate()
        failures.removeValue(forKey: port)

        // Also kill anything externally holding the port (e.g. started outside Sampras).
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/bin/bash")
        killer.arguments = ["-c", "lsof -ti :\(port) | xargs kill -9 2>/dev/null; true"]
        try? killer.run()
        killer.waitUntilExit()
    }

    func clearFailure(port: Int) {
        failures.removeValue(forKey: port)
    }

    // MARK: - Start Backend

    func startBackend(port: Int, app: AppDefinition) {
        guard let uvicorn = app.uvicornPath else { return }
        stop(port: port)
        let cmd = """
            cd '\(app.path)/backend' && \
            '\(uvicorn)' \(app.uvicornModule) \
            --host 0.0.0.0 --port \(port) --reload \
            > '/tmp/sampras-\(port).log' 2>&1
            """
        launch(cmd: cmd, port: port)
    }

    // MARK: - Start Frontend

    func startFrontend(port: Int, app: AppDefinition) {
        stop(port: port)
        let cmd = """
            cd '\(app.path)/frontend' && \
            npm run dev -- --port \(port) \
            > '/tmp/sampras-\(port).log' 2>&1
            """
        launch(cmd: cmd, port: port)
    }

    // MARK: - Helpers

    private func launch(cmd: String, port: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", cmd]
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.handleTermination(proc, port: port)
            }
        }
        do {
            try process.run()
            processes[port] = process
        } catch {
            failures[port] = PortFailure(
                timestamp: Date(),
                reason: .launchThrew,
                exitCode: -1,
                logTail: "Failed to launch process: \(error.localizedDescription)"
            )
            surfaceFailureAlert(port: port)
        }
    }

    private func handleTermination(_ proc: Process, port: Int) {
        // If the entry at this port is no longer this process, the user either
        // stopped or restarted it. Stay silent.
        guard processes[port] === proc else { return }
        processes.removeValue(forKey: port)

        let reason: PortFailure.Reason = proc.terminationReason == .uncaughtSignal ? .uncaughtSignal : .exited
        failures[port] = PortFailure(
            timestamp: Date(),
            reason: reason,
            exitCode: proc.terminationStatus,
            logTail: readLogTail(port: port, lines: 20)
        )
        surfaceFailureAlert(port: port)
    }

    private func readLogTail(port: Int, lines: Int) -> String {
        let path = "/tmp/sampras-\(port).log"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "(no log file at \(path))"
        }
        let split = contents.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = split.suffix(lines).joined(separator: "\n")
        return tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(empty log)" : tail
    }

    private func surfaceFailureAlert(port: Int) {
        guard let failure = failures[port] else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Port :\(port) stopped unexpectedly"
        let exitDesc: String
        switch failure.reason {
        case .uncaughtSignal: exitDesc = "Killed by signal \(failure.exitCode)"
        case .exited:         exitDesc = "Exit code \(failure.exitCode)"
        case .launchThrew:    exitDesc = "Sampras could not start the process"
        }
        alert.informativeText = "\(exitDesc)\n\nLast log lines:\n\(failure.logTail)"
        alert.addButton(withTitle: "Open Log")
        alert.addButton(withTitle: "Dismiss")
        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/sampras-\(port).log"))
        }
    }
}
