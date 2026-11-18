import AppKit
import AVFoundation
import Combine
import StudioCore
import UniformTypeIdentifiers

@MainActor
final class Studio: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var project = ChartProject()
    @Published var selected: UUID?
    @Published private(set) var currentTime = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isRecording = false
    @Published private(set) var audioName = ""
    @Published var subdivision = 4
    @Published var status = "就绪"
    @Published private(set) var activeTouches: [Int: CGPoint] = [:]
    @Published private(set) var dirty = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    var projectName: String { projectURL?.deletingPathExtension().lastPathComponent ?? project.title }
    var hasAudio: Bool { player != nil }
    private var history: [ChartProject] = [], future: [ChartProject] = []
    private var takeStart: ChartProject?
    private var recorder = GestureRecorder()
    private var player: AVAudioPlayer?
    private var audioURL: URL?, projectURL: URL?
    private var timer: Timer?
    private var savedProject = ChartProject()
    private var audioChanged = false
    // Device and event timestamps advance independently. Keep an anchor in each domain.
    private var deviceStart = 0.0, songStart = 0.0, uptimeStart = 0.0

    private func updateFlags() {
        dirty = audioChanged || project != savedProject
        canUndo = !history.isEmpty && !isRecording
        canRedo = !future.isEmpty && !isRecording
    }

    private func remember(_ old: ChartProject) {
        history.append(old)
        if history.count > 64 { history.removeFirst() }
        future.removeAll()
    }

    func updateMetadata(_ change: (inout ChartProject) -> Void) {
        guard !isRecording else { return }
        var next = project
        change(&next)
        guard next != project else { return }
        do { try next.validate() } catch { status = error.localizedDescription; return }
        remember(project); project = next; updateFlags()
    }

    func updateNote(_ note: ChartNote) {
        updateMetadata { project in
            if let i = project.notes.firstIndex(where: { $0.id == note.id }) { project.notes[i] = note }
        }
    }

    func addNote(at time: Double, x: Double) {
        guard !isRecording, time.isFinite, x.isFinite else { return }
        let note = quantize(ChartNote(kind: .tap, start: max(0, time), x: min(1, max(0, x))),
                            bpm: project.bpm, subdivision: subdivision)
        updateMetadata { $0.notes.append(note) }; selected = note.id
    }

    func deleteSelected() {
        guard !isRecording, let id = selected else { return }
        updateMetadata { $0.notes.removeAll { $0.id == id } }; selected = nil
    }

    func undo() {
        guard !isRecording, let previous = history.popLast() else { return }
        future.append(project); project = previous; selected = nil; updateFlags()
    }
    func redo() {
        guard !isRecording, let next = future.popLast() else { return }
        history.append(project); project = next; selected = nil; updateFlags()
    }

    private func install(_ next: AVAudioPlayer?, url: URL?, name: String?) {
        player?.delegate = nil; player?.stop()
        player = next; next?.delegate = self
        audioURL = url; audioName = name ?? ""; duration = next?.duration ?? 0; currentTime = 0
    }

    @discardableResult
    func loadAudio(_ url: URL) throws -> Bool {
        let next = try Self.prepare(url)
        stop()
        install(next, url: url, name: url.lastPathComponent)
        audioChanged = true; updateFlags(); status = "已导入音乐"
        return true
    }

    private static func prepare(_ url: URL) throws -> AVAudioPlayer {
        let next = try AVAudioPlayer(contentsOf: url)
        guard next.duration.isFinite, next.duration > 0, next.prepareToPlay() else {
            throw NSError(domain: "Studio", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法播放此音频。"])
        }
        return next
    }

    func importAudio() {
        stop()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]; panel.prompt = "导入音乐"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try loadAudio(url) } catch { status = "导入失败：" + error.localizedDescription }
    }
    func newProject() {
        stop()
        guard permitDiscard() else { return }
        install(nil, url: nil, name: nil); project = ChartProject(); projectURL = nil
        resetEdits(); status = "新工程"
    }
    private func resetEdits() {
        history.removeAll(); future.removeAll(); selected = nil; savedProject = project
        audioChanged = false; updateFlags()
    }
    func openProject() {
        stop()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.studioProject]
        panel.treatsFilePackagesAsDirectories = false; panel.prompt = "打开工程"
        if panel.runModal() == .OK, let url = panel.url { openURL(url) }
    }
    func openURL(_ url: URL) {
        stop()
        do {
            let loaded = try ProjectStore.read(from: url)
            let next = try loaded.audioURL.map(Self.prepare)
            guard permitDiscard() else { return }
            project = loaded.project; projectURL = url
            install(next, url: loaded.audioURL, name: loaded.audioName)
            resetEdits(); status = "已打开工程"
        } catch { status = "打开失败：" + error.localizedDescription }
    }
    func saveProject() { _ = persist() }
    private func persist() -> Bool {
        stop()
        let destination: URL
        if let url = projectURL { destination = url }
        else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.studioProject]
            panel.nameFieldStringValue = Self.suggestion(project.title) + ".tbstudio"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        do {
            try ProjectStore.write(project, audioURL: audioURL, audioName: audioName, to: destination)
            let stored = try ProjectStore.read(from: destination)
            projectURL = destination; audioURL = stored.audioURL
            savedProject = project; audioChanged = false; updateFlags(); status = "工程已保存"
            return true
        } catch { status = "保存失败：" + error.localizedDescription; return false }
    }
    private static func suggestion(_ value: String) -> String {
        let s = value.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "-")
        return s.isEmpty ? "Untitled" : String(s.prefix(80))
    }
    func permitDiscard() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "保存工程更改？"; alert.informativeText = projectName
        for label in ["保存", "取消", "不保存"] { alert.addButton(withTitle: label) }
        switch alert.runModal() {
        case .alertFirstButtonReturn: return persist()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    func exportPEZ() {
        stop()
        guard let audioURL else { status = "请先导入音乐"; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pez") ?? .data]
        panel.nameFieldStringValue = Self.suggestion(project.title) + ".pez"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PEZExporter.export(project: project, audioURL: audioURL, destination: url)
            status = "已导出 " + url.lastPathComponent
        } catch { status = "导出失败：" + error.localizedDescription }
    }

    func togglePlayback() { if isPlaying { stop() } else { play(record: false) } }
    func toggleRecording() {
        if isRecording { stop() }
        else { if isPlaying { stop() }; play(record: true) }
    }

    private func play(record: Bool) {
        guard let player else { status = "请先导入音乐"; return }
        if currentTime >= duration { currentTime = 0 }
        player.currentTime = currentTime
        let uptime = ProcessInfo.processInfo.systemUptime
        let device = player.deviceCurrentTime
        let preroll = 0.08
        guard player.play(atTime: device + preroll) else { status = "播放失败"; return }
        deviceStart = device + preroll; songStart = currentTime; uptimeStart = uptime + preroll
        isPlaying = true; isRecording = record
        takeStart = record ? project : nil; updateFlags()
        status = record ? "录制中" : "播放中"
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard isPlaying, let player else { return }
        currentTime = min(duration, songStart + max(0, player.deviceCurrentTime - deviceStart))
        if currentTime >= duration { stop(atEnd: true) }
    }
    func stop(atEnd: Bool = false) {
        cancelTouches()
        guard isPlaying else { return }
        if let player {
            currentTime = atEnd ? duration : min(duration, songStart + max(0, player.deviceCurrentTime - deviceStart))
            player.pause()
        }
        timer?.invalidate(); timer = nil
        let recorded = isRecording
        isRecording = false; isPlaying = false
        if let before = takeStart, before != project { remember(before) }
        takeStart = nil; updateFlags()
        status = recorded ? "录制结束" : (atEnd ? "播放结束" : "已暂停")
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player, self.isPlaying,
                  !player.isPlaying, player.deviceCurrentTime >= self.deviceStart else { return }
            self.stop(atEnd: flag)
            if !flag { self.status = "音频播放中断" }
        }
    }
    func seek(_ time: Double) {
        guard time.isFinite, !isRecording else { return }
        let resume = isPlaying
        if resume { stop() }
        currentTime = min(hasAudio ? duration : max(0, time), max(0, time))
        player?.currentTime = currentTime
        if resume && currentTime < duration { play(record: false) }
    }
    func cancelTouches() { recorder.cancelAll(); activeTouches.removeAll() }
    private func songTime(_ uptime: Double) -> Double? {
        guard isRecording, uptime >= uptimeStart else { return nil }
        return min(duration, songStart + uptime - uptimeStart)
    }
    func touchBegan(_ id: Int, _ point: CGPoint, _ uptime: Double) {
        activeTouches[id] = point
        guard let t = songTime(uptime), t < duration else { return }
        recorder.begin(id: id, x: point.x, y: point.y, time: t)
    }
    func touchMoved(_ id: Int, _ point: CGPoint, _ uptime: Double) {
        guard activeTouches[id] != nil else { return }
        activeTouches[id] = point
        guard let t = songTime(uptime) else { return }
        recorder.move(id: id, x: point.x, y: point.y, time: t)
    }
    func touchEnded(_ id: Int, _ point: CGPoint, _ uptime: Double) {
        activeTouches[id] = nil
        guard let t = songTime(uptime),
              let note = recorder.end(id: id, x: point.x, y: point.y, time: t) else { return }
        project.notes.append(quantize(note, bpm: project.bpm, subdivision: subdivision))
        selected = note.id; dirty = true
    }
}

extension UTType {
    static let studioProject = UTType(exportedAs: "dev.ritel.touchbridge.project", conformingTo: .package)
}
