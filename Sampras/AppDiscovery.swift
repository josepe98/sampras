import Foundation

struct AppDefinition: Identifiable {
    let name: String       // directory name, e.g. "everything-app"
    let path: String       // absolute path, e.g. "/Users/x/everything-app"
    let hasBackend: Bool   // has venv/bin/uvicorn
    let hasFrontend: Bool  // has frontend/package.json
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
        let hasBackend  = fm.fileExists(atPath: "\(p)/venv/bin/uvicorn")
        let hasFrontend = fm.fileExists(atPath: "\(p)/frontend/package.json")
        guard hasBackend || hasFrontend else { return nil }

        return AppDefinition(name: url.lastPathComponent, path: p,
                             hasBackend: hasBackend, hasFrontend: hasFrontend)
    }.sorted { $0.name < $1.name }
}
