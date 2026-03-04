import Foundation

struct AppDefinition: Identifiable {
    let name: String          // directory name, e.g. "everything-app"
    let path: String          // absolute path, e.g. "/Users/x/everything-app"
    let uvicornPath: String?  // absolute path to uvicorn binary, nil if no backend
    let hasFrontend: Bool     // has frontend/package.json
    var hasBackend: Bool { uvicornPath != nil }
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

        return AppDefinition(name: url.lastPathComponent, path: p,
                             uvicornPath: uvicorn, hasFrontend: hasFrontend)
    }.sorted { $0.name < $1.name }
}
