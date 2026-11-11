import AppKit
import SwiftUI

/// Populate native font choices once, not thousands of SwiftUI menu views per keystroke.
struct FontSelector: NSViewRepresentable {
    @Binding var selection: String
    private static let fonts = NSFontManager.shared.availableFonts.sorted()
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox()
        combo.addItems(withObjectValues: Self.fonts)
        combo.numberOfVisibleItems = 16
        combo.completes = true
        combo.delegate = context.coordinator
        combo.stringValue = selection
        return combo
    }
    func updateNSView(_ combo: NSComboBox, context: Context) {
        context.coordinator.selection = $selection
        // Preserve the field editor and any marked IME text during unrelated updates.
        if combo.currentEditor() == nil && combo.stringValue != selection { combo.stringValue = selection }
        combo.isEnabled = context.environment.isEnabled
    }
    @MainActor
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox, let font = combo.objectValueOfSelectedItem as? String else { return }
            selection.wrappedValue = font
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox else { return }
            selection.wrappedValue = combo.stringValue
        }
    }
}
