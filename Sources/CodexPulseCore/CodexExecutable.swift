import Foundation

public enum CodexExecutable {
    public static func resolve(path: String? = nil) throws -> URL {
        let selected = path ?? ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .first(where: FileManager.default.isExecutableFile(atPath:)) ?? ""
        guard selected.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: selected) else {
            throw ProbeError.codexNotInstalled
        }
        return URL(fileURLWithPath: selected)
    }
}
