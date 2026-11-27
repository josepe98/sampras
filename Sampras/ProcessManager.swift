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

    /// App definitions for ports Sampras started, used to support Restart.
    private var runningApps: [Int: (app: AppDefinition, type: PortType)] = [:]

    /// Per-port record of the most recent unexpected termination. Cleared on
    /// stop/restart and on user dismissal.
    var failures: [Int: PortFailure] = [:]

    // MARK: - Stop

    func stop(port: Int) {
        // Remove from the map BEFORE terminating so the termination handler
        // sees `processes[port] !== proc` and treats this as a user-initiated
        // stop (silent — no failure recorded).
        let proc = processes.removeValue(forKey: port)
        runningApps.removeValue(forKey: port)
        proc?.terminate()
        failures.removeValue(forKey: port)

        // Also kill anything externally LISTENING on the port (e.g. started outside
        // Sampras). Must be restricted to listeners: a bare `lsof -ti :port` also
        // returns clients connected to the port — i.e. the browser with the app open.
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/bin/bash")
        killer.arguments = ["-c", "/usr/sbin/lsof -ti tcp:\(port) -sTCP:LISTEN | xargs kill -9 2>/dev/null; true"]
        try? killer.run()
        killer.waitUntilExit()
    }

    func clearFailure(port: Int) {
        failures.removeValue(forKey: port)
    }

    // MARK: - Start Backend

    func canRestart(port: Int, appName: String?) -> Bool {
        runningApps[port] != nil || resolvedApp(for: port, appName: appName) != nil
    }

    func restart(port: Int, appName: String?, type: PortType) {
        // A launchd job with KeepAlive respawns its process the instant it is
        // killed, so kill-then-spawn loses the race for the port. Ask launchd
        // to do the restart instead.
        if let label = launchdLabel(forListenerOn: port) {
            restartViaLaunchd(label: label, port: port)
            return
        }
        let entry: (app: AppDefinition, type: PortType)
        if let stored = runningApps[port] {
            entry = stored
        } else if let app = resolvedApp(for: port, appName: appName) {
            entry = (app, type)
        } else {
            return
        }
        if entry.type == .backend {
            startBackend(port: port, app: entry.app)
        } else {
            startFrontend(port: port, app: entry.app)
        }
    }

    /// Label of the user launchd job that owns the process listening on `port`,
    /// if any. Walks up the parent chain because the listener may be a child of
    /// the job's main process (e.g. uvicorn --reload workers). `application.*`
    /// labels are ordinary GUI apps (including Sampras itself), not jobs.
    private func launchdLabel(forListenerOn port: Int) -> String? {
        let script = """
            pid=$(/usr/sbin/lsof -ti tcp:\(port) -sTCP:LISTEN | head -1)
            jobs=$(/bin/launchctl list)
            while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
              label=$(echo "$jobs" | awk -v p="$pid" '$1==p && $3 !~ /^application\\./ {print $3; exit}')
              if [ -n "$label" ]; then echo "$label"; exit 0; fi
              pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
            done
            """
        let (status, out) = runShell(script)
        let label = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return status == 0 && !label.isEmpty ? label : nil
    }

    private func restartViaLaunchd(label: String, port: Int) {
        // Drop any Sampras-owned process for this port without tripping the
        // unexpected-termination alert.
        processes.removeValue(forKey: port)?.terminate()
        runningApps.removeValue(forKey: port)
        failures.removeValue(forKey: port)

        let (status, out) = runShell("/bin/launchctl kickstart -k gui/\(getuid())/'\(label)' 2>&1")
        if status != 0 {
            failures[port] = PortFailure(
                timestamp: Date(),
                reason: .launchThrew,
                exitCode: status,
                logTail: "launchctl kickstart of \(label) failed (exit \(status)):\n\(out)"
            )
            surfaceFailureAlert(port: port)
        }
    }

    private func runShell(_ script: String) -> (status: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func resolvedApp(for port: Int, appName: String?) -> AppDefinition? {
        guard let name = appName else { return nil }
        let all = discoverApps() + discoverSpecialApps()
        return all.first { $0.name == name }
    }

    // MARK: - Start Backend

    func startBackend(port: Int, app: AppDefinition) {
        stop(port: port)
        runningApps[port] = (app, .backend)

        let cmd: String
        if let customCmd = app.customBackendCmd {
            // Script-based backend (e.g. claude-usage dashboard.py). PORT env var
            // is injected so the script can bind to the user-chosen port.
            cmd = "cd '\(app.path)' && PORT=\(port) \(customCmd) > '/tmp/sampras-\(port).log' 2>&1"
        } else {
            guard let uvicorn = app.uvicornPath else { return }
            cmd = """
                cd '\(app.path)/backend' && \
                '\(uvicorn)' \(app.uvicornModule) \
                --host 0.0.0.0 --port \(port) --reload \
                > '/tmp/sampras-\(port).log' 2>&1
                """
        }
        launch(cmd: cmd, port: port)
    }

    // MARK: - Start Frontend

    func startFrontend(port: Int, app: AppDefinition) {
        stop(port: port)
        runningApps[port] = (app, .frontend)
        // A GUI app's PATH is /usr/bin:/bin:/usr/sbin:/sbin — it has no nvm or
        // Homebrew entries, so npm (and the node it shells out to) must be put
        // on PATH explicitly.
        let pathPrefix = Self.nodeBinDir.map { "PATH='\($0)':\"$PATH\" " } ?? ""
        let cmd = """
            cd '\(app.path)/frontend' && \
            \(pathPrefix)npm run dev -- --port \(port) \
            > '/tmp/sampras-\(port).log' 2>&1
            """
        launch(cmd: cmd, port: port)
    }

    // MARK: - Helpers

    /// Directory containing `npm` and `node`, resolved once per launch. Asks the
    /// user's interactive login shell first (so it honours nvm's default), then
    /// falls back to well-known install locations.
    private static let nodeBinDir: String? = {
        let fm = FileManager.default

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-ilc", "command -v npm"]
        shell.standardInput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        shell.standardOutput = pipe
        if (try? shell.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            shell.waitUntilExit()
            let lines = (String(data: data, encoding: .utf8) ?? "")
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let npm = lines.last(where: { $0.hasPrefix("/") && fm.isExecutableFile(atPath: $0) }) {
                return (npm as NSString).deletingLastPathComponent
            }
        }

        var candidates = ["/opt/homebrew/bin", "/usr/local/bin"]
        let nvmRoot = NSHomeDirectory() + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            let newestFirst = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            candidates += newestFirst.map { "\(nvmRoot)/\($0)/bin" }
        }
        return candidates.first { fm.isExecutableFile(atPath: $0 + "/npm") }
    }()

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
        runningApps.removeValue(forKey: port)

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
