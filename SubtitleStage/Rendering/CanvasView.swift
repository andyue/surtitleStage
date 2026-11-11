import AppKit
import SwiftUI
import SubtitleCore

struct CanvasView: NSViewRepresentable {
    let frame: LiveFrame?
    let canvas: CanvasDefinition
    let blackout: Bool
    var outputID: UUID? = nil
    var physicalOutput = false
    var applyMapping = true
    var previewResolution: PixelSize? = nil
    var opacity: Double = 1
    var transitionDuration: Double = 0
    func makeNSView(context: Context) -> CanvasDrawingView { CanvasDrawingView() }
    func updateNSView(_ view: CanvasDrawingView, context: Context) {
        let needsContentUpdate = view.frameData != frame || view.canvas != canvas || view.blackout != blackout || view.outputID != outputID || view.physicalOutput != physicalOutput || view.applyMapping != applyMapping || view.previewResolution != previewResolution
        view.frameData = frame; view.canvas = canvas; view.blackout = blackout; view.outputID = outputID
        view.physicalOutput = physicalOutput; view.applyMapping = applyMapping; view.previewResolution = previewResolution
        if needsContentUpdate { view.needsDisplay = true }
        view.setContentOpacity(blackout ? 0 : opacity, duration: transitionDuration)
    }
}

final class CanvasDrawingView: NSView {
    var frameData: LiveFrame?
    var canvas = CanvasDefinition()
    var blackout = false
    var outputID: UUID?
    var physicalOutput = false
    var applyMapping = true
    var previewResolution: PixelSize? = nil
    private(set) var contentOpacity: Double = 1
    private var fadeTimer: Timer?
    private var fadeStartOpacity = 1.0
    private var fadeTargetOpacity = 1.0
    private var fadeStartTime = 0.0
    private var fadeDuration = 0.0
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard !blackout, contentOpacity > 0, let frameData,
              let context = NSGraphicsContext.current?.cgContext else { return }
        CanvasContentRenderer.draw(frameData, canvas: canvas, outputID: outputID,
                                   applyMapping: applyMapping, physicalOutput: physicalOutput,
                                   previewResolution: previewResolution, bounds: bounds,
                                   backingBounds: convertToBacking(bounds), contentOpacity: contentOpacity, context: context)
    }
    func setContentOpacity(_ target: Double, duration: Double) {
        let target = min(1, max(0, target))
        guard target != contentOpacity else { return }
        fadeTimer?.invalidate()
        guard duration > 0, window != nil else {
            contentOpacity = target; needsDisplay = true; return
        }
        fadeStartOpacity = contentOpacity
        fadeTargetOpacity = target
        fadeStartTime = ProcessInfo.processInfo.systemUptime
        fadeDuration = duration
        fadeTimer = Timer(timeInterval: 1.0 / 60.0, target: self,
                          selector: #selector(advanceFade), userInfo: nil, repeats: true)
        RunLoop.main.add(fadeTimer!, forMode: .common)
    }
    @objc private func advanceFade() {
        let elapsed = ProcessInfo.processInfo.systemUptime - fadeStartTime
        let progress = min(1, elapsed / fadeDuration)
        contentOpacity = fadeStartOpacity + (fadeTargetOpacity - fadeStartOpacity) * progress
        needsDisplay = true
        if progress >= 1 { fadeTimer?.invalidate(); fadeTimer = nil }
    }
}
