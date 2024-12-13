import SwiftUI

struct FileTag: View {
    let url: URL
    let onRemove: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: url))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Text(url.lastPathComponent)
                .lineLimit(1)
                .font(.system(size: 12))
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "txt": return "doc.text.fill"
        case "md": return "doc.text.fill"
        case "swift": return "swift"
        case "js", "ts": return "curlybraces"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush.fill"
        case "json": return "curlybraces.square.fill"
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