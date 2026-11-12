import SwiftUI

/// Tab selection is local: switching editor pages must not rebuild the cue table
/// and playback column. A fixed header avoids segmented/menu fitting oscillation.
struct EditWorkspaceView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var output: OutputManager
    @ObservedObject var osc: OSCController
    @ObservedObject var syphon: SyphonOutputManager
    @ObservedObject var ndi: NDIOutputManager
    @State private var selection = "Text Modify"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit").font(.headline)
            Picker("Edit page", selection: $selection) {
                Text("Layout Setting").tag("Layout")
                Text("Text Modify").tag("Text Modify")
                Text("OSC").tag("OSC")
                Text("Video Output").tag("Video Output")
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                Group {
                    if selection == "Layout" { LayoutView(store: store, output: output) }
                    else if selection == "OSC" { OSCSettingsView(controller: osc, store: store) }
                    else if selection == "Video Output" { VideoOutputView(store: store, syphon: syphon, ndi: ndi) }
                    else { TextModifyView(store: store) }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: selection) { _ in store.endHistoryGroup() }
    }
}
