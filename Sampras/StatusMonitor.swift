import SwiftUI

@Observable
@MainActor
class StatusMonitor {
    var backendRunning: Bool = false
    var frontendRunning: Bool = false
    var frontendPort: Int? = nil

    private let frontendPorts = Array(5173...5178)
    private var timer: Timer?

    init() {
        startPolling()
    }

    private func startPolling() {
        Task { await poll() }

        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }
    }

    private func poll() async {
        await checkBackend()
        await checkFrontend()
    }

    private func checkBackend() async {
        guard let url = URL(string: "http://localhost:8000/health") else {
            backendRunning = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                backendRunning = true
            } else {
                backendRunning = false
            }
        } catch {
            backendRunning = false
        }
    }

    private func checkFrontend() async {
        for port in frontendPorts {
            guard let url = URL(string: "http://localhost:\(port)") else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 1.0

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 500 {
                    frontendRunning = true
                    frontendPort = port
                    return
                }
            } catch {
                // Try next port
            }
        }

        frontendRunning = false
        frontendPort = nil
    }

    var overallColor: Color {
        switch (backendRunning, frontendRunning) {
        case (true, true):
            return .green
        case (false, false):
            return .red
        default:
            return .orange
        }
    }
}
