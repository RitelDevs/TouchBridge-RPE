import AVFoundation
import Foundation
import XCTest
import StudioCore
@testable import StudioApp

final class SessionTests: XCTestCase {
    @MainActor
    func testEditingValidationAndHistory() async throws {
        let studio = Studio()
        studio.subdivision = 4
        studio.addNote(at: 0.26, x: 0.7)
        XCTAssertEqual(studio.project.notes.first?.start, 0.25)
        studio.updateMetadata { $0.bpm = 0 }
        XCTAssertEqual(studio.project.bpm, 120)
        studio.deleteSelected(); XCTAssertTrue(studio.project.notes.isEmpty)
        studio.undo(); XCTAssertEqual(studio.project.notes.count, 1)
        studio.undo(); XCTAssertFalse(studio.dirty)
        studio.redo(); XCTAssertEqual(studio.project.notes.count, 1)
    }

    @MainActor
    func testAudioSessionRecordUndoAndPortableReopen() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let audio = root.appendingPathComponent("source.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        do {
            let f = try AVAudioFile(forWriting: audio, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88200))
            buffer.frameLength = buffer.frameCapacity
            memset(buffer.floatChannelData![0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.stride)
            try f.write(from: buffer)
        }
        let studio = Studio()
        try studio.loadAudio(audio); studio.subdivision = 0
        XCTAssertEqual(studio.duration, 2, accuracy: 0.02)
        studio.seek(0.5); studio.toggleRecording()
        guard studio.isRecording else { XCTFail(studio.status); return }
        defer { studio.stop() }
        try await Task.sleep(nanoseconds: 180_000_000)
        let t = ProcessInfo.processInfo.systemUptime
        let point = CGPoint(x: 0.3, y: 0.6)
        studio.touchBegan(42, point, t); studio.touchBegan(43, point, t)
        studio.touchEnded(42, point, t + 0.05); studio.touchEnded(43, point, t + 0.4)
        studio.touchBegan(80, point, t); studio.cancelTouches(); studio.touchEnded(80, point, t + 0.3)
        studio.stop()
        XCTAssertEqual(studio.project.notes.map(\.kind), [.tap, .hold])
        let start = try XCTUnwrap(studio.project.notes.first?.start)
        XCTAssertGreaterThan(start, 0.5)
        let take = studio.project
        studio.undo(); XCTAssertTrue(studio.project.notes.isEmpty)
        studio.redo(); XCTAssertEqual(studio.project, take)
        let doc = root.appendingPathComponent("demo.tbstudio")
        try ProjectStore.write(take, audioURL: audio, audioName: "source.wav", to: doc)
        try fm.removeItem(at: audio)
        let reopened = Studio()
        reopened.openURL(doc)
        XCTAssertTrue(reopened.hasAudio); XCTAssertEqual(reopened.project, take)
        XCTAssertFalse(reopened.dirty)
        let loaded = try ProjectStore.read(from: doc)
        try PEZExporter.export(project: loaded.project, audioURL: XCTUnwrap(loaded.audioURL),
                               destination: root.appendingPathComponent("demo.pez"))
    }
}
