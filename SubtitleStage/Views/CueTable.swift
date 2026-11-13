import AppKit
import SwiftUI
import SubtitleCore

struct CueTable: View {
    @ObservedObject var store: ProjectStore
    @State private var focusedCell: CellID?
    @State private var focusRevision = 0
    private struct CellID: Hashable { let cueID: UUID; let languageID: UUID }
    private let columnWidth: CGFloat = 220

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(store.project.cues) { cue in
                            let height = CueRowMetrics.height(texts: store.project.languages.map { store.project.text(for: cue, languageID: $0.id) }, columnWidth: columnWidth)
                            HStack(spacing: 0) {
                                Toggle("Select cue \(cue.displayNumber) for batch editing", isOn: Binding(
                                    get: { store.checkedCueIDs.contains(cue.id) },
                                    set: { if $0 { store.checkedCueIDs.insert(cue.id) } else { store.checkedCueIDs.remove(cue.id) } }
                                )).labelsHidden().toggleStyle(.checkbox).frame(width: 28)
                                Button { store.deleteCue(id: cue.id) } label: {
                                    Image(systemName: "xmark").frame(width: 24, height: height)
                                }
                                .buttonStyle(.plain)
                                .disabled(store.playback.liveCueID == cue.id)
                                .help(store.playback.liveCueID == cue.id ? "The live cue cannot be deleted" : "Delete this entire cue row")
                                Button {
                                    focusedCell = nil; store.playback.selectedCueID = cue.id
                                } label: {
                                    Text(cue.displayNumber.isEmpty ? "—" : cue.displayNumber)
                                        .font(.system(size: 15, weight: .medium)).frame(width: 48, height: height)
                                        .background(store.playback.liveCueID == cue.id ? Color.green.opacity(0.85) : .clear)
                                        .foregroundStyle(store.playback.liveCueID == cue.id ? .black : .primary)
                                }.buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                                        focusedCell = nil
                                        store.playback.selectedCueID = cue.id
                                        store.showSelectedCue()
                                    })
                                    .help("Click to select; double-click to take this cue live")
                                ForEach(store.project.languages) { language in
                                    let cell = CellID(cueID: cue.id, languageID: language.id)
                                    CueCellTextView(
                                        text: Binding(get: { store.project.text(for: cue, languageID: language.id) },
                                                      set: { store.setText($0, cueID: cue.id, languageID: language.id) }),
                                        shouldFocus: focusedCell == cell,
                                        focusRevision: focusRevision,
                                        onSelect: { select(cell, requestFocus: false) },
                                        onEndEditing: { store.endHistoryGroup() },
                                        onNavigate: { navigate(from: cell, direction: $0) },
                                        onAddCue: {
                                            let id = store.addCue(after: cue.id, focusing: language.id)
                                            select(CellID(cueID: id, languageID: language.id), requestFocus: true)
                                        }
                                    )
                                    .frame(width: columnWidth, height: height)
                                    .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 1) }
                                }
                                Image(systemName: "equal")
                                    .frame(width: 30, height: height)
                                    .contentShape(Rectangle())
                                    .draggable(cue.id.uuidString)
                                    .help("Drag to reorder this cue")
                            }
                            .background(store.playback.selectedCueID == cue.id ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor))
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(height: 1) }
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first, let sourceID = UUID(uuidString: value) else { return false }
                                store.moveCue(id: sourceID, before: cue.id)
                                return true
                            }
                        }
                    } header: {
                        HStack(spacing: 0) {
                            Text("").frame(width: 28, height: 34)
                            Text("").frame(width: 24, height: 34)
                            Text("Cue").frame(width: 48, height: 34)
                            ForEach(store.project.languages) { language in
                                SurtitleHeader(store: store, language: language).frame(width: columnWidth, height: 34)
                                    .overlay(alignment: .leading) { Divider() }
                            }
                            Color.clear.frame(width: 30, height: 34)
                                .contentShape(Rectangle())
                                .dropDestination(for: String.self) { values, _ in
                                    guard let value = values.first, value.hasPrefix("surtitle:"),
                                          let id = UUID(uuidString: String(value.dropFirst(9))) else { return false }
                                    return store.moveSurtitle(id: id, to: nil)
                                }
                        }.background(.bar)
                    }
                }.frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
    }

    private func select(_ cell: CellID, requestFocus: Bool) {
        if focusedCell != cell { focusedCell = cell }
        if store.playback.selectedCueID != cell.cueID { store.playback.selectedCueID = cell.cueID }
        if store.selectedSurtitleID != cell.languageID { store.selectedSurtitleID = cell.languageID }
        if requestFocus { focusRevision += 1 }
    }

    private func navigate(from cell: CellID, direction: CellDirection) {
        guard let row = store.project.cues.firstIndex(where: { $0.id == cell.cueID }),
              let column = store.project.languages.firstIndex(where: { $0.id == cell.languageID }) else { return }
        let destination: (Int, Int)
        switch direction {
        case .left: destination = (row, max(0, column - 1))
        case .right: destination = (row, min(store.project.languages.count - 1, column + 1))
        case .up: destination = (max(0, row - 1), column)
        case .down: destination = (min(store.project.cues.count - 1, row + 1), column)
        }
        select(CellID(cueID: store.project.cues[destination.0].id,
                      languageID: store.project.languages[destination.1].id), requestFocus: true)
    }
}

enum CellDirection { case left, right, up, down }

private struct CueCellTextView: NSViewRepresentable {
    @Binding var text: String
    let shouldFocus: Bool
    let focusRevision: Int
    let onSelect: () -> Void
    let onEndEditing: () -> Void
    let onNavigate: (CellDirection) -> Void
    let onAddCue: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        let editor = NSTextView()
        editor.delegate = context.coordinator
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 18)
        editor.textContainerInset = NSSize(width: 5, height: 5)
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.string = text
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if editor.string != text, !editor.hasMarkedText() { editor.string = text }
        if shouldFocus, context.coordinator.lastFocusRevision != focusRevision {
            context.coordinator.lastFocusRevision = focusRevision
            DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CueCellTextView
        var lastFocusRevision = -1
        init(parent: CueCellTextView) { self.parent = parent }
        func textDidBeginEditing(_ notification: Notification) { parent.onSelect() }
        func textDidEndEditing(_ notification: Notification) { parent.onEndEditing() }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, !editor.hasMarkedText() else { return }
            parent.text = editor.string
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
                parent.onAddCue(); return true
            }
            let direction: CellDirection?
            if commandSelector == #selector(NSResponder.moveLeft(_:)) { direction = .left }
            else if commandSelector == #selector(NSResponder.moveRight(_:)) { direction = .right }
            else if commandSelector == #selector(NSResponder.moveUp(_:)) { direction = .up }
            else if commandSelector == #selector(NSResponder.moveDown(_:)) { direction = .down }
            else { direction = nil }
            if let direction { parent.onNavigate(direction); return true }
            return false
        }
    }
}

@MainActor
enum CueRowMetrics {
    private static let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>(); cache.countLimit = 12_000; return cache
    }()
    private(set) static var measurementCount = 0
    static func resetCache() { cache.removeAllObjects(); measurementCount = 0 }

    static func height(texts: [String], columnWidth: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 18)
        let width = max(1, columnWidth - 20)
        let height: CGFloat = texts.map { text -> CGFloat in
            let key = "\(width):\(text)" as NSString
            if let cached = cache.object(forKey: key) { return CGFloat(cached.doubleValue) }
            let measured = NSAttributedString(string: text + "\u{200b}", attributes: [.font: font])
                .boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            cache.setObject(NSNumber(value: Double(measured)), forKey: key)
            measurementCount += 1
            return measured
        }.max() ?? 0
        return max(34, ceil(height) + 12)
    }
}

private struct SurtitleHeader: View {
    @ObservedObject var store: ProjectStore
    let language: LanguageLayer
    @State private var editing = false
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 3) {
            Button { store.deleteSurtitle(id: language.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).padding(.leading, 5)
                .disabled(store.project.languages.count <= 1)
                .help("Delete this Surtitle column (Undo is available)")
            Group {
            if editing {
                TextField("Surtitle name", text: Binding(get: { language.name }, set: { value in store.editLanguage(language.id) { $0.name = value } }))
                    .textFieldStyle(.roundedBorder).padding(.horizontal, 6).focused($focused)
                    .onAppear { focused = true }
                    .onSubmit { editing = false }
                    .onChange(of: focused) { value in if !value { editing = false } }
            } else {
                Text(language.name).font(.headline).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    .onTapGesture { store.selectedSurtitleID = language.id }
                    .onTapGesture(count: 2) { editing = true; store.selectedSurtitleID = language.id }
                    .help("Click to select; double-click to rename this Surtitle")
            }
            }
            Image(systemName: "equal").padding(.horizontal, 5).contentShape(Rectangle())
                .draggable("surtitle:" + language.id.uuidString)
                .help("Drag left or right to reorder this Surtitle")
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, value.hasPrefix("surtitle:"),
                  let id = UUID(uuidString: String(value.dropFirst(9))) else { return false }
            return store.moveSurtitle(id: id, to: language.id)
        }
        .contextMenu {
            Button("Move Left") { store.moveSurtitle(id: language.id, by: -1) }
                .disabled(store.project.languages.first?.id == language.id)
            Button("Move Right") { store.moveSurtitle(id: language.id, by: 1) }
                .disabled(store.project.languages.last?.id == language.id)
            Button("Delete Surtitle") { store.deleteSurtitle(id: language.id) }
                .disabled(store.project.languages.count <= 1)
        }
    }
}
