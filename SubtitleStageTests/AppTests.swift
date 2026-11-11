import XCTest
import AppKit
@testable import SubtitleStage
import SubtitleCore

final class AppTests: XCTestCase {
    @MainActor
    func testStoreEditingAndLiveDeletionProtection() async {
        let store = ProjectStore()
        store.addCue()
        let id = store.selectedCue!.id
        var cue = store.selectedCue!
        cue.text = "繁體中文\nEnglish"; store.editCue(cue)
        store.go()
        cue.text = "Edited"; store.editCue(cue)
        XCTAssertEqual(store.playback.liveFrame?.cue.text, "Edited")
        store.deleteCue()
        XCTAssertEqual(store.project.cues.count, 1)
        XCTAssertNotNil(store.errorMessage)
        store.addCue(); store.moveCue(by: -1)
        XCTAssertEqual(store.project.cues.last?.id, id)
        store.deleteCue()
        XCTAssertEqual(store.project.cues.map(\.id), [id])
        XCTAssertTrue(store.isDirty)
    }

    @MainActor
    func testImportOnlyMutatesOnCommit() async {
        let store = ProjectStore()
        let items = ClipboardImporter.parse("第一句\nSecond", mode: .line)
        XCTAssertTrue(store.project.cues.isEmpty)
        store.importItems(items)
        XCTAssertEqual(store.project.cues.map(\.text), ["第一句", "Second"])
        XCTAssertEqual(Set(store.project.cues.map(\.id)).count, 2)
    }

    @MainActor
    func testPasteTargetsSurtitleAndInsertsBelowCursor() async {
        let store = ProjectStore()
        store.addCue(); let first = store.selectedCue!.id
        store.addCue(); let second = store.selectedCue!.id
        let secondary = store.addLanguage()
        store.playback.selectedCueID = first
        store.importItems(ClipboardImporter.parse("A\nB", mode: .line), to: secondary, after: first)
        XCTAssertEqual(store.project.cues.map(\.id).last, second)
        XCTAssertEqual(store.project.cues[1].translations[secondary], "A")
        XCTAssertEqual(store.project.cues[2].translations[secondary], "B")
        XCTAssertEqual(store.playback.selectedCueID, store.project.cues[1].id)
    }

    @MainActor
    func testReturnStyleInsertionAddsAfterCurrentCue() async {
        let store = ProjectStore()
        store.addCue(); let first = store.selectedCue!.id
        store.addCue(); let second = store.selectedCue!.id
        let inserted = store.addCue(after: first, focusing: store.project.languages[0].id)
        XCTAssertEqual(store.project.cues.map(\.id), [first, inserted, second])
        XCTAssertEqual(store.playback.selectedCueID, inserted)
    }

    @MainActor
    func testUndoRedoDeletionAndSelectedCueSequence() async {
        let store = ProjectStore()
        store.addCue(); let first = store.selectedCue!.id
        store.addCue(); let second = store.selectedCue!.id
        store.addCue(); let third = store.selectedCue!.id
        store.playback.selectedCueID = second
        store.moveCue(by: -1)
        XCTAssertEqual(store.project.cues.map(\.id), [second, first, third])
        store.undo()
        XCTAssertEqual(store.project.cues.map(\.id), [first, second, third])
        XCTAssertEqual(store.playback.selectedCueID, second)
        store.redo()
        XCTAssertEqual(store.project.cues.map(\.id), [second, first, third])
        store.deleteCue()
        XCTAssertEqual(store.project.cues.map(\.id), [first, third])
        store.undo()
        XCTAssertEqual(store.project.cues.map(\.id), [second, first, third])
        XCTAssertEqual(store.playback.selectedCueID, second)
    }

    @MainActor
    func testUndoHistoryIsLimitedToOneHundredChanges() async {
        let store = ProjectStore()
        for _ in 0..<105 { store.addCue() }
        for _ in 0..<105 { store.undo() }
        XCTAssertEqual(store.project.cues.count, 5)
        XCTAssertFalse(store.canUndo)
        XCTAssertTrue(store.canRedo)
    }

    @MainActor
    func testContinuousCellTypingIsOneUndoStep() async {
        let store = ProjectStore()
        store.addCue()
        let cueID = store.selectedCue!.id
        let languageID = store.project.languages[0].id
        store.setText("字", cueID: cueID, languageID: languageID)
        store.setText("字幕", cueID: cueID, languageID: languageID)
        store.setText("字幕內容", cueID: cueID, languageID: languageID)
        store.endHistoryGroup()
        store.undo()
        XCTAssertEqual(store.project.text(for: store.selectedCue!, languageID: languageID), "")
        store.redo()
        XCTAssertEqual(store.project.text(for: store.selectedCue!, languageID: languageID), "字幕內容")
    }

    @MainActor
    func testCueFadeOutThenFadeInNavigationAndBoundary() async throws {
        let store = ProjectStore()
        store.addCue(); let first = store.selectedCue!.id
        store.addCue(); let second = store.selectedCue!.id
        store.editCueTransition(first) { $0.fadeOutEnabled = true; $0.fadeOutDuration = 0.02 }
        store.editCueTransition(second) { $0.fadeInEnabled = true; $0.fadeInDuration = 0.02 }
        store.playback.selectedCueID = first
        store.go()
        store.go()
        XCTAssertTrue(store.isCueTransitioning)
        XCTAssertEqual(store.playback.liveCueID, first)
        XCTAssertEqual(store.playback.visibleOpacity, 0)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(store.isCueTransitioning)
        XCTAssertEqual(store.playback.liveCueID, second)
        XCTAssertEqual(store.playback.visibleOpacity, 1)
        store.go()
        XCTAssertEqual(store.playback.liveCueID, second)
        XCTAssertFalse(store.isCueTransitioning)
    }

    @MainActor
    func testNativeRendererAndBlackout() async throws {
        var project = Project()
        project.canvases[0] = CanvasDefinition(width: 2688, height: 768)
        project.cues = [Cue(displayNumber: "1", text: "繁體中文 · 简体中文\nEnglish · 日本語 · 한국어")]
        var playback = PlaybackState(); playback.go(in: project)
        let view = CanvasDrawingView(frame: NSRect(x: 0, y: 0, width: 896, height: 256))
        view.canvas = project.canvas; view.frameData = playback.liveFrame
        func render() throws -> NSBitmapImageRep {
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 896, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
            context.cgContext.translateBy(x: 0, y: 256)
            context.cgContext.scaleBy(x: 1, y: -1)
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        func litPixels(_ rep: NSBitmapImageRep) -> Int {
            var count = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    if let color = rep.colorAt(x: x, y: y), color.redComponent > 0.1 { count += 1 }
                }
            }
            return count
        }
        let normal = try render()
        XCTAssertGreaterThan(litPixels(normal), 100)
        let png = try XCTUnwrap(normal.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("SubtitleStage-render-smoke.png"))
        view.blackout = true
        XCTAssertEqual(litPixels(try render()), 0)
        // Distinct routed frames must actually produce distinct pixels.
        let a = OutputConfiguration(displayID: 1, canvasID: project.canvas.id)
        let b = OutputConfiguration(displayID: 2, canvasID: project.canvas.id)
        project.outputs = [a, b]
        project.languages[0].frame = PixelFrame(x: 100, y: 100, width: 2200, height: 200)
        project.languages[0].outputIDs = [a.id]
        var english = LanguageLayer(name: "English", frame: PixelFrame(x: 100, y: 450, width: 2200, height: 200))
        english.outputIDs = [b.id]
        project.languages.append(english)
        project.cues[0].translations[english.id] = "Separate output"
        view.frameData = LiveFrame(cue: project.cues[0], project: project)
        view.blackout = false
        view.outputID = a.id
        let pixelsA = litPixels(try render())
        view.outputID = b.id
        let pixelsB = litPixels(try render())
        view.outputID = nil
        XCTAssertGreaterThan(pixelsA, 100)
        XCTAssertGreaterThan(pixelsB, 100)
        XCTAssertEqual(litPixels(try render()), pixelsA + pixelsB)
        view.outputID = UUID()
        XCTAssertEqual(litPixels(try render()), 0)
        var decoration = TextStylePatch()
        decoration.color = TextColor(red: 1, green: 0, blue: 0)
        decoration.italic = true; decoration.underline = true; decoration.strikethrough = true
        project.cues[0].styleOverrides[project.languages[0].id] = decoration
        view.frameData = LiveFrame(cue: project.cues[0], project: project)
        view.outputID = a.id
        let colored = try render()
        XCTAssertGreaterThan(litPixels(colored), 100)
        var greenPixels = 0
        for y in 0..<colored.pixelsHigh {
            for x in 0..<colored.pixelsWide {
                if let color = colored.colorAt(x: x, y: y), color.greenComponent > 0.1 { greenPixels += 1 }
            }
        }
        XCTAssertEqual(greenPixels, 0, "Per-cell color must reach the output renderer")
        let unrotatedData = try XCTUnwrap(colored.representation(using: .png, properties: [:]))
        project.languages[0].rotation = Rotation3D(x: 12, y: 8, z: 15)
        view.frameData = LiveFrame(cue: project.cues[0], project: project)
        let rotated = try render()
        XCTAssertNotEqual(rotated.representation(using: .png, properties: [:]), unrotatedData)
        view.setContentOpacity(0, duration: 0)
        XCTAssertEqual(litPixels(try render()), 0)
        view.setContentOpacity(1, duration: 0)
        XCTAssertGreaterThan(litPixels(try render()), 100)
    }
}
