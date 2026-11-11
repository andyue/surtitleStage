import XCTest
import AppKit
import SubtitleCore
@testable import SubtitleStage

final class MappingTests: XCTestCase {
    func testScaleModesAndNonzeroSourceCrop() throws {
        let source = PixelFrame(x: 200, y: 50, width: 400, height: 100)
        let dest = PixelFrame(x: 600, y: 300, width: 200, height: 200)
        let fit = try XCTUnwrap(RegionTransform(source: source, destination: dest, mode: .fit))
        XCTAssertEqual(fit.scaleX, 0.5); XCTAssertEqual(fit.scaleY, 0.5)
        XCTAssertEqual(fit.map(x: 200, y: 50).x, 600)
        XCTAssertEqual(fit.map(x: 200, y: 50).y, 375)
        let fill = try XCTUnwrap(RegionTransform(source: source, destination: dest, mode: .fill))
        XCTAssertEqual(fill.scaleX, 2); XCTAssertEqual(fill.map(x: 200, y: 50).x, 300)
        let stretch = try XCTUnwrap(RegionTransform(source: source, destination: dest, mode: .stretch))
        XCTAssertEqual(stretch.scaleX, 0.5); XCTAssertEqual(stretch.scaleY, 2)
        let pixel = try XCTUnwrap(RegionTransform(source: source, destination: dest, mode: .pixel))
        XCTAssertEqual(pixel.scaleX, 1); XCTAssertEqual(pixel.scaleY, 1)
        XCTAssertEqual(pixel.map(x: 201, y: 51).x, 601); XCTAssertEqual(pixel.map(x: 201, y: 51).y, 301)
        XCTAssertNil(RegionTransform(source: PixelFrame(x: 0, y: 0, width: 0, height: 10), destination: dest, mode: .fit))
    }

    func testArbitraryCanvasAndPreviewConversion() throws {
        for (w, h) in [(5760.0,1080.0), (2688,768), (2560,960), (4096,2160), (700,2000)] {
            var project = Project(); project.canvases[0].width = w; project.canvases[0].height = h
            try project.validate()
            let transform = try XCTUnwrap(CanvasTransform(canvas: project.canvas, viewportWidth: 800, viewportHeight: 500))
            let p = transform.toPreview(x: w - 1, y: h - 1)
            let restored = transform.toCanvas(x: p.x, y: p.y)
            XCTAssertEqual(restored.x, w - 1, accuracy: 1e-8); XCTAssertEqual(restored.y, h - 1, accuracy: 1e-8)
        }
    }

    func testMigrationFromSevenPreservesProductionAndFit() throws {
        var project = Project()
        project.cues = [Cue(displayNumber: "A", name: "Scene", note: "筆記", text: "字幕")]
        var config = OutputConfiguration(name: "LED", displayID: 12, canvasID: project.canvas.id)
        config.languageLayouts[project.languages[0].id] = LanguagePlacement(project.languages[0])
        project.outputs = [config]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: ProjectCodec.encode(project)) as? [String: Any])
        json["projectFormatVersion"] = 7
        var outputs = try XCTUnwrap(json["outputs"] as? [[String: Any]])
        for key in ["resolution", "isEnabled", "scaleMode", "regions"] { outputs[0].removeValue(forKey: key) }
        json["outputs"] = outputs
        let loaded = try ProjectCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded, project)
        XCTAssertEqual(loaded.projectFormatVersion, 11)
        XCTAssertEqual(loaded.outputs[0].scaleMode, .fit)
        XCTAssertNil(loaded.outputs[0].resolution)
        XCTAssertEqual(loaded.cues[0].id, project.cues[0].id)
    }

    @MainActor
    func testRegionValidationUndoLiveRefreshAndResize() async throws {
        let store = ProjectStore(); store.addCue(); store.go()
        let out = store.addOutput()
        let id = try XCTUnwrap(store.addRegion(to: out))
        let original = store.project
        store.editRegion(id, outputID: out) { $0.source.x = 99999 }
        XCTAssertEqual(store.project, original); XCTAssertNotNil(store.errorMessage)
        store.editRegion(id, outputID: out) { $0.destination.width = 500; $0.scaleMode = .pixel }
        let mapped = store.project
        XCTAssertEqual(store.playback.liveFrame?.outputs, mapped.outputs)
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(mapped)), mapped)
        store.undo(); XCTAssertEqual(store.project, original)
        store.redo(); XCTAssertEqual(store.project, mapped)
        store.resizeCanvas(width: 5760, height: 1080)
        XCTAssertEqual(store.project.outputs[0].regions[0].source.width, 5760)
        XCTAssertEqual(store.project.outputs[0].regions[0].destination, mapped.outputs[0].regions[0].destination)
        XCTAssertEqual(store.project.outputs[0].regions[0].id, id)
        try store.project.validate()
        let before = store.project
        store.setOutputResolution(out, size: PixelSize(width: 100, height: 100))
        XCTAssertEqual(store.project, before, "Do not silently change regions when a signal shrinks")
        store.removeRegion(id, outputID: out); XCTAssertTrue(store.project.outputs[0].regions.isEmpty)
        store.undo(); XCTAssertEqual(store.project, before)
    }

    func testRejectsInvalidRegionsAndDeviceScaling() throws {
        var project = Project()
        var config = OutputConfiguration(canvasID: project.canvas.id)
        config.resolution = PixelSize(width: 1920, height: 1080)
        let source = PixelFrame(x: 0, y: 0, width: 1920, height: 1080)
        let region = OutputRegion(name: "A", sourceCanvasID: project.canvas.id, source: source, destination: source, scaleMode: .pixel)
        config.regions = [region]; project.outputs = [config]
        try project.validate()
        project.outputs[0].regions[0].sourceCanvasID = UUID()
        XCTAssertThrowsError(try project.validate())
        project.outputs = [config]; project.outputs[0].regions.append(region)
        XCTAssertThrowsError(try project.validate())
        project.outputs = [config]; project.outputs[0].regions[0].destination.x = 0.5
        XCTAssertThrowsError(try project.validate())
        project.outputs = [config]; project.outputs[0].regions[0].source.height = .nan
        XCTAssertThrowsError(try project.validate())
        project.outputs = [config]; project.outputs[0].resolution = nil
        XCTAssertThrowsError(try project.validate())
        let pixels = PixelSize(width: 1920, height: 1080)
        try config.validateDevice(backing: pixels, scanout: pixels)
        XCTAssertThrowsError(try config.validateDevice(backing: PixelSize(width: 3840, height: 2160), scanout: pixels))
        XCTAssertThrowsError(try config.validateDevice(backing: pixels, scanout: PixelSize(width: 3840, height: 2160)))
    }

    @MainActor
    func testMultipleOutputMappingsAndSecondaryCanvasAreIndependent() async throws {
        let store = ProjectStore(); store.addCue()
        let a = store.addOutput(displayID: 1), b = store.addOutput(displayID: 2)
        let ra = try XCTUnwrap(store.addRegion(to: a)), rb = try XCTUnwrap(store.addRegion(to: b))
        let originalB = store.project.outputs[1]
        store.editRegion(ra, outputID: a) { $0.destination.width = 500; $0.scaleMode = .stretch }
        XCTAssertEqual(store.project.outputs[1], originalB)
        XCTAssertNotEqual(ra, rb)
        let secondary = CanvasDefinition(width: 2688, height: 768)
        store.change { project in
            project.canvases.append(secondary)
            project.outputs[1].canvasID = secondary.id
            project.outputs[1].regions[0].sourceCanvasID = secondary.id
            project.outputs[1].regions[0].source = PixelFrame(x: 0, y: 0, width: 2688, height: 768)
        }
        store.go()
        XCTAssertEqual(store.canvas(for: b), secondary)
        XCTAssertEqual(store.playback.liveFrame?.canvases.count, 2)
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(store.project)), store.project)
    }

    @MainActor
    func testMappingUndoRequiresStopAndDragIsOneHistoryStep() async throws {
        let store = ProjectStore(); store.addCue(); store.go()
        let output = store.addOutput()
        let region = try XCTUnwrap(store.addRegion(to: output))
        store.editRegion(region, outputID: output, historyGroup: "gesture") { $0.destination.width = 1000 }
        store.editRegion(region, outputID: output, historyGroup: "gesture") { $0.destination.width = 900 }
        store.endHistoryGroup()
        let before = store.project
        store.undo(outputRunning: true)
        XCTAssertEqual(store.project, before)
        XCTAssertNotNil(store.errorMessage)
        store.undo()
        XCTAssertEqual(store.project.outputs[0].regions[0].destination.width, store.project.canvas.width)
        store.redo()
        XCTAssertEqual(store.project, before)
    }

    @MainActor
    func testOutputStartRejectsUnavailableDeviceWithoutChangingLive() async {
        let store = ProjectStore(); store.addCue(); store.addOutput(displayID: UInt32.max)
        let manager = OutputManager()
        manager.startConfigured(store: store)
        XCTAssertNil(store.playback.liveCueID)
        XCTAssertTrue(manager.activeDisplayIDs.isEmpty)
        XCTAssertNotNil(manager.status)
    }

    @MainActor
    func testRasterRegionsCropDestinationAndDisabledOutput() async throws {
        var project = Project()
        project.canvases[0].width = 200; project.canvases[0].height = 100
        project.languages[0].frame = PixelFrame(x: 0, y: 0, width: 200, height: 100)
        project.cues = [Cue(text: "MMMM")]; project.cues[0].style.fontSize = 30
        var config = OutputConfiguration(canvasID: project.canvas.id)
        config.resolution = PixelSize(width: 400, height: 100)
        let region = OutputRegion(name: "Right", sourceCanvasID: project.canvas.id,
                                  source: PixelFrame(x: 0, y: 0, width: 200, height: 100),
                                  destination: PixelFrame(x: 200, y: 0, width: 200, height: 100), scaleMode: .pixel)
        config.regions = [region]; project.outputs = [config]
        let view = CanvasDrawingView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.outputID = config.id
        func counts() throws -> (left: Int, right: Int) {
            view.frameData = LiveFrame(cue: project.cues[0], project: project)
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
            context.cgContext.translateBy(x: 0, y: 100); context.cgContext.scaleBy(x: 1, y: -1)
            view.draw(view.bounds)
            var left = 0, right = 0
            for y in 0..<100 { for x in 0..<400 {
                if let c = rep.colorAt(x: x, y: y), c.redComponent > 0.1 { if x < 200 { left += 1 } else { right += 1 } }
            } }
            return (left, right)
        }
        let one = try counts(); XCTAssertEqual(one.left, 0); XCTAssertGreaterThan(one.right, 100)
        var second = region; second.id = UUID(); second.destination.x = 0
        project.outputs[0].regions.append(second)
        let two = try counts(); XCTAssertEqual(two.left, two.right); XCTAssertEqual(two.right, one.right)
        project.outputs[0].regions[0].source.width = 1
        XCTAssertEqual(try counts().right, 0, "Source crop must exclude glyphs outside the crop")
        project.outputs[0].isEnabled = false
        let disabled = try counts(); XCTAssertEqual(disabled.left + disabled.right, 0)
    }
}
