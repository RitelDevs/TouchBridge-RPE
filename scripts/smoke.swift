import AVFoundation
import Foundation
import StudioCore

// Exercises the same session used by the window and leaves a small, original demo to open.
@main @MainActor
enum StudioSmoke {
    static func main() async throws {
        let fm = FileManager.default
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: temp) }
        let source = temp.appendingPathComponent("Pulse Study.wav")
        try synthesize(to: source)
        let studio = Studio()
        try studio.loadAudio(source)
        precondition(abs(studio.duration - 8) < 0.02)
        studio.updateMetadata { $0.title = "Pulse Study"; $0.composer = "TouchBridge Studio"; $0.charter = "Studio"; $0.difficulty = "Practice" }
        studio.toggleRecording()
        precondition(studio.isRecording, "audio device failed to start a take")
        try await Task.sleep(nanoseconds: 150_000_000)
        let tick = ProcessInfo.processInfo.systemUptime
        let a = CGPoint(x: 0.2, y: 0.4), b = CGPoint(x: 0.8, y: 0.4)
        for i in 0..<4 { studio.touchBegan(i, a, tick) }
        studio.touchEnded(0, a, tick + 0.06); studio.touchEnded(1, a, tick + 0.35)
        studio.touchEnded(2, b, tick + 0.1); studio.touchEnded(3, b, tick + 1.0)
        studio.touchBegan(4, a, tick); studio.cancelTouches(); studio.touchEnded(4, a, tick + 0.1)
        studio.stop()
        precondition(studio.project.notes.map(\.kind) == [.tap, .hold, .flick, .drag])
        studio.undo(); precondition(studio.project.notes.isEmpty)
        studio.redo(); precondition(studio.project.notes.count == 4)
        var chart = studio.project
        chart.notes = (0..<16).map { i in
            let pattern: [NoteKind] = [.tap,.tap,.drag,.tap,.flick,.tap,.hold,.tap]
            let positions = [0.20, 0.44, 0.66, 0.84, 0.66, 0.44, 0.28, 0.52]
            let kind = pattern[i % 8]
            return ChartNote(kind: kind, start: Double(i) * 0.5, duration: kind == .hold ? 0.5 : 0,
                             x: positions[i % 8])
        }
        let doc = out.appendingPathComponent("Pulse Study.tbstudio")
        try ProjectStore.write(chart, audioURL: source, audioName: source.lastPathComponent, to: doc)
        try fm.removeItem(at: source)
        let reopened = Studio(); reopened.openURL(doc)
        precondition(reopened.hasAudio && reopened.project == chart && !reopened.dirty)
        let contents = try ProjectStore.read(from: doc)
        // Resave using the embedded audio to exercise atomic replacement in place.
        try ProjectStore.write(chart, audioURL: contents.audioURL, audioName: contents.audioName, to: doc)
        try PEZExporter.export(project: chart, audioURL: contents.audioURL!, destination: out.appendingPathComponent("Pulse Study.pez"))
        print("PASS: audio clock, polyphonic take, cancel, undo/redo, portable save, reopen, resave, PEZ.")
    }
    static func synthesize(to url: URL) throws {
        let rate = 22050.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ]
        let f = try AVAudioFile(forWriting: url, settings: settings)
        let data = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(8 * rate))!
        data.frameLength = data.frameCapacity
        let pitches = [261.63, 329.63, 392.0, 523.25, 440.0, 392.0, 329.63, 293.66]
        for i in 0..<Int(data.frameLength) {
            let t = Double(i)/rate, beat = Int(t * 2), p = t - Double(beat)/2
            let carrier = 2 * .pi * pitches[beat % pitches.count] * p
            let attack = min(1, p * 140)
            let tone = (sin(carrier) + 0.17 * sin(2 * carrier)) * exp(-7 * p) * 0.31
            let kick = (beat.isMultiple(of: 2) ? 0.28 : 0.10) * exp(-22 * p) * sin(2 * .pi * (53 * p + 0.8 * (1-exp(-22*p))))
            data.floatChannelData![0][i] = Float((tone + kick) * attack * min(1, (8-t)*50))
        }
        try f.write(from: data)
    }
}
