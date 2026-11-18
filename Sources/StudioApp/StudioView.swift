import SwiftUI
import StudioCore

private enum Ink {
    static let studio = Color(red: 0.093, green: 0.099, blue: 0.105)
    static let panel = Color(red: 0.123, green: 0.130, blue: 0.136)
    static let pad = Color(red: 0.061, green: 0.069, blue: 0.073)
    static let line = Color.white.opacity(0.105)
    static let mint = Color(red: 0.46, green: 0.88, blue: 0.75)
    static let coral = Color(red: 1, green: 0.48, blue: 0.45)
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
}

private extension NoteKind {
    var label: String { rawValue.capitalized }
    var tint: Color {
        switch self {
        case .tap: return .init(red: 0.42, green: 0.78, blue: 1)
        case .hold: return Ink.mint
        case .flick: return Ink.coral
        case .drag: return .init(red: 1, green: 0.81, blue: 0.38)
        }
    }
}

private func clockText(_ t: Double, precise: Bool = false) -> String {
    let ms = Int(max(0, min(t.isFinite ? t : 0, 1e9)) * 1000)
    let base = String(format: "%02d:%02d", ms / 60000, ms / 1000 % 60)
    return precise ? base + String(format: ".%03d", ms % 1000) : base
}

struct StudioView: View {
    @ObservedObject var studio: Studio
    @State private var mode = PadInput.trackpad

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    capture
                    Divider()
                    TimelinePane(studio: studio)
                        .frame(minHeight: 180, idealHeight: 240, maxHeight: 285)
                }
                Divider()
                InspectorPane(studio: studio)
                    .frame(width: 238)
                    .background(Ink.panel)
            }
            Divider()
            transport
            Divider()
            HStack(spacing: 8) {
                Circle().fill(studio.isRecording ? Ink.coral : Ink.mint).frame(width: 6, height: 6)
                Text(studio.status).lineLimit(1).truncationMode(.middle).help(studio.status)
                Spacer()
                Text("RPE  /  PEZ").font(Ink.mono)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 18).frame(height: 26)
        }
        .background(Ink.studio)
        .preferredColorScheme(.dark)
        .tint(Ink.mint)
        .frame(minWidth: 900, minHeight: 620)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(Ink.mint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("TouchBridge Studio").font(.system(size: 17, weight: .semibold))
                HStack(spacing: 5) {
                    Text(studio.projectName).lineLimit(1)
                    if studio.dirty { Circle().frame(width: 5, height: 5).accessibilityLabel("未保存") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ToolIcon("新建工程", "doc.badge.plus", action: studio.newProject)
            ToolIcon("打开工程", "folder", action: studio.openProject)
            ToolIcon("保存工程", "square.and.arrow.down", action: studio.saveProject)
            Divider().frame(height: 18)
            Button(action: studio.exportPEZ) { Label("导出 PEZ", systemImage: "square.and.arrow.up") }
                .disabled(!studio.hasAudio || studio.project.notes.isEmpty || studio.isRecording)
        }
        .padding(.horizontal, 18).frame(height: 60).background(Ink.panel)
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("演奏区", systemImage: "hand.point.up.left")
                    .font(.headline)
                Spacer()
                Picker("输入设备", selection: $mode) {
                    ForEach(PadInput.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 125)
                .disabled(studio.isRecording)
            }
            ZStack {
                PadGrid(points: studio.activeTouches)
                if studio.activeTouches.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: mode == .trackpad ? "hand.tap" : "computermouse")
                            .font(.system(size: 24, weight: .light))
                        Text(mode == .trackpad ? "触控板输入" : "鼠标输入").font(.caption)
                    }.foregroundStyle(.secondary).allowsHitTesting(false)
                }
                PadView(studio: studio, mode: mode)
                    .help(mode == .trackpad ? "将指针停在此区域，抬起手指后重新触碰触控板。" : "在此区域点击、按住或拖动鼠标。")
            }
            .background(Ink.pad).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(studio.isRecording ? Ink.coral : Ink.line) }
            HStack {
                Circle().fill(studio.isRecording ? Ink.coral : Ink.mint).frame(width: 6, height: 6)
                Text(studio.isRecording ? "正在录制" : "输入监看")
                Spacer()
                Text("\(studio.activeTouches.count) 个触点").monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transport: some View {
        HStack(spacing: 12) {
            ToolIcon("回到开头", "backward.end.fill") { studio.seek(0) }
                .disabled(studio.isRecording || !studio.hasAudio)
            ToolIcon(studio.isPlaying ? "暂停" : "播放", studio.isPlaying ? "pause.fill" : "play.fill", action: studio.togglePlayback)
                .disabled(!studio.hasAudio || studio.isRecording)
            Button(action: studio.toggleRecording) {
                Label(studio.isRecording ? "停止录制" : "录制", systemImage: studio.isRecording ? "stop.fill" : "record.circle")
                    .frame(minWidth: 60)
            }
            .buttonStyle(RecordButtonStyle())
            .disabled(!studio.hasAudio)
            Divider().frame(height: 22)
            Text(clockText(studio.currentTime, precise: true))
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .accessibilityLabel("播放时间 \(clockText(studio.currentTime, precise: true))")
            Text("/ " + clockText(studio.duration)).font(Ink.mono).foregroundStyle(.secondary)
            Slider(value: Binding(get: { max(0, min(studio.currentTime, studio.duration)) }, set: studio.seek),
                   in: 0...max(0.001, studio.duration))
                .accessibilityLabel("播放进度").disabled(!studio.hasAudio || studio.isRecording)
            ToolIcon("撤销", "arrow.uturn.backward", action: studio.undo).disabled(!studio.canUndo || studio.isRecording)
            ToolIcon("重做", "arrow.uturn.forward", action: studio.redo).disabled(!studio.canRedo || studio.isRecording)
        }
        .padding(.horizontal, 18).frame(height: 58).background(Ink.panel)
    }
}

private struct RecordButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout.weight(.semibold))
            .padding(.horizontal, 8).frame(height: 28)
            .foregroundStyle(isEnabled ? .black : .secondary)
            .background(isEnabled ? Ink.coral.opacity(configuration.isPressed ? 0.75 : 1) : .white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct ToolIcon: View {
    let name: String, symbol: String
    let action: () -> Void
    init(_ name: String, _ symbol: String, action: @escaping () -> Void) {
        self.name = name; self.symbol = symbol; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).foregroundStyle(.primary).help(name).accessibilityLabel(name)
    }
}

private struct PadGrid: View {
    let points: [Int: CGPoint]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var grid = Path()
            for col in 1..<8 { let x = w * CGFloat(col)/8; grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: h)) }
            for row in 1..<4 { let y = h * CGFloat(row)/4; grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: w, y: y)) }
            ctx.stroke(grid, with: .color(.white.opacity(0.075)), style: .init(lineWidth: 1, dash: [3, 4]))
            for (id, touch) in points {
                let p = CGPoint(x: min(w - 3, max(3, touch.x * w)), y: min(h - 3, max(3, (1 - touch.y) * h)))
                let ring = Path(ellipseIn: CGRect(x: p.x-15, y: p.y-15, width: 30, height: 30))
                ctx.fill(ring, with: .color(Ink.mint.opacity(0.22)))
                ctx.stroke(ring, with: .color(Ink.mint), lineWidth: 1.5)
                ctx.draw(Text(String(id)).font(Ink.mono).foregroundStyle(Ink.mint), at: p)
            }
        }.accessibilityHidden(true)
    }
}

private struct TimelinePane: View {
    @ObservedObject var studio: Studio
    @State private var bars = 4

    private var beat: Double { 60 / max(1, min(1_000, studio.project.bpm)) }
    private var span: Double {
        bars == 0 ? max(beat * 4, max(studio.duration, studio.project.notes.map { $0.start + $0.duration }.max() ?? 0)) : beat * Double(4 * bars)
    }
    var body: some View {
        let span = self.span
        let left = bars == 0 ? 0 : floor(min(studio.currentTime, max(0, studio.duration - 0.001)) / span) * span
        let beat = self.beat
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("谱面时间线", systemImage: "pianokeys").font(.headline)
                Text(studio.project.notes.count.formatted()).font(Ink.mono).foregroundStyle(.secondary)
                Spacer()
                Picker("时间线范围", selection: $bars) {
                    Text("2 小节").tag(2); Text("4 小节").tag(4); Text("8 小节").tag(8); Text("全曲").tag(0)
                }.labelsHidden().frame(width: 88)
                ToolIcon("在播放头添加 Tap", "plus") { studio.addNote(at: studio.currentTime, x: 0.5) }
                    .disabled(!studio.hasAudio || studio.isRecording)
            }
            GeometryReader { geo in
                Canvas { ctx, size in
                    let strideBeats = max(1, ceil(span / beat / max(1, size.width / 24)))
                    let step = strideBeats * beat
                    let first = ceil(left / step - 0.0000001)
                    for i in 0...Int(ceil(span / step) + 1) {
                        let t = (first + Double(i)) * step
                        let x = (t - left) / span * size.width
                        guard x >= -0.001, x < size.width else { continue }
                        let major = (Int(round(t / beat)) % 4 == 0) || strideBeats > 1
                        var line = Path()
                        line.move(to: .init(x: x, y: 17)); line.addLine(to: .init(x: x, y: size.height))
                        ctx.stroke(line, with: .color(.white.opacity(major ? 0.20 : 0.075)), lineWidth: 1)
                        if major, (strideBeats == 1 || i % 3 == 0) {
                            ctx.draw(Text(clockText(t)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary),
                                     at: .init(x: x + 3, y: 7), anchor: .leading)
                        }
                    }
                    for i in 0...2 {
                        let y = ordinate(Double(i) / 2, height: size.height)
                        var line = Path(); line.move(to: .init(x: 0, y: y)); line.addLine(to: .init(x: size.width, y: y))
                        ctx.stroke(line, with: .color(.white.opacity(0.075)), lineWidth: 1)
                    }
                    for note in studio.project.notes where note.start <= left + span && note.start + note.duration >= left {
                        let x = (note.start - left) / span * size.width
                        let y = ordinate(note.x, height: size.height)
                        let end = (note.start + note.duration - left) / span * size.width
                        let rect = CGRect(x: max(-4, x-3), y: y-3.5, width: max(6, min(size.width+3, end+3)-max(-4, x-3)), height: 7)
                        let mark = Path(roundedRect: rect, cornerRadius: 2)
                        ctx.fill(mark, with: .color(note.kind.tint))
                        if note.id == studio.selected {
                            ctx.stroke(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 3),
                                       with: .color(.white), lineWidth: 1)
                        }
                    }
                    let x = (studio.currentTime - left) / span * size.width
                    var needle = Path(); needle.move(to: .init(x: x, y: 0)); needle.addLine(to: .init(x: x, y: size.height))
                    ctx.stroke(needle, with: .color(Ink.mint), lineWidth: 1.5)
                    var tip = Path(); tip.move(to: .init(x: x - 4, y: 0)); tip.addLine(to: .init(x: x + 4, y: 0)); tip.addLine(to: .init(x: x, y: 6)); tip.closeSubpath()
                    ctx.fill(tip, with: .color(Ink.mint))
                }
                .background(Ink.pad).clipped()
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    guard !studio.isRecording else { return }
                    let p = tap.location, w = max(geo.size.width, 1)
                    let t = left + span * p.x / w
                    let nearest = studio.project.notes.compactMap { note -> (ChartNote, Double)? in
                        let horizontal = max(0, max(note.start-t, t-note.start-note.duration)) / span * w
                        let d = hypot(horizontal, ordinate(note.x, height: geo.size.height) - p.y)
                        return d <= 12 ? (note, d) : nil
                    }.min { $0.1 < $1.1 }?.0
                    studio.selected = nearest?.id
                    if studio.hasAudio { studio.seek(nearest?.start ?? min(studio.duration, max(0, t))) }
                })
                .accessibilityElement().accessibilityLabel("谱面时间线，\(studio.project.notes.count) 个音符")
                .help("点击音符以编辑；点击空白处移动播放头。")
            }
            HStack(spacing: 14) {
                ForEach(NoteKind.allCases, id: \.self) { kind in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(kind.tint).frame(width: 9, height: 4)
                        Text(kind.label).font(Ink.mono)
                    }
                }
            }.foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }
    private func ordinate(_ x: Double, height: CGFloat) -> CGFloat {
        24 + (1-x) * max(1, height-32)
    }
}

private struct InspectorPane: View {
    @ObservedObject var studio: Studio
    private var note: ChartNote? { studio.project.notes.first { $0.id == studio.selected } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("工程", systemImage: "slider.horizontal.3").font(.headline)
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(Ink.mint)
                    Text(studio.hasAudio ? studio.audioName : "未载入音频")
                        .font(.callout).lineLimit(1).truncationMode(.middle).help(studio.audioName)
                    Spacer(minLength: 1)
                    ToolIcon("导入音频", "folder.badge.plus", action: studio.importAudio)
                        .disabled(studio.isRecording)
                }
                if !studio.hasAudio {
                    Button("导入音频…", action: studio.importAudio).frame(maxWidth: .infinity, alignment: .leading)
                }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 7) {
                    metadataRow("曲名", \.title)
                    metadataRow("作曲", \.composer)
                    metadataRow("谱师", \.charter)
                    metadataRow("难度", \.difficulty)
                    GridRow {
                        Text("BPM").foregroundStyle(.secondary)
                        CommitField(display(studio.project.bpm), label: "BPM") { text in
                            if let v = Double(text), v.isFinite, v > 0 { studio.updateMetadata { $0.bpm = v } }
                        }
                    }
                    GridRow {
                        Text("吸附").foregroundStyle(.secondary)
                        Picker("每拍细分", selection: $studio.subdivision) {
                            Text("关闭").tag(0)
                            ForEach([1, 2, 3, 4, 8], id: \.self) { Text("每拍 \($0) 格").tag($0) }
                        }.labelsHidden()
                    }
                }.disabled(studio.isRecording)
                Divider()
                HStack {
                    Label("音符", systemImage: "music.note").font(.headline)
                    Spacer()
                    ToolIcon("上一个音符", "chevron.left") { adjacent(-1) }.disabled(studio.project.notes.isEmpty || studio.isRecording)
                    ToolIcon("下一个音符", "chevron.right") { adjacent(1) }.disabled(studio.project.notes.isEmpty || studio.isRecording)
                    ToolIcon("删除音符", "trash", action: studio.deleteSelected).disabled(note == nil || studio.isRecording)
                }
                if let note {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 7) {
                        GridRow {
                            Text("类型").foregroundStyle(.secondary)
                            Picker("音符类型", selection: Binding(get: { note.kind }, set: { next in
                                amend(note) { n in
                                    n.kind = next
                                    n.duration = next == .hold ? max(n.duration, 60 / max(1, studio.project.bpm)) : 0
                                }
                            })) {
                                ForEach(NoteKind.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.labelsHidden()
                        }
                        numberRow("时间", unit: "秒", value: note.start) { value in
                            amend(note) { $0.start = max(0, value) }
                        }
                        numberRow("横向", unit: "%", value: note.x * 100) { value in
                            amend(note) { $0.x = min(1, max(0, value / 100)) }
                        }
                        if note.kind == .hold {
                            numberRow("时长", unit: "秒", value: note.duration) { value in
                                if value > 0 { amend(note) { $0.duration = value } }
                            }
                        }
                    }.id(note.id).disabled(studio.isRecording)
                } else {
                    Text("未选择音符").font(.callout).foregroundStyle(.secondary)
                }
            }
            .font(.callout).padding(15).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataRow(_ name: String, _ key: WritableKeyPath<ChartProject, String>) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            CommitField(studio.project[keyPath: key], label: name) { text in
                studio.updateMetadata { $0[keyPath: key] = text }
            }
        }
    }
    private func numberRow(_ name: String, unit: String, value: Double, onCommit: @escaping (Double) -> Void) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                CommitField(display(value), label: name) { text in
                    if let v = Double(text), v.isFinite { onCommit(v) }
                }
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func display(_ v: Double) -> String {
        v.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...4)))
    }
    private func amend(_ original: ChartNote, change: (inout ChartNote) -> Void) {
        guard var n = studio.project.notes.first(where: { $0.id == original.id }) else { return }
        change(&n)
        studio.updateNote(n)
    }
    private func adjacent(_ offset: Int) {
        let sorted = studio.project.notes.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return }
        let pos = sorted.firstIndex { $0.id == studio.selected }
        let i = pos.map { ($0 + offset + sorted.count) % sorted.count } ?? (offset > 0 ? 0 : sorted.count - 1)
        studio.selected = sorted[i].id
        if studio.hasAudio { studio.seek(sorted[i].start) }
    }
}

private struct CommitField: View {
    let value: String, label: String
    let commit: (String) -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(_ value: String, label: String, commit: @escaping (String) -> Void) {
        self.value = value; self.label = label; self.commit = commit
        _draft = State(initialValue: value)
    }
    var body: some View {
        TextField(label, text: $draft).labelsHidden().accessibilityLabel(label).focused($focused)
            .onSubmit { focused = false }
            .onChange(of: focused) { _, now in
                if !now {
                    let submitted = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft = value
                    if submitted != value { commit(submitted) }
                }
            }
            .onChange(of: value) { _, newValue in draft = newValue }
    }
}
