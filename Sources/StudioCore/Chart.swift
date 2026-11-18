import Foundation

public enum NoteKind: String, Codable, CaseIterable, Sendable {
    case tap, hold, flick, drag
}

public struct ChartNote: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var kind: NoteKind
    /// Song time in seconds. Beat conversion belongs at the output boundary.
    public var start: Double
    public var duration: Double
    /// Horizontal position on the pad: 0 is the left edge and 1 the right edge.
    public var x: Double

    public init(id: UUID = UUID(), kind: NoteKind, start: Double, duration: Double = 0, x: Double) {
        self.id = id
        self.kind = kind
        self.start = start
        self.duration = duration
        self.x = x
    }
}

public enum ChartValidationError: LocalizedError, Equatable {
    case emptyTitle, invalidTempo, duplicateNote(UUID), invalidPosition(UUID), invalidTiming(UUID)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: return "请填写谱面名称。"
        case .invalidTempo: return "BPM 必须在 1 到 1000 之间。"
        case .duplicateNote: return "工程中存在标识相同的音符。"
        case .invalidPosition: return "音符位置超出了触控板范围。"
        case .invalidTiming: return "音符时间无效。仅 Hold 可以有时长，且必须大于零。"
        }
    }
}

public struct ChartProject: Codable, Equatable, Sendable {
    public static let supportedTempo = 1.0...1_000.0
    public static let maximumTime = 86_400.0
    public var title = "未命名谱面"
    public var composer = ""
    public var charter = ""
    public var difficulty = ""
    public var bpm = 120.0
    public var notes: [ChartNote] = []

    public init() {}

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChartValidationError.emptyTitle
        }
        guard Self.supportedTempo.contains(bpm) else { throw ChartValidationError.invalidTempo }
        var seen = Set<UUID>()
        for note in notes {
            guard seen.insert(note.id).inserted else { throw ChartValidationError.duplicateNote(note.id) }
            guard (0.0...1.0).contains(note.x) else { throw ChartValidationError.invalidPosition(note.id) }
            guard (0.0...Self.maximumTime).contains(note.start),
                  note.duration.isFinite,
                  (note.kind == .hold ? note.duration > 0 : note.duration == 0),
                  note.start + note.duration <= Self.maximumTime else {
                throw ChartValidationError.invalidTiming(note.id)
            }
        }
    }
}

public struct GestureRecorder: Sendable {
    private struct Track: Sendable {
        let start: Double, x: Double, y: Double
        var lastTime: Double, anchorX: Double, anchorY: Double
        var path = 0.0, excursion = 0.0

        mutating func sample(x nextX: Double, y nextY: Double, time: Double) {
            lastTime = time
            excursion = max(excursion, hypot(nextX - x, nextY - y))
            // Keep an anchor between packets: slow deliberate motion accumulates, sensor jitter does not.
            let step = hypot(nextX - anchorX, nextY - anchorY)
            if step >= 0.008 {
                path += step
                anchorX = nextX
                anchorY = nextY
            }
        }
    }

    private var tracks: [Int: Track] = [:]
    public init() {}

    public mutating func begin(id: Int, x: Double, y: Double, time: Double) {
        guard let (x, y) = coordinates(x, y), (0.0...ChartProject.maximumTime).contains(time) else { return }
        if let previous = tracks[id], time <= previous.lastTime { return }
        tracks[id] = Track(start: time, x: x, y: y, lastTime: time, anchorX: x, anchorY: y)
    }

    public mutating func move(id: Int, x: Double, y: Double, time: Double) {
        guard let (x, y) = coordinates(x, y), let track = tracks[id],
              time >= track.lastTime, time <= ChartProject.maximumTime else { return }
        tracks[id]?.sample(x: x, y: y, time: time)
    }

    public mutating func end(id: Int, x: Double, y: Double, time: Double) -> ChartNote? {
        guard var track = tracks[id], time >= track.lastTime else { return nil }
        tracks[id] = nil
        guard let (x, y) = coordinates(x, y), time <= ChartProject.maximumTime else { return nil }
        track.sample(x: x, y: y, time: time)
        let elapsed = time - track.start
        let displacement = hypot(x - track.x, y - track.y)
        let kind: NoteKind
        if displacement >= 0.10, displacement >= 0.70 * track.path,
           displacement >= 1.05 * max(elapsed, 0.001) {
            kind = .flick
        } else if track.excursion >= 0.045 || (track.excursion >= 0.025 && track.path >= 0.12) {
            kind = .drag
        } else {
            kind = elapsed >= 0.32 ? .hold : .tap
        }
        return ChartNote(kind: kind, start: track.start, duration: kind == .hold ? elapsed : 0, x: track.x)
    }

    public mutating func cancelAll() { tracks.removeAll(keepingCapacity: true) }

    private func coordinates(_ x: Double, _ y: Double) -> (Double, Double)? {
        guard x.isFinite, y.isFinite else { return nil }
        return (min(1, max(0, x)), min(1, max(0, y)))
    }
}

/// The subdivision is the number of equal grid intervals per beat; zero leaves timing untouched.
public func quantize(_ note: ChartNote, bpm: Double, subdivision: Int) -> ChartNote {
    guard subdivision > 0, ChartProject.supportedTempo.contains(bpm),
          (0.0...ChartProject.maximumTime).contains(note.start),
          (0.0...ChartProject.maximumTime).contains(note.duration) else { return note }
    let step = 60 / bpm / Double(subdivision)
    let limit = ChartProject.maximumTime
    let snap = { (value: Double) in min(limit, (value / step).rounded() * step) }
    var result = note
    result.start = snap(note.start)
    if note.kind == .hold {
        let end = min(limit, max(snap(note.start + note.duration), result.start + step))
        if result.start >= end { result.start = max(0, end - step) }
        result.duration = end - result.start
    }
    return result
}
