import SwiftUI

struct FileTag: View {
    let url: URL
    let onRemove: () -> Void
    @Binding var draggedItem: URL?
    let items: [URL]
    let reorderHandler: (Int, Int) -> Void
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Self.iconName(for: url))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .opacity(isHovered ? 0.8 : 0.5)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(isHovered ? 0.15 : 0.1), 
                               lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.2), value: isHovered)
        .onDrag {
            self.draggedItem = url
            return NSItemProvider(object: url as NSURL)
        }
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(
            item: url,
            items: items,
            draggedItem: $draggedItem,
            reorderHandler: reorderHandler
        ))
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    static func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "txt": return "doc.text"
        case "md": return "text.justify.left"
        case "swift": return "swift"
        case "js", "ts": return "curlybraces"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush.fill"
        case "json": return "brackets"
        case "py": return "terminal.fill"
        case "java": return "cup.and.saucer.fill"
        case "cpp", "c": return "chevron.left.forwardslash.chevron.right"
        case "rb": return "diamond.fill"
        case "go": return "g.circle.fill"
        case "rs": return "gear"
        case "php": return "p.circle.fill"
        case "xml": return "tag.fill"
        case "yaml", "yml": return "doc.plaintext.fill"
        case "sh", "bash": return "terminal.fill"
        case "ipynb", "rmd", "qmd": return "book.fill"
        default: return "doc"
        }
    }
}