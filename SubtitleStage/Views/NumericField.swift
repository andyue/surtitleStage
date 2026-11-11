import AppKit
import SwiftUI

struct NumericField: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    func makeCoordinator() -> Coordinator { Coordinator(value: $value, range: range, step: step) }
    func makeNSView(context: Context) -> ScrollNumericTextField {
        let field = ScrollNumericTextField()
        field.isBezeled = true; field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.stringValue = context.coordinator.format(value)
        field.onScroll = { [weak field, weak coordinator = context.coordinator] delta in
            coordinator?.adjust(delta > 0 ? 1 : -1, editor: field?.currentEditor() as? NSTextView)
        }
        return field
    }
    func updateNSView(_ field: ScrollNumericTextField, context: Context) {
        context.coordinator.value = $value; context.coordinator.range = range; context.coordinator.step = step
        if field.currentEditor() == nil { field.stringValue = context.coordinator.format(value) }
        field.isEnabled = context.environment.isEnabled
    }
    static func dismantleNSView(_ field: ScrollNumericTextField, coordinator: Coordinator) {
        coordinator.stopScrollMonitor()
    }
    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Binding<Double>
        var range: ClosedRange<Double>
        var step: Double
        private weak var activeField: NSTextField?
        private var scrollMonitor: Any?
        private let formatter: NumberFormatter = {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.usesGroupingSeparator = false; f.maximumFractionDigits = 2; return f
        }()
        init(value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1) { self.value = value; self.range = range; self.step = step }
        func format(_ value: Double) -> String { formatter.string(from: NSNumber(value: value)) ?? String(value) }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
                  let number = formatter.number(from: field.stringValue)?.doubleValue,
                  number.isFinite, range.contains(number) else { return }
            value.wrappedValue = number
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            activeField = field
            stopScrollMonitor()
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak field] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, let field, field.currentEditor() != nil,
                          event.window === field.window,
                          field.bounds.contains(field.convert(event.locationInWindow, from: nil)),
                          event.scrollingDeltaY != 0 else { return false }
                    self.adjust(event.scrollingDeltaY > 0 ? 1 : -1, editor: field.currentEditor() as? NSTextView)
                    return true
                }
                return consumed ? nil : event
            }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            field.stringValue = format(value.wrappedValue)
            stopScrollMonitor()
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            let delta: Double
            if selector == #selector(NSResponder.moveUp(_:)) { delta = 1 }
            else if selector == #selector(NSResponder.moveDown(_:)) { delta = -1 }
            else { return false }
            adjust(delta, editor: textView)
            return true
        }
        func adjust(_ direction: Double, editor: NSTextView?) {
            let number = min(range.upperBound, max(range.lowerBound, value.wrappedValue + direction * step))
            value.wrappedValue = number
            editor?.string = format(number)
            editor?.setSelectedRange(NSRange(location: 0, length: editor?.string.utf16.count ?? 0))
        }
        func stopScrollMonitor() {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
            activeField = nil
        }
    }
}

final class ScrollNumericTextField: NSTextField {
    var onScroll: ((CGFloat) -> Void)?
    override func scrollWheel(with event: NSEvent) {
        guard currentEditor() != nil, event.scrollingDeltaY != 0 else { super.scrollWheel(with: event); return }
        onScroll?(event.scrollingDeltaY)
    }
}
