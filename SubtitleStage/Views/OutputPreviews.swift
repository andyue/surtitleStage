import SwiftUI
import SubtitleCore

struct OutputPreviews: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var output: OutputManager
    var live: Bool
    var select: ((UUID) -> Void)? = nil
    var body: some View {
        if store.project.outputs.isEmpty {
            EmptyStateView("No outputs configured", systemImage: "display.2", description: "Add output slots now and assign displays later.")
        } else {
            // Playback fills the operator column; the layout overview keeps thumbnails.
            LazyVGrid(columns: live
                      ? [GridItem(.flexible(minimum: 0))]
                      : [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 16) {
                ForEach(Array(store.project.outputs.enumerated()), id: \.element.id) { index, config in
                    let size = config.resolution ?? output.displays.first(where: { $0.id == config.displayID })?.pixels ?? PixelSize(width: store.canvas(for: config.id).width, height: store.canvas(for: config.id).height)
                    VStack(alignment: .leading, spacing: 6) {
                        let frame = live ? store.playback.liveFrame : store.selectedCue.map { LiveFrame(cue: $0, project: store.project) }
                        CanvasView(frame: frame, canvas: store.project.canvas, blackout: false, outputID: config.id, previewResolution: size,
                                   opacity: live ? store.playback.visibleOpacity : 1,
                                   transitionDuration: live ? store.playback.transitionDuration : 0)
                            .aspectRatio(size.width / size.height, contentMode: .fit)
                            .overlay { Rectangle().stroke(Color.secondary, lineWidth: 1) }
                        if !config.isEnabled { Text("Disabled").foregroundStyle(.orange) }
                        Text(config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Output \(index + 1)" : config.name).font(.headline)
                        Text(config.displayID.flatMap { id in output.displays.first(where: { $0.id == id })?.name } ?? (config.displayID == nil ? "No device assigned" : "Assigned display unavailable"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.contentShape(Rectangle())
                        .onTapGesture { select?(config.id) }
                        .accessibilityAddTraits(select == nil ? [] : .isButton)
                        .help(select == nil ? "Live output preview" : "Open this output’s layout")
                }
            }.frame(maxWidth: .infinity)
        }
    }
}
