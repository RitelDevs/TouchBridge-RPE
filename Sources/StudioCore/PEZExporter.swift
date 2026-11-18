import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

public enum PEZExporter {
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TouchBridge.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    public static func export(project: ChartProject, audioURL: URL, destination: URL) throws {
        try project.validate()
        let fm = FileManager.default, source = audioURL.resolvingSymlinksInPath()
        let target = destination.standardizedFileURL
        guard source.standardizedFileURL != target.resolvingSymlinksInPath(),
              !project.notes.isEmpty else { throw failure("需要至少一个音符，且不能覆盖原音频。") }
        let ext = source.pathExtension.lowercased()
        guard ext.range(of: #"^[a-z0-9]{1,10}$"#, options: .regularExpression) != nil,
              try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else { throw failure("缺少可导出的音频文件。") }
        let staging = target.deletingLastPathComponent().appendingPathComponent(".pez-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let music = "music." + ext, archive = staging.appendingPathComponent("export.zip")
        try fm.copyItem(at: source, to: staging.appendingPathComponent(music))
        try cover(staging.appendingPathComponent("cover.png"))
        let line: (String) -> String = { $0.components(separatedBy: .newlines).joined(separator: " ") }
        let info = ["#", "Name: " + line(project.title), "Composer: " + line(project.composer),
                    "Charter: " + line(project.charter), "Level: " + line(project.difficulty),
                    "Chart: chart.json", "Music: " + music, "Image: cover.png", ""].joined(separator: "\n")
        try info.write(to: staging.appendingPathComponent("info.txt"), atomically: false, encoding: .utf8)
        let chart = makeChart(project, music: music)
        try JSONSerialization.data(withJSONObject: chart, options: [.sortedKeys])
            .write(to: staging.appendingPathComponent("chart.json"))
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); zip.currentDirectoryURL = staging
        zip.arguments = ["-q", "-X", "export.zip", "info.txt", "chart.json", music, "cover.png"]
        var env = ProcessInfo.processInfo.environment; env["ZIPOPT"] = nil; zip.environment = env
        try zip.run(); zip.waitUntilExit()
        guard zip.terminationStatus == 0 else { throw failure("无法创建 PEZ 压缩包。") }
        guard rename(archive.path, target.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func makeChart(_ project: ChartProject, music: String) -> [String: Any] {
        let resolution = 1920
        let ticks: (Double) -> Int = { Int(($0 * project.bpm / 60 * Double(resolution)).rounded()) }
        let beat: (Int) -> [Int] = { t in
            let r = t % resolution
            if r == 0 { return [t / resolution, 0, 1] }
            var a = resolution, b = r
            while b != 0 { (a,b) = (b,a%b) }
            return [t / resolution, r/a, resolution/a]
        }
        let type: [NoteKind: Int] = [.tap: 1, .hold: 2, .flick: 3, .drag: 4]
        let notes: [[String: Any]] = project.notes.sorted {
            $0.start != $1.start ? $0.start < $1.start : $0.id.uuidString < $1.id.uuidString
        }.map { n in
            let start = ticks(n.start), end = n.kind == .hold ? max(start + 1, ticks(n.start + n.duration)) : start
            return ["type": type[n.kind]!, "above": 1, "startTime": beat(start), "endTime": beat(end),
                    "positionX": (n.x - 0.5) * 1350, "yOffset": 0, "size": 1, "speed": 1,
                    "alpha": 255, "isFake": 0, "visibleTime": 999999]
        }
        let last = project.notes.map { ticks($0.start + $0.duration) }.max() ?? 0
        func event(_ value: Int) -> [[String: Any]] {
            [["startTime": [0,0,1], "endTime": beat(last + 4 * resolution), "start": value,
              "end": value, "easingType": 1, "easingLeft": 0, "easingRight": 1,
              "bezier": 0, "bezierPoints": [0,0,0,0]]]
        }
        let layer = ["alphaEvents": event(255), "moveXEvents": event(0), "moveYEvents": event(0),
                     "rotateEvents": event(0), "speedEvents": event(10)]
        let judge: [String: Any] = ["Name":"Main", "Texture":"line.png", "Group":0, "bpmfactor":1,
                                    "father":-1, "isCover":1, "zOrder":0, "numOfNotes":notes.count,
                                    "eventLayers":[layer], "notes":notes]
        let meta: [String: Any] = ["RPEVersion":150, "offset":0, "name":project.title, "song":music,
                                   "background":"cover.png", "composer":project.composer, "charter":project.charter,
                                   "level":project.difficulty, "illustrator":"TouchBridge Studio"]
        return ["META":meta, "BPMList":[["bpm":project.bpm, "startTime":[0,0,1]]],
                "judgeLineGroup":["Default"], "judgeLineList":[judge]]
    }

    private static func cover(_ url: URL) throws {
        let w = 512, h = 288
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw failure("无法生成封面。") }
        ctx.setFillColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for i in 0..<32 {
            let height = 16 + (sin(Double(i)*0.42)+1)*48 + (cos(Double(i)*1.28)+1)*14
            ctx.setFillColor(red: 0.43, green: 0.84, blue: 0.73, alpha: 1)
            let x = CGFloat(21 + i * 15)
            ctx.fill(CGRect(x: x, y: 144 - CGFloat(height)/2, width: 6, height: CGFloat(height)))
        }
        guard let img = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw failure("无法写入封面。") }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw failure("无法完成封面。") }
    }
}
