import SwiftUI

struct TreeNodeView: View {
    let node: FolderNode
    let searchText: String
    let level: Int
    @Binding var expandedNodes: Set<URL>
    @State private var isHovered = false
    
    private var isExpanded: Bool {
        expandedNodes.contains(node.url)
    }
    
    private var matchesSearch: Bool {
        searchText.isEmpty || node.url.lastPathComponent.localizedCaseInsensitiveContains(searchText)
    }
    
    var body: some View {
        if matchesSearch {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if !node.children.isEmpty {
                        Button(action: { toggleExpansion() }) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Image(systemName: node.children.isEmpty ? FileTag.iconName(for: node.url) : "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text(node.url.lastPathComponent)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                .padding(.leading, CGFloat(level * 16))
                .padding(.vertical, 4)
                .padding(.trailing, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                )
                .onHover { isHovered = $0 }
                
                if isExpanded {
                    ForEach(node.children) { child in
                        TreeNodeView(
                            node: child,
                            searchText: searchText,
                            level: level + 1,
                            expandedNodes: $expandedNodes
                        )
                    }
                }
            }
        }
    }
    
    private func toggleExpansion() {
        withAnimation(.spring(response: 0.2)) {
            if isExpanded {
                expandedNodes.remove(node.url)
            } else {
                expandedNodes.insert(node.url)
            }
        }
    }
} 