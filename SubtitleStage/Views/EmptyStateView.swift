import SwiftUI

/// macOS 13-compatible empty state, shared by the editor and output previews.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var description: String?
    init(_ title: String, systemImage: String, description: String? = nil) {
        self.title = title; self.systemImage = systemImage; self.description = description
    }
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let description { Text(description).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
