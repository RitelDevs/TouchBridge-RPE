import Foundation
import XCTest
@testable import StudioCore

final class ProjectStoreTests: XCTestCase {
    func testResaveAfterMoveAndFailedSavePreservesExistingProject() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let first = root.appendingPathComponent("First.tbstudio"), moved = root.appendingPathComponent("Moved.tbstudio")
        let audio = root.appendingPathComponent("sample.wav"), bytes = Data([1, 3, 5, 8])
        try bytes.write(to: audio)
        var chart = ChartProject()
        try ProjectStore.write(chart, audioURL: audio, audioName: "Rain", to: first)
        try fm.moveItem(at: first, to: moved)
        try fm.removeItem(at: audio)
        let read = try ProjectStore.read(from: moved)
        chart.title = "After move"
        try ProjectStore.write(chart, audioURL: read.audioURL, audioName: read.audioName, to: moved)
        XCTAssertThrowsError(try ProjectStore.write(chart, audioURL: audio, audioName: "gone", to: moved))
        let saved = try ProjectStore.read(from: moved)
        XCTAssertEqual(saved.project, chart)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(saved.audioURL)), bytes)
        XCTAssertEqual(saved.audioName, "Rain")
    }
    func testDoesNotFollowSymlinkOrOverwriteUnrelatedDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let package = root.appendingPathComponent("Sample.tbstudio"), audio = root.appendingPathComponent("source.wav")
        try Data([1]).write(to: audio)
        XCTAssertThrowsError(try ProjectStore.write(ChartProject(), audioURL: nil, audioName: nil, to: root))
        try ProjectStore.write(ChartProject(), audioURL: audio, audioName: nil, to: package)
        let bundled = try XCTUnwrap(ProjectStore.read(from: package).audioURL)
        try fm.removeItem(at: bundled)
        try fm.createSymbolicLink(at: bundled, withDestinationURL: audio)
        XCTAssertThrowsError(try ProjectStore.read(from: package))
    }
}
