import Foundation
import ImageIO
import XCTest
@testable import StudioCore

final class PEZTests: XCTestCase {
    func testExportIsSelfContainedAndPreservesBeatsAndKinds() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let audio = root.appendingPathComponent("odd name.wav"), pez = root.appendingPathComponent("demo.pez")
        let bytes = Data([6,1,7,4])
        try bytes.write(to: audio)
        var chart = ChartProject()
        chart.title = "Test\nImage: other.png"
        chart.notes = [
            ChartNote(kind: .hold, start: 1.25, duration: 0.5, x: 0.5),
            ChartNote(kind: .tap, start: 0, x: 0), ChartNote(kind: .flick, start: 2, x: 1),
            ChartNote(kind: .drag, start: 3, x: 0.3)
        ]
        try PEZExporter.export(project: chart, audioURL: audio, destination: pez)
        let entries = root.appendingPathComponent("unzipped")
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-qq", pez.path, "-d", entries.path]
        try unzip.run(); unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: entries.path)), ["info.txt", "cover.png", "chart.json", "music.wav"])
        let info = try String(contentsOf: entries.appendingPathComponent("info.txt"), encoding: .utf8)
        XCTAssertTrue(info.hasPrefix("#\n"))
        XCTAssertEqual(info.components(separatedBy: "\n").filter { $0.hasPrefix("Image:") }, ["Image: cover.png"])
        XCTAssertTrue(info.contains("Music: music.wav")); XCTAssertTrue(info.contains("Chart: chart.json"))
        XCTAssertEqual(try Data(contentsOf: entries.appendingPathComponent("music.wav")), bytes)
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(entries.appendingPathComponent("cover.png") as CFURL, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(image, 0, nil))
        let content = try Data(contentsOf: entries.appendingPathComponent("chart.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: content) as? [String: Any])
        let line = try XCTUnwrap((json["judgeLineList"] as? [[String: Any]])?.first)
        let notes = try XCTUnwrap(line["notes"] as? [[String: Any]])
        XCTAssertEqual(notes.compactMap { $0["type"] as? Int }, [1,2,3,4])
        XCTAssertEqual(notes[1]["startTime"] as? [Int], [2,1,2]); XCTAssertEqual(notes[1]["endTime"] as? [Int], [3,1,2])
        for i in [0,2,3] { XCTAssertEqual(notes[i]["startTime"] as? [Int], notes[i]["endTime"] as? [Int]) }
        XCTAssertEqual(notes[0]["positionX"] as? Double, -675); XCTAssertEqual(notes[2]["positionX"] as? Double, 675)
    }
}
