import SwiftUI

struct TreeSidebarView: View {
    let structure: FolderNode?
    @State private var expandedNodes = Set<URL>()
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search files", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if let tree = structure {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        TreeNodeView(
                            node: tree,
                            searchText: searchText,
                            level: 0,
                            expandedNodes: $expandedNodes
                        )
                    }
                    .padding(.vertical, 8)
                }
            } else {
                EmptyTreeView()
            }
        }
        .background(VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow))
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1)
                .offset(x: -0.5),
            alignment: .trailing
        )
    }
} 