import SwiftUI
import SubtitleCore

struct LayoutCanvas: View {
    @ObservedObject var store: ProjectStore
    @Binding var selectedLanguageID: UUID?
    let outputID: UUID?
    var body: some View {
        GeometryReader { geometry in
            let canvas = store.canvas(for: outputID)
            let frame = LiveFrame(cue: store.selectedCue ?? Cue(), project: store.project)
            if let transform = CanvasTransform(canvas: canvas, viewportWidth: geometry.size.width, viewportHeight: geometry.size.height) {
                ZStack(alignment: .topLeading) {
                    CanvasView(frame: frame, canvas: canvas, blackout: false, outputID: outputID, applyMapping: false)
                    Rectangle().stroke(.gray, lineWidth: 1)
                        .frame(width: canvas.width * transform.scale, height: canvas.height * transform.scale)
                        .offset(x: transform.offsetX, y: transform.offsetY)
                        .allowsHitTesting(false)
                    ForEach(frame.layers(for: outputID)) { language in
                        LanguageBox(language: language, canvas: canvas, transform: transform, selected: selectedLanguageID == language.id, select: {
                            selectedLanguageID = language.id
                            store.selectedSurtitleID = language.id
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }, update: { store.setLanguageFrame(language.id, frame: $0, outputID: outputID) })
                    }
                }
            }
        }.frame(minHeight: 250)
    }
}

private struct LanguageBox: View {
    let language: LanguageLayer
    let canvas: CanvasDefinition
    let transform: CanvasTransform
    let selected: Bool
    let select: () -> Void
    let update: (PixelFrame) -> Void
    @State private var dragOrigin: PixelFrame?
    var body: some View {
        let f = language.frame
        ZStack(alignment: .topLeading) {
            Rectangle().fill(selected ? Color.accentColor.opacity(0.08) : Color.clear)
            Rectangle().stroke(selected ? Color.accentColor : .gray, style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: selected ? [] : [5, 3]))
            Text(language.name).font(.caption).padding(3).background(selected ? Color.accentColor : .gray).foregroundStyle(.white)
            if selected {
                Rectangle().fill(Color.accentColor).frame(width: 14, height: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .highPriorityGesture(drag(resizing: true))
            }
        }
        .frame(width: f.width * transform.scale, height: f.height * transform.scale)
        .rotation3DEffect(.degrees(language.rotation.x), axis: (x: 1, y: 0, z: 0), perspective: 0)
        .rotation3DEffect(.degrees(language.rotation.y), axis: (x: 0, y: 1, z: 0), perspective: 0)
        .rotation3DEffect(.degrees(language.rotation.z), axis: (x: 0, y: 0, z: 1), perspective: 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .gesture(drag(resizing: false))
        .offset(x: transform.offsetX + f.x * transform.scale, y: transform.offsetY + f.y * transform.scale)
        .help("Click to select. Drag to move; drag the bottom-right handle to resize. Arrow keys move one canvas pixel.")
    }
    private func drag(resizing: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                select()
                if dragOrigin == nil { dragOrigin = language.frame }
                guard let origin = dragOrigin else { return }
                update(origin.adjusted(dx: value.translation.width / transform.scale, dy: value.translation.height / transform.scale, resizing: resizing, canvas: canvas))
            }
            .onEnded { _ in dragOrigin = nil }
    }
}
