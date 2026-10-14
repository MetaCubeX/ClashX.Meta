import Foundation

enum MihomoConfigComposer {
    static func applyingSystemStackDefault(to source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        guard let tunIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed == "tun:"
        }) else { return source }

        let end = lines[(tunIndex + 1)...].firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#") && !line.hasPrefix(" ") && !line.hasPrefix("\t")
        }) ?? lines.endIndex

        if let stackIndex = lines[(tunIndex + 1)..<end].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("stack:")
        }) {
            let value = lines[stackIndex].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[1]
                .trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value.hasPrefix("#") {
                let indent = String(lines[stackIndex].prefix { $0 == " " || $0 == "\t" })
                lines[stackIndex] = "\(indent)stack: system"
            }
        } else {
            let indent = lines[(tunIndex + 1)..<end]
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .map { String($0.prefix { $0 == " " || $0 == "\t" }) } ?? "  "
            lines.insert("\(indent)stack: system", at: tunIndex + 1)
        }
        return lines.joined(separator: "\n")
    }

    static func effectiveConfigPath(for sourcePath: String) throws -> String {
        let source = try String(contentsOfFile: sourcePath, encoding: .utf8)
        let effective = applyingSystemStackDefault(to: source)
        let directory = URL(fileURLWithPath: kConfigFolderPath).appendingPathComponent("mihomo-runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("effective.yaml")
        try effective.write(to: destination, atomically: true, encoding: .utf8)
        return destination.path
    }
}
