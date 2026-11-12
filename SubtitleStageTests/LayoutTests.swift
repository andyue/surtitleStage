import XCTest
import Foundation
import SubtitleCore
@testable import SubtitleStage

final class LayoutTests: XCTestCase {
    @MainActor
    func testCanvasResizeScalesAllLayoutPixels() async {
        let store = ProjectStore()
        let languageID = store.project.languages[0].id
        let outputID = store.addOutput()
        store.setLanguageFrame(languageID, frame: PixelFrame(x: 100, y: 200, width: 800, height: 100), outputID: outputID)
        let originalCanvas = store.project.canvas
        store.resizeCanvas(width: originalCanvas.width * 2, height: originalCanvas.height * 2)
        XCTAssertEqual(store.project.canvas.width, originalCanvas.width * 2)
        XCTAssertEqual(store.layoutLanguage(languageID, outputID: outputID)?.frame, PixelFrame(x: 200, y: 400, width: 1600, height: 200))
        store.undo()
        XCTAssertEqual(store.project.canvas, originalCanvas)
    }
    func testVersionOneMigrationPreservesProductionData() throws {
        var original = Project()
        original.canvases[0] = CanvasDefinition(width: 2688, height: 768)
        original.cues = [Cue(displayNumber: "A1", name: "Old name", note: "筆記", text: "繁體中文")]
        original.cues[0].style.fontSize = 91
        original.outputs = [OutputConfiguration(displayID: 123, canvasID: original.canvas.id)]
        // Build the exact legacy JSON shape (no language or translation fields).
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["projectFormatVersion"] = 1
        json.removeValue(forKey: "languages")
        var cues = try XCTUnwrap(json["cues"] as? [[String: Any]])
        cues[0].removeValue(forKey: "translations")
        json["cues"] = cues
        let migrated = try ProjectCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.projectFormatVersion, 12)
        XCTAssertEqual(migrated.cues, original.cues)
        XCTAssertEqual(migrated.outputs, original.outputs)
        XCTAssertEqual(migrated.canvases, original.canvases)
        XCTAssertEqual(migrated.languages.count, 1)
        XCTAssertTrue(migrated.languages[0].usesCueStyle)
        XCTAssertEqual(migrated.languages[0].frame.width, original.canvas.width * 0.9)
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(migrated)), migrated)
    }
    func testTranslationRoutingAndSnapshots() throws {
        var project = Project()
        let english = LanguageLayer(name: "English", frame: PixelFrame(x: 100, y: 700, width: 1500, height: 200))
        project.languages.append(english)
        project.cues = [Cue(text: "中文"), Cue(text: "下一句")]
        let id = project.cues[0].id
        project.setText("English", cueID: id, languageID: english.id)
        let a = OutputConfiguration(displayID: 1, canvasID: project.canvas.id)
        let b = OutputConfiguration(displayID: 2, canvasID: project.canvas.id)
        project.outputs = [a, b]
        project.languages[0].outputIDs = [a.id]
        project.languages[1].outputIDs = [b.id]
        var state = PlaybackState(); state.go(in: project)
        let snapshot = try XCTUnwrap(state.liveFrame)
        XCTAssertEqual(snapshot.layers(for: a.id).map(\.name), ["Surtitle 1"])
        XCTAssertEqual(snapshot.layers(for: b.id).map(\.name), ["English"])
        XCTAssertEqual(snapshot.layers(for: nil).count, 2)
        XCTAssertEqual(snapshot.text(for: english), "English")
        project.languages[1].frame.x = 300
        project.setText("Changed", cueID: id, languageID: english.id)
        project.languages[1].outputIDs = [a.id]
        state.blackout(); state.toggleBlackout()
        XCTAssertEqual(state.liveFrame, snapshot)
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(project)), project)
        project.moveCue(id: id, by: 1)
        XCTAssertEqual(project.cues[1].translations[english.id], "Changed")
        project.languages[1].isVisible = false
        XCTAssertEqual(LiveFrame(cue: project.cues[1], project: project).layers(for: nil).count, 1)
    }
    func testDragUsesCanvasPixelsAndAllowsOverflow() throws {
        let canvas = CanvasDefinition(width: 5760, height: 1080)
        let transform = try XCTUnwrap(CanvasTransform(canvas: canvas, viewportWidth: 960, viewportHeight: 400))
        let rect = PixelFrame(x: 100, y: 100, width: 1000, height: 200)
        let moved = rect.adjusted(dx: 50 / transform.scale, dy: 20 / transform.scale, resizing: false, canvas: canvas)
        XCTAssertEqual(moved.x, 400, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 220, accuracy: 0.0001)
        let clamped = rect.adjusted(dx: 10000, dy: -10000, resizing: false, canvas: canvas)
        XCTAssertEqual(clamped.x, 10100)
        XCTAssertEqual(clamped.y, -9900)
        let resized = rect.adjusted(dx: 10000, dy: -10000, resizing: true, canvas: canvas)
        XCTAssertEqual(resized.width, 11000)
        XCTAssertEqual(resized.height, 1)
    }
    func testInvalidRoutesAndGeometryRejected() throws {
        var project = Project()
        project.languages[0].outputIDs = [UUID()]
        XCTAssertThrowsError(try ProjectCodec.encode(project))
        project.languages[0].outputIDs = []
        project.languages[0].frame.width = -1
        XCTAssertThrowsError(try ProjectCodec.encode(project))
        project.languages[0].frame.width = 100
        let output = OutputConfiguration(displayID: 1, canvasID: project.canvas.id)
        project.outputs = [output, OutputConfiguration(displayID: 1, canvasID: project.canvas.id)]
        XCTAssertThrowsError(try ProjectCodec.encode(project))
    }
    @MainActor
    func testEditingAndOutputRemovalNeverBroadensRoutes() async {
        let store = ProjectStore()
        store.addCue()
        let cueID = store.selectedCue!.id
        let languageID = store.addLanguage()
        store.setText("Translation", cueID: cueID, languageID: languageID)
        XCTAssertEqual(store.selectedCue?.translations[languageID], "Translation")
        store.addOutput(displayID: 1); store.addOutput(displayID: 2)
        let a = store.project.outputs[0].id
        store.editLanguage(languageID) { $0.outputIDs = [a] }
        store.go()
        store.setLanguageFrame(languageID, frame: PixelFrame(x: 99999, y: -10, width: 400, height: 100))
        let layer = store.project.languages[1]
        XCTAssertEqual(layer.frame.x, 32768)
        XCTAssertEqual(layer.frame.y, -10)
        store.removeOutput(a)
        XCTAssertFalse(store.project.languages[1].isVisible)
        XCTAssertEqual(store.playback.liveFrame?.languages.first(where: { $0.id == languageID })?.frame, layer.frame)
        XCTAssertEqual(store.project.outputs.count, 1)
    }
    @MainActor
    func testIndependentOutputLayoutsAndSave() async throws {
        let store = ProjectStore()
        store.addCue(); let language = store.addLanguage()
        store.addOutput(displayID: 101); store.addOutput(displayID: 102)
        let a = store.project.outputs[0].id, b = store.project.outputs[1].id
        let originalB = try XCTUnwrap(store.layoutLanguage(language, outputID: b))
        store.setLanguageFrame(language, frame: PixelFrame(x: 200, y: 300, width: 600, height: 160), outputID: a)
        store.editLayoutLanguage(language, outputID: a) {
            $0.style.fontSize = 120; $0.isVisible = false
            $0.rotation = Rotation3D(x: 12, y: -8, z: 3)
        }
        XCTAssertEqual(store.layoutLanguage(language, outputID: b), originalB)
        XCTAssertEqual(store.layoutLanguage(language, outputID: a)?.rotation, Rotation3D(x: 12, y: -8, z: 3))
        store.go()
        let snapshot = try XCTUnwrap(store.playback.liveFrame)
        XCTAssertFalse(snapshot.layers(for: a).contains(where: { $0.id == language }))
        XCTAssertTrue(snapshot.layers(for: b).contains(where: { $0.id == language }))
        let decoded = try ProjectCodec.decode(ProjectCodec.encode(store.project))
        XCTAssertEqual(decoded, store.project)
        store.editLayoutLanguage(language, outputID: a) { $0.isVisible = true }
        XCTAssertNotEqual(store.playback.liveFrame, snapshot)
        XCTAssertTrue(try XCTUnwrap(store.playback.liveFrame).layers(for: a).contains(where: { $0.id == language }))
    }
    func testVersionTwoOutputMigration() throws {
        let project = Project()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        json["projectFormatVersion"] = 2
        let loaded = try ProjectCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.projectFormatVersion, 12)
        XCTAssertEqual(loaded.languages, project.languages)
    }

    func testVersionFourAddsTransitionAndRotationDefaults() throws {
        let project = Project()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        json["projectFormatVersion"] = 4
        json.removeValue(forKey: "transitions")
        var languages = try XCTUnwrap(json["languages"] as? [[String: Any]])
        languages[0].removeValue(forKey: "rotation")
        json["languages"] = languages
        let loaded = try ProjectCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.projectFormatVersion, 12)
        XCTAssertEqual(loaded.transitions, TransitionSettings())
        XCTAssertEqual(loaded.languages[0].rotation, Rotation3D())
    }

    @MainActor
    func testBlankOutputSlotsAndLaterDeviceAssignment() async throws {
        let store = ProjectStore()
        let slots = (0..<5).map { _ in store.addOutput() }
        XCTAssertEqual(store.project.outputs.count, 5)
        XCTAssertTrue(store.project.outputs.allSatisfy { $0.displayID == nil })
        store.assignDisplay(101, to: slots[2])
        XCTAssertEqual(store.project.outputs[2].displayID, 101)
        store.assignDisplay(101, to: slots[3])
        XCTAssertNil(store.project.outputs[3].displayID)
        XCTAssertNotNil(store.errorMessage)
        let decoded = try ProjectCodec.decode(ProjectCodec.encode(store.project))
        XCTAssertEqual(decoded.projectFormatVersion, 12)
        XCTAssertEqual(decoded.outputs, store.project.outputs)
    }

    @MainActor
    func testDuplicateSurtitleCopiesTextStyleAndOutputLayoutBesideSource() async throws {
        let store = ProjectStore()
        store.addCue()
        let cueID = store.selectedCue!.id
        let sourceID = store.project.languages[0].id
        store.setText("完整複製", cueID: cueID, languageID: sourceID)
        var style = TextStyle(); style.fontSize = 111
        store.modifyTextStyle(cueID: cueID, surtitleID: sourceID, property: .fontSize, style: style)
        let outputID = store.addOutput()
        store.setLanguageFrame(sourceID, frame: PixelFrame(x: 120, y: 240, width: 900, height: 180), outputID: outputID)
        let duplicateID = try XCTUnwrap(store.duplicateLanguage(sourceID))
        XCTAssertEqual(store.project.languages.map(\.id), [sourceID, duplicateID])
        XCTAssertEqual(store.project.text(for: store.selectedCue!, languageID: duplicateID), "完整複製")
        XCTAssertEqual(store.project.cues[0].styleOverrides[duplicateID], store.project.cues[0].styleOverrides[sourceID])
        XCTAssertEqual(store.layoutLanguage(duplicateID, outputID: outputID)?.frame,
                       store.layoutLanguage(sourceID, outputID: outputID)?.frame)
    }

    @MainActor
    func testLayoutNudgeUsesSelectedOutputAndSurtitle() async {
        let store = ProjectStore()
        let outputID = store.addOutput()
        let languageID = store.project.languages[0].id
        let original = store.layoutLanguage(languageID, outputID: outputID)!.frame
        store.layoutOutputID = outputID
        store.selectedSurtitleID = languageID
        store.nudgeSelectedLayout(dx: 1, dy: -1)
        let moved = store.layoutLanguage(languageID, outputID: outputID)!.frame
        XCTAssertEqual(moved.x, original.x + 1)
        XCTAssertEqual(moved.y, max(0, original.y - 1))
    }

}
