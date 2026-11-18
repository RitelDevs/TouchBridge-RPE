import Foundation

/// A portable package. The manifest never references paths outside the package.
public enum ProjectStore {
    private struct Manifest: Codable {
        let version: Int
        let chart: ChartProject
        let audio: String?
        let audioName: String?
    }

    public struct Contents {
        public let project: ChartProject
        public let audioURL: URL?
        public let audioName: String?
    }

    public enum Failure: LocalizedError {
        case unsupportedVersion, invalidPackage
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "工程版本较新，当前版本无法打开。"
            case .invalidPackage: return "工程内容不完整，或引用了工程外的文件。"
            }
        }
    }

    private static let manifestName = "project.json"
    private static func isPlain(_ url: URL, directory: Bool = false) throws -> Bool {
        let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        return v.isSymbolicLink != true && (directory ? v.isDirectory == true : v.isRegularFile == true)
    }

    public static func read(from url: URL) throws -> Contents {
        let file = url.appendingPathComponent(manifestName)
        guard try isPlain(url, directory: true), try isPlain(file) else { throw Failure.invalidPackage }
        let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: file))
        guard m.version == 1 else { throw Failure.unsupportedVersion }
        try m.chart.validate()
        let audio = try m.audio.map { name -> URL in
            guard name.range(of: #"^audio\.[A-Za-z0-9]{1,10}$"#, options: .regularExpression) != nil,
                  !name.contains("/") else { throw Failure.invalidPackage }
            let file = url.appendingPathComponent(name)
            guard try isPlain(file) else { throw Failure.invalidPackage }
            return file
        }
        return Contents(project: m.chart, audioURL: audio, audioName: m.audioName)
    }

    public static func write(_ chart: ChartProject, audioURL: URL?, audioName: String?, to url: URL) throws {
        try chart.validate()
        let fm = FileManager.default
        // Stage alongside the destination; on failure the previous project stays intact.
        let staging = url.deletingLastPathComponent().appendingPathComponent(".tb-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let stored = try audioURL.map { src -> String in
            let ext = src.pathExtension.lowercased()
            guard ext.range(of: #"^[a-z0-9]{1,10}$"#, options: .regularExpression) != nil,
                  try isPlain(src.resolvingSymlinksInPath()) else { throw Failure.invalidPackage }
            let name = "audio." + ext
            try fm.copyItem(at: src.resolvingSymlinksInPath(), to: staging.appendingPathComponent(name))
            return name
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Manifest(version: 1, chart: chart, audio: stored, audioName: audioName))
            .write(to: staging.appendingPathComponent(manifestName))
        if fm.fileExists(atPath: url.path) {
            // Only replace our own packages, never an unrelated directory chosen by mistake.
            _ = try read(from: url)
            _ = try fm.replaceItemAt(url, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: url)
        }
    }
}
