import AppKit
import SwiftUI

/// Background marker: does not intercept controls or text input. The window bridge
/// arms it only after a mouse click inside this region has finished dispatching.
struct ShowControlsFocus: NSViewRepresentable {
    @ObservedObject var store: ProjectStore
    func makeNSView(context: Context) -> ShowControlsFocusView {
        let view = ShowControlsFocusView()
        view.changed = { [weak store] focused in store?.showControlsFocused = focused }
        return view
    }
    func updateNSView(_ nsView: ShowControlsFocusView, context: Context) {}
}

final class ShowControlsFocusView: NSView {
    var changed: ((Bool) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func becomeFirstResponder() -> Bool { changed?(true); return true }
    override func resignFirstResponder() -> Bool { changed?(false); return true }
    override func keyDown(with event: NSEvent) { /* Unassigned keys never activate a focused button. */ }
}
