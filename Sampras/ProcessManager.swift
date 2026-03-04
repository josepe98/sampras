import Foundation

class ProcessManager: ObservableObject {
    /// Processes Sampras has started, keyed by port number.
    private var processes: [Int: Process] = [:]

    // MARK: - Stop

    func stop(port: Int) {
        processes[port]?.terminate()
        processes.removeValue(forKey: port)

        // Also kill anything externally holding the port (e.g. started outside Sampras).
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/bin/bash")
        killer.arguments = ["-c", "lsof -ti :\(port) | xargs kill -9 2>/dev/null; true"]
        try? killer.run()
        killer.waitUntilExit()
    }

    // MARK: - Start Backend

    func startBackend(port: Int, app: AppDefinition) {
        guard let uvicorn = app.uvicornPath else { return }
        stop(port: port)
        let cmd = """
            cd '\(app.path)/backend' && \
            '\(uvicorn)' app.main:app \
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
        do {
            try process.run()
            processes[port] = process
        } catch {
            print("Sampras: failed to launch on port \(port): \(error)")
        }
    }
}
