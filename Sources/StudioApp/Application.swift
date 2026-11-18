import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum TouchBridgeApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let studio = Studio()
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
    private var updates: AnyCancellable?
    private var keys: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = NSHostingView(rootView: StudioView(studio: studio))
        window.contentView = view
        window.title = "TouchBridge Studio"
        window.contentMinSize = NSSize(width: 900, height: 620)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.center(); window.setFrameAutosaveName("StudioEditor")
        installMenus()
        updates = studio.$dirty.sink { [weak self] in self?.window.isDocumentEdited = $0 }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, !(self.window.firstResponder is NSTextView),
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }
            switch event.keyCode {
            case 49: if !event.isARepeat { self.studio.togglePlayback() }; return nil
            case 15: if !event.isARepeat { self.studio.toggleRecording() }; return nil
            case 51, 117: self.studio.deleteSelected(); return nil
            default: return event
            }
        }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { studio.openURL(url); window.makeKeyAndOrderFront(nil) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil); return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        studio.stop(); return studio.permitDiscard() ? .terminateNow : .terminateCancel
    }
    func windowDidResignKey(_ notification: Notification) {
        if studio.isRecording { studio.stop() }
    }
    @objc private func newDoc() { studio.newProject() }
    @objc private func openDoc() { studio.openProject() }
    @objc private func saveDoc() { studio.saveProject() }
    @objc private func importSong() { studio.importAudio() }
    @objc private func exportChart() { studio.exportPEZ() }
    @objc private func play() { studio.togglePlayback() }
    @objc private func record() { studio.toggleRecording() }
    @objc private func undoEdit() {
        if let view = window.firstResponder as? NSTextView, let undo = view.undoManager { undo.undo() }
        else { studio.undo() }
    }
    @objc private func redoEdit() {
        if let view = window.firstResponder as? NSTextView, let undo = view.undoManager { undo.redo() }
        else { studio.redo() }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoEdit): return (window.firstResponder as? NSTextView)?.undoManager?.canUndo ?? studio.canUndo
        case #selector(redoEdit): return (window.firstResponder as? NSTextView)?.undoManager?.canRedo ?? studio.canRedo
        case #selector(exportChart): return studio.hasAudio && !studio.project.notes.isEmpty && !studio.isRecording
        case #selector(play), #selector(record): return studio.hasAudio
        default: return true
        }
    }
    private func installMenus() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); main.addItem(item); let menu = NSMenu(title: title)
            item.submenu = menu; return menu
        }
        func action(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String = "",
                    shift: Bool = false, target: AnyObject? = nil) {
            let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            item.target = target
        }
        let app = submenu("TouchBridge Studio")
        action(app, "关于 TouchBridge Studio", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        app.addItem(.separator())
        action(app, "隐藏 TouchBridge Studio", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        action(app, "退出 TouchBridge Studio", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = submenu("文件")
        action(file, "新建工程", #selector(newDoc), "n", target: self)
        action(file, "打开工程…", #selector(openDoc), "o", target: self)
        action(file, "保存工程", #selector(saveDoc), "s", target: self)
        file.addItem(.separator())
        action(file, "导入音乐…", #selector(importSong), "i", target: self)
        action(file, "导出 PEZ…", #selector(exportChart), "e", target: self)
        action(file, "关闭窗口", #selector(NSWindow.performClose(_:)), "w")
        let edit = submenu("编辑")
        action(edit, "撤销", #selector(undoEdit), "z", target: self)
        action(edit, "重做", #selector(redoEdit), "z", shift: true, target: self)
        edit.addItem(.separator())
        action(edit, "剪切", #selector(NSText.cut(_:)), "x")
        action(edit, "拷贝", #selector(NSText.copy(_:)), "c")
        action(edit, "粘贴", #selector(NSText.paste(_:)), "v")
        action(edit, "全选", #selector(NSText.selectAll(_:)), "a")
        let transport = submenu("播放")
        action(transport, "播放 / 暂停", #selector(play), target: self)
        action(transport, "开始 / 停止录制", #selector(record), target: self)
        NSApp.mainMenu = main
    }
}
