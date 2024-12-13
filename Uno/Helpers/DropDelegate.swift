import SwiftUI
import UniformTypeIdentifiers

struct FileDropDelegate: DropDelegate {
    let item: URL
    let items: [URL]
    @Binding var draggedItem: URL?
    let reorderHandler: (Int, Int) -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedItem = draggedItem else { return false }
        guard let fromIndex = items.firstIndex(of: draggedItem),
              let toIndex = items.firstIndex(of: item) else { return false }
        
        if fromIndex != toIndex {
            reorderHandler(fromIndex, toIndex)
        }
        
        self.draggedItem = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              let fromIndex = items.firstIndex(of: draggedItem),
              let toIndex = items.firstIndex(of: item) else { return }
        
        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.3)) {
                reorderHandler(fromIndex, toIndex)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
} 
