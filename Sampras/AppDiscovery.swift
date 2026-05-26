import Foundation

struct AppDefinition: Identifiable {
    let name: String              // directory name, e.g. "everything-app"
    let path: String              // absolute path, e.g. "/Users/x/everything-app"
    let uvicornPath: String?      // absolute path to uvicorn binary, nil if no uvicorn backend
    let uvicornModule: String     // e.g. "app.main:app" or "main:app"
    let hasFrontend: Bool         // has frontend/package.json
    let customBackendCmd: String? // shell command run in place of uvicorn; PORT=\(port) prepended at launch
    var hasBackend: Bool { uvicornPath != nil || customBackendCmd != nil }
    var id: String { name }
}

/// Scans the home directory for project folders that look like backend or frontend apps.
func discoverApps() -> [AppDefinition] {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let skip: Set<String> = [
        "Library", "Desktop", "Documents", "Downloads",
        "Movies", "Music", "Pictures", "Public",
        "Applications", "Sites", ".Trash"
    ]

    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(
        at: home,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    ) else { return [] }

    return entries.compactMap { url in
        guard !skip.contains(url.lastPathComponent),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { return nil }

        let p = url.path
        // venv may live at the project root or inside backend/
        let uvicorn: String? = ["\(p)/venv/bin/uvicorn", "\(p)/backend/venv/bin/uvicorn"]
            .first(where: { fm.fileExists(atPath: $0) })
        let hasFrontend = fm.fileExists(atPath: "\(p)/frontend/package.json")
        guard uvicorn != nil || hasFrontend else { return nil }

        // Detect module path: prefer app/main.py, fall back to main.py
        let backendRoot = fm.fileExists(atPath: "\(p)/backend/app/main.py") || fm.fileExists(atPath: "\(p)/app/main.py")
        let uvicornModule = backendRoot ? "app.main:app" : "main:app"

        return AppDefinition(name: url.lastPathComponent, path: p,
                             uvicornPath: uvicorn, uvicornModule: uvicornModule,
                             hasFrontend: hasFrontend, customBackendCmd: nil)
    }.sorted { $0.name < $1.name }
}

/// Returns any well-known apps that don't follow the standard uvicorn/npm pattern.
/// These are merged into the result of `discoverApps()` for menu purposes.
func discoverSpecialApps() -> [AppDefinition] {
    let fm = FileManager.default
    let home = NSHomeDirectory()
    var apps: [AppDefinition] = []

    // ── claude-usage ──────────────────────────────────────────────────────────
    // Runs dashboard.py directly with Python (no uvicorn). Respects PORT env var.
    let claudeUsagePath = "\(home)/claude-usage"
    if fm.fileExists(atPath: "\(claudeUsagePath)/dashboard.py") {
        let python = "\(home)/.venv/bin/python"
        let pythonExe = fm.fileExists(atPath: python) ? python : "/usr/bin/python3"
        apps.append(AppDefinition(
            name: "claude-usage",
            path: claudeUsagePath,
            uvicornPath: nil,
            uvicornModule: "",
            hasFrontend: false,
            customBackendCmd: "'\(pythonExe)' dashboard.py"
        ))
    }

    return apps
}
