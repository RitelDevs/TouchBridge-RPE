import AppKit
import SwiftUI

enum PadInput: String, CaseIterable, Identifiable {
    case trackpad = "触控板"
    case mouse = "鼠标"
    var id: Self { self }
}

struct PadView: NSViewRepresentable {
    let studio: Studio
    var mode: PadInput

    func makeNSView(context: Context) -> ContactSurface {
        let view = ContactSurface()
        view.studio = studio
        view.mode = mode
        return view
    }

    func updateNSView(_ view: ContactSurface, context: Context) {
        view.studio = studio
        view.mode = mode
    }
}

final class ContactSurface: NSView {
    weak var studio: Studio?
    var mode: PadInput = .trackpad {
        didSet {
            guard oldValue != mode else { return }
            resetContacts()
            allowedTouchTypes = mode == .trackpad ? [.indirect] : []
        }
    }
    private var fingers: [(identity: any NSObjectProtocol, id: Int)] = []
    private var nextID = 1
    private var mouseIsDown = false

    init() {
        super.init(frame: .zero)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("录制输入区")
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            resetContacts()
        }
        if let newWindow {
            NotificationCenter.default.addObserver(self, selector: #selector(lostFocus),
                name: NSWindow.didResignKeyNotification, object: newWindow)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc private func lostFocus() { resetContacts() }

    private func resetContacts() {
        if !fingers.isEmpty || mouseIsDown { studio?.cancelTouches() }
        fingers.removeAll()
        mouseIsDown = false
    }

    // NSTouch instances change between frames. Compare the opaque identities by equality.
    private func index(of touch: NSTouch) -> Int? {
        fingers.firstIndex { $0.identity.isEqual(touch.identity) }
    }

    override func touchesBegan(with event: NSEvent) {
        guard mode == .trackpad else { return }
        for touch in event.touches(matching: .began, in: self) where index(of: touch) == nil {
            let id = nextID
            nextID = nextID == Int.max ? 1 : nextID + 1
            fingers.append((touch.identity, id))
            studio?.touchBegan(id, touch.normalizedPosition, event.timestamp)
        }
    }

    override func touchesMoved(with event: NSEvent) {
        guard mode == .trackpad else { return }
        for touch in event.touches(matching: .moved, in: self) {
            guard let index = index(of: touch) else { continue }
            studio?.touchMoved(fingers[index].id, touch.normalizedPosition, event.timestamp)
        }
    }

    override func touchesEnded(with event: NSEvent) {
        guard mode == .trackpad else { return }
        for touch in event.touches(matching: .ended, in: self) {
            guard let index = index(of: touch) else { continue }
            studio?.touchEnded(fingers.remove(at: index).id, touch.normalizedPosition, event.timestamp)
        }
    }

    override func touchesCancelled(with event: NSEvent) { resetContacts() }

    private func position(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: max(0, min(1, local.x / max(1, bounds.width))),
                       y: max(0, min(1, local.y / max(1, bounds.height))))
    }

    // Explicit input modes prevent a tap-to-click from being counted twice.
    override func mouseDown(with event: NSEvent) {
        guard mode == .mouse, !mouseIsDown else { return }
        mouseIsDown = true
        studio?.touchBegan(0, position(event), event.timestamp)
    }
    override func mouseDragged(with event: NSEvent) {
        guard mouseIsDown else { return }
        studio?.touchMoved(0, position(event), event.timestamp)
    }
    override func mouseUp(with event: NSEvent) {
        guard mouseIsDown else { return }
        mouseIsDown = false
        studio?.touchEnded(0, position(event), event.timestamp)
    }
}
