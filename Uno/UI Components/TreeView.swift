import SwiftUI

struct TreeView: View {
    let root: FolderNode
    @State private var expandedNodes: Set<URL> = []
    @State private var searchText = ""
    
    var body: some View {
        List {
            ForEach([root], id: \.id) { node in
                TreeNodeView(
                    node: node,
                    searchText: searchText,
                    level: 0,
                    expandedNodes: $expandedNodes
                )
            }
        }
        .listStyle(SidebarListStyle())
    }
}