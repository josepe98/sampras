import Foundation

class ProcessManager: ObservableObject {
    private let projectRoot = "/Users/erikjosephson/everything-app"

    private var backendProcess: Process?
    private var frontendProcess: Process?

    // MARK: - Backend

    func startBackend() {
        guard backendProcess == nil || !backendProcess!.isRunning else { return }

        // Clear any process still holding port 8000 (e.g. crashed uvicorn)
        let freePort = Process()
        freePort.executableURL = URL(fileURLWithPath: "/bin/bash")
        freePort.arguments = ["-c", "lsof -ti :8000 | xargs kill -9 2>/dev/null; true"]
        try? freePort.run()
        freePort.waitUntilExit()

        let backendDir = "\(projectRoot)/backend"
        let uvicorn = "\(projectRoot)/venv/bin/uvicorn"
        let cmd = "cd '\(backendDir)' && '\(uvicorn)' app.main:app --host 0.0.0.0 --port 8000 --reload > /tmp/backend.log 2>&1"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", cmd]

        do {
            try process.run()
            backendProcess = process
        } catch {
            print("Failed to start backend: \(error)")
        }
    }

    func stopBackend() {
        backendProcess?.terminate()
        backendProcess = nil

        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-f", "uvicorn app.main:app"]
        try? killer.run()
    }

    // MARK: - Frontend

    func startFrontend() {
        guard frontendProcess == nil || !frontendProcess!.isRunning else { return }

        let frontendDir = "\(projectRoot)/frontend"
        let cmd = "cd '\(frontendDir)' && npm run dev > /tmp/frontend.log 2>&1"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", cmd]

        do {
            try process.run()
            frontendProcess = process
        } catch {
            print("Failed to start frontend: \(error)")
        }
    }

    func stopFrontend() {
        frontendProcess?.terminate()
        frontendProcess = nil

        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-f", "vite"]
        try? killer.run()
    }
}
