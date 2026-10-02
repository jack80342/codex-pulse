import Foundation

public enum CodexExecutable {
    public static func resolve(path: String? = nil) throws -> URL {
        let candidates = path.map { [$0] } ?? automaticCandidates(
            environment: ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser)
        guard let selected = candidates.first(where: { candidate in
            candidate.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: candidate) &&
            (try? URL(fileURLWithPath: candidate).resolvingSymlinksInPath()
                .resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }) else { throw ProbeError.codexNotInstalled }
        return URL(fileURLWithPath: selected)
    }

    /// 有界位置查找，不运行登录 Shell、不读取用户启动脚本或递归扫描磁盘。
    static func automaticCandidates(environment: [String: String], home: URL) -> [String] {
        var paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        paths += (environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path }
        paths += [".local/bin", "bin", ".npm-global/bin", ".volta/bin"]
            .map { home.appendingPathComponent($0).appendingPathComponent("codex").path }
        for (directory, suffix) in [(".nvm/versions/node", "bin/codex"), (".fnm/node-versions", "installation/bin/codex")] {
            let versions = (try? FileManager.default.contentsOfDirectory(
                at: home.appendingPathComponent(directory), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            paths += versions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent(suffix).path }
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
