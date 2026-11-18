import Foundation
import Testing
@testable import StudioCore

struct ChartTests {
    @Test func simultaneousTapAndHoldKeepTheirOwnOriginAndDuration() throws {
        var recorder = GestureRecorder()
        recorder.begin(id: 1, x: 0.1, y: 0.7, time: 1)
        recorder.begin(id: 2, x: 0.9, y: 0.4, time: 1.02)
        let endedTap = recorder.end(id: 2, x: 0.9, y: 0.4, time: 1.12)
        let tap = try #require(endedTap)
        for frame in 1...30 {
            recorder.move(id: 1, x: frame.isMultiple(of: 2) ? 0.106 : 0.094, y: 0.7, time: 1 + Double(frame) / 60)
        }
        let endedHold = recorder.end(id: 1, x: 0.1, y: 0.7, time: 1.6)
        let hold = try #require(endedHold)
        #expect(tap.kind == .tap)
        #expect(tap.start == 1.02)
        #expect(tap.x == 0.9)
        #expect(hold.kind == .hold)
        #expect(hold.x == 0.1)
        #expect(abs(hold.duration - 0.6) < 0.000_001)
        #expect(hold.id != tap.id)
    }

    @Test func straightFastSwipeAndReturningDragDiffer() {
        var recorder = GestureRecorder()
        recorder.begin(id: 1, x: 0.5, y: 0.1, time: 0)
        recorder.move(id: 1, x: 0.5, y: 0.25, time: 0.02)
        #expect(recorder.end(id: 1, x: 0.5, y: 0.4, time: 0.08)?.kind == .flick)
        recorder.begin(id: 2, x: 0.2, y: 0.5, time: 1)
        recorder.move(id: 2, x: 0.7, y: 0.5, time: 1.08)
        #expect(recorder.end(id: 2, x: 0.2, y: 0.5, time: 1.15)?.kind == .drag)
        recorder.begin(id: 3, x: 0.1, y: 0.1, time: 2)
        #expect(recorder.end(id: 3, x: 0.6, y: 0.1, time: 3)?.kind == .drag)
    }

    @Test func cancelledContactsAndStaleSamplesEmitNoExtraNotes() {
        var recorder = GestureRecorder()
        recorder.begin(id: 4, x: 0.2, y: 0.3, time: 0)
        recorder.begin(id: 5, x: 0.8, y: 0.3, time: 0)
        recorder.cancelAll()
        #expect(recorder.end(id: 4, x: 0.3, y: 0.3, time: 0.1) == nil)
        #expect(recorder.end(id: 5, x: 0.8, y: 0.3, time: 0.2) == nil)
        recorder.begin(id: 4, x: 0.4, y: 0.3, time: 5)
        recorder.move(id: 4, x: 0.4, y: 0.3, time: 5.1)
        recorder.move(id: 4, x: 1, y: 1, time: 5.05)
        #expect(recorder.end(id: 4, x: 0.4, y: 0.3, time: 4) == nil)
        #expect(recorder.end(id: 4, x: 0.4, y: 0.3, time: 5.2)?.kind == .tap)
        #expect(recorder.end(id: 4, x: 0.4, y: 0.3, time: 5.2) == nil)
    }

    @Test func quantizationSnapsBothEndsAndPreservesIdentity() {
        let input = ChartNote(kind: .hold, start: 0.068, duration: 0.24, x: 0.2)
        let snapped = quantize(input, bpm: 120, subdivision: 4)
        #expect(snapped.id == input.id)
        #expect(snapped.start == 0.125)
        #expect(snapped.duration == 0.125)
        #expect(snapped.x == input.x)
        #expect(quantize(input, bpm: 120, subdivision: 0) == input)
        #expect(quantize(input, bpm: .nan, subdivision: 4) == input)
        let tiny = ChartNote(kind: .hold, start: 0.121, duration: 0.003, x: 0.5)
        #expect(quantize(tiny, bpm: 120, subdivision: 4).duration == 0.125)
    }

    @Test func projectRoundTripAndInvalidImports() throws {
        var chart = ChartProject()
        chart.title = "A, B & C"
        let tap = ChartNote(kind: .tap, start: 0.2, x: 0.6)
        chart.notes = [tap, ChartNote(kind: .hold, start: 0.2, duration: 1, x: 0)]
        try chart.validate()
        let restored = try JSONDecoder().decode(ChartProject.self, from: JSONEncoder().encode(chart))
        #expect(restored == chart)
        chart.notes.append(tap)
        #expect(throws: ChartValidationError.duplicateNote(tap.id)) { try chart.validate() }
        for bad in [
            ChartNote(kind: .tap, start: .nan, x: 0),
            ChartNote(kind: .tap, start: 0, x: .infinity),
            ChartNote(kind: .drag, start: 0, duration: 1, x: 1),
            ChartNote(kind: .hold, start: 8, duration: 0, x: 0),
            ChartNote(kind: .hold, start: 86_399, duration: 2, x: 1),
        ] {
            chart.notes = [bad]
            #expect(throws: ChartValidationError.self) { try chart.validate() }
        }
        chart.notes = []
        chart.bpm = .nan
        #expect(throws: ChartValidationError.self) { try chart.validate() }
        chart.bpm = 120
        chart.title = "   "
        #expect(throws: ChartValidationError.self) { try chart.validate() }
    }
}
